# 隔离恢复演练

本页恢复的是独立实例，不自动恢复整个 InnoDB Cluster，不切换业务流量。
先按 [备份方案](BACKUPS.md) 取得有效备份和备份时刻的数据基线，再准备一台与原集群网络隔离的目标主机。
目标不能连接原 Group Replication 网络，也不能被应用入口访问。

## 目标准备

- 安装与备份匹配的 MySQL 和工具版本，使用独立的恢复账号。
- 核对目标主机名、IP、数据目录和备份路径，确保不是原生产节点。
- 保留备份原件，只对工作副本执行解压、prepare 或导入。
- 恢复实例关闭自动加入复制组、复制自动启动和 event_scheduler。
- 物理恢复会带回原来的身份、账号和持久化变量；启动时禁用加载原持久化变量，防止自动连接原组。

在**恢复目标**的独立 MySQL 配置中加入以下项，确认服务确实加载该配置后再启动：

```ini
[mysqld]
plugin_load_add=group_replication.so
persisted_globals_load=OFF
group_replication_start_on_boot=OFF
skip_replica_start=ON
event_scheduler=OFF
```

这是恢复环境配置，不复制回生产；已有 plugin_load_add 时合并一次，不重复加载插件。
物理恢复使用备份内已有账号的凭据，目标原初始化密码可能不再有效。目标安装需支持 Group Replication 变量；没有加载该插件时，
先核对安装方式，不能把无法识别的配置报错当作恢复成功。

## 逻辑恢复

目标为干净、已启动的 MySQL 实例。将 dump 放在恢复主机可读目录，使用交互密码连接：

```bash
mysqlsh --no-defaults --uri restoreadmin@127.0.0.1:3306 --password --js
```

在 MySQL Shell 中执行，替换路径和业务库名。示例只恢复业务库，不导入原集群元数据或用户：

```javascript
shell.options.useWizards = false;
session.runSql('SET GLOBAL local_infile = ON');
try {
  util.loadDump('/srv/restore/logical-dump', {
    includeSchemas: ['app_db'],
    loadUsers: false,
    threads: 2
  });
} finally {
  session.runSql('SET GLOBAL local_infile = OFF');
}
```

仅对可信备份临时开启 local_infile。导入失败时保留日志和工作副本，不向原集群回写；
修复目标条件后根据 Shell 的恢复进度处理，不能为了重试而清空源数据库。

## 物理恢复

以下命令在隔离恢复主机执行。示例面向 systemd 的 RHEL 系 MySQL RPM 服务 `mysqld`；
其他发行版需核对实际服务名和配置位置。修改三个目录参数后分阶段执行：

```bash
set -euo pipefail
BACKUP=/srv/restore/physical-backup
WORK=/srv/restore/physical-work
DATADIR=/var/lib/mysql
SERVICE=mysqld

# 拒绝覆盖已有工作目录，保留原备份
sudo test -f "$BACKUP/xtrabackup_checkpoints"
sudo test ! -e "$WORK"
sudo mkdir -m 700 "$WORK"
sudo cp -a "$BACKUP/." "$WORK/"
```

先读取工作副本的实际检查点，而不是只根据最初的压缩开关决定操作。工具版本必须匹配备份来源：

```bash
STATE="$(sudo awk -F= '$1 ~ /^backup_type[[:space:]]*$/ {gsub(/[[:space:]]/, "", $2); print $2}' "$WORK/xtrabackup_checkpoints")"
case "$STATE" in
  full-prepared)
    echo '已完成 prepare，直接进入 copy-back'
    ;;
  full-backuped)
    if sudo find "$WORK" -type f \( -name '*.zst' -o -name '*.lz4' -o -name '*.qp' \) -print -quit | grep -q .; then
      sudo xtrabackup --decompress --remove-original --parallel=2 --target-dir="$WORK"
    fi
    sudo xtrabackup --prepare --use-memory=1G --target-dir="$WORK"
    ;;
  *)
    echo "未识别或不完整的备份状态：$STATE" >&2
    exit 1
    ;;
esac
sudo grep -Eq '^backup_type[[:space:]]*=[[:space:]]*full-prepared[[:space:]]*$' "$WORK/xtrabackup_checkpoints"
```

只在 WORK 副本操作。已 prepared 的旧备份可能同时保留 `.zst` 原件；不要再次解压覆盖已准备的
数据页。压缩原件不会被 `--copy-back` 复制到 datadir，参见
[Percona 解压与准备说明](https://docs.percona.com/percona-xtrabackup/8.4/prepare-compressed-backup.html)。
若解压中断，保留失败日志，从原件创建新的 WORK 副本再处理。
低资源实验可将 `--use-memory=1G` 降为 `128M`，并减少并行度，生产值按恢复主机资源选择。

确认成功后停止**目标**实例，保留它原来的数据目录，再 copy-back：

```bash
sudo systemctl stop "$SERVICE"
sudo test -d "$DATADIR"
SAVED="${DATADIR}.before-restore.$(date +%Y%m%d%H%M%S)"
sudo test ! -e "$SAVED"
sudo mv "$DATADIR" "$SAVED"
sudo install -d -o mysql -g mysql -m 750 "$DATADIR"
sudo xtrabackup --copy-back --target-dir="$WORK" --datadir="$DATADIR"
sudo chown -R mysql:mysql "$DATADIR"
```

若 datadir 是挂载点，移动会失败；先另规划空恢复目录并修改目标配置，不要为了继续而删除挂载点内容。
SELinux/AppArmor 环境需按目标目录恢复对应访问策略。确认上述隔离启动配置已生效，再执行：

```bash
sudo systemctl start "$SERVICE"
sudo systemctl is-active "$SERVICE"
```

## 验证

用恢复实例的受保护账号连接，检查：

```sql
SELECT @@hostname, @@server_uuid, @@GLOBAL.group_replication_start_on_boot;
SHOW DATABASES;
SELECT COUNT(*) FROM app_db.orders;
SHOW CREATE TABLE app_db.orders;
```

将示例库表名替换为自己的业务对象，与**备份时刻**的基线比较结构、行数、关键记录和
规范化数据摘要。行数相同不足以证明内容一致；旧备份也不应包含备份之后的新增事务。
保存 [恢复演练记录](../templates/restore-drill-record.md)，记录工具版本、耗时、命令及差异。

## 排障与退出

- 初始化或启动失败：检查目标配置加载、目录权限、安全策略和错误日志，不反复操作源节点。
- prepare 失败：保留工作副本与日志，核对工具版本、解压完成情况和空间。
- 结构打印形式不同：保存原始差异，进一步核对字段、字符集、索引和约束，不直接忽略。
- 演练完成后停止隔离实例并保留证据；重新入组或业务切换应另行规划，不能直接启动原身份节点接入生产。
- 回退演练仅恢复目标主机自己的目录与配置，原集群不受此流程修改。

## 工具参考

- [MySQL 持久化变量加载规则](https://dev.mysql.com/doc/refman/8.4/en/persisted-system-variables.html)
- [MySQL 副本启动选项](https://dev.mysql.com/doc/refman/8.4/en/replication-options-replica.html)
- [Percona XtraBackup 恢复](https://docs.percona.com/percona-xtrabackup/8.4/quickstart-restore-back.html)
