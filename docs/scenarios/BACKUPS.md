# 备份方案：逻辑 / 物理与 local / NFS / rsync

## 准备

完成 [公共准备](COMMON.md)，先确认数据库层健康，选择备份方式与存储目标。
备份默认关闭；恢复操作单独在隔离实例执行，见 [恢复演练](RESTORE.md)。

Ansible extra vars 中的字典会整体替换，因此不能只复制一段 `backup_config.enabled: true`
就覆盖完整备份配置。下面从当前唯一配置源生成完整本地备份字典，保留签名和校验参数：

```bash
umask 077
python3 - <<'PY'
from pathlib import Path
import yaml
source = yaml.safe_load(Path('inventory/group_vars/all.yml').read_text())
backup = source['backup_config']
backup.update(enabled=True, method='logical', type='local', threads=2)
backup['xtrabackup'].update(parallel=2, compress_threads=2)
with Path('inventory/backup.local.yml').open('x') as stream:
    yaml.safe_dump({'backup_config': backup}, stream, sort_keys=False)
PY
${EDITOR:-vi} inventory/backup.local.yml
```

已有 backup.local.yml 时生成器拒绝覆盖，直接编辑该文件。运行配置升级后，应与新默认字典
核对新增字段，尤其是 Percona 签名公钥配置。

## 选择方法

| 项目 | logical | xtrabackup |
| --- | --- | --- |
| 配置 | `method: logical` | `method: xtrabackup` |
| 工具 | MySQL Shell `util.dumpInstance` | 匹配版本线的 Percona XtraBackup |
| 恢复 | 逻辑导入到干净实例 | prepare 后 copy-back 到隔离数据目录 |
| 常用并行度 | `threads` | `xtrabackup.parallel` |

修改完整本地文件里的 `method` 即可切换。物理备份如希望在本轮执行 prepare，设置
`xtrabackup.prepare: true`；压缩输出会先解压再 prepare。准备阶段的内存由 `use_memory` 控制。
备份节点由 `run_on_host_group` 选择；选择 mysql_secondary 会在该组所有成员执行，不是只选一台。
执行组必须非空、属于 mysql_cluster，并复用原有主机名，不能用同地址别名重复执行。

## 选择目标

只修改生成字典中对应字段，保留其余内容：

| 类型 | 需要修改 / 准备 |
| --- | --- |
| local | `type: local`，`base_dir` 指向具备足够空间的本地目录 |
| nfs | `type: nfs`，先由系统管理将 NFS 挂载到 `base_dir` 所在路径；流程会检查真实 NFS 挂载 |
| rsync | `type: rsync`，配置 remote_host / remote_user / remote_dir，以及 SSH key 与 known_hosts |

rsync 先在备份节点的 base_dir 生成备份，再同步到远端，所以本地也需要足够空间。
SSH known_hosts 和可选私钥路径指的是**远端备份执行节点**上的文件，不是控制端文件。
known_hosts 要由 root 所有且不能被组/其他用户写入；私钥需 root 所有、0400 或 0600。
首次使用前通过可信渠道核对远端指纹，不关闭 StrictHostKeyChecking。

## 执行与验证

```bash
"$DEPLOY" --status --scope mysql "${COMMON_ARGS[@]}"
"$DEPLOY" --backup "${COMMON_ARGS[@]}" -e @inventory/backup.local.yml
```

成功时会按集群、时间和主机组织目录，并在启用 create_manifest 时生成清单。
记录备份时间、执行节点、方法、工具版本、目录和结果；核对备份退出码及清单，再执行隔离恢复。

```bash
# 默认执行组为 mysql_primary；如修改过 run_on_host_group，使用对应组名
ansible mysql_primary "${COMMON_ARGS[@]}" -b -m command \
  -a 'find /backup/mysql -name manifest.txt -type f'
```

若修改了 base_dir，同步修改观察命令的路径。备份成功不等于恢复验证成功。

## 排障与停止

- 备份默认关闭：确认最后一个 extra vars 文件含完整且 enabled=true 的字典。
- NFS 检查失败：先修复实际挂载，不能以普通目录假装 NFS。
- rsync 失败：核对执行节点的密钥、known_hosts、目标权限与远端目录。
- 空间不足：增加目标空间或清理经过确认的旧备份，再重跑；失败输出不能当作有效备份。
- 不再使用时不再调用该入口，并将本地 enabled 设为 false。项目没有自动创建定时任务。

不要在排障时关闭包签名校验，也不要用不匹配版本的 XtraBackup 强行 prepare。

启用 `xtrabackup.prepare` 后，流程会核对 `xtrabackup_checkpoints` 的实际状态；若同时压缩，
解压时删除本轮生成的压缩副本，避免以后再次解压覆盖已准备的数据页。最终产物为已准备的
非压缩目录。希望存储压缩备份时保持 `prepare: false`，恢复时只对工作副本解压和 prepare。
清单记录 `xtrabackup_state` 与保留的压缩文件数量，恢复步骤按检查点状态分支执行。
