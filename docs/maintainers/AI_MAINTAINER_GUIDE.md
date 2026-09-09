# AI Maintainer Guide

本文面向后续 AI / 自动化维护者。目标是在不创建平行流程、不泄露部署材料、不破坏
幂等与 fail-closed 门的前提下维护当前主线。

## 1. 先读顺序

1. `AGENTS.md`
2. `AI_CONTEXT.md`
3. `README.md`
4. `docs/runbooks/OPERATOR_GUIDE.md`
5. `inventory/README.md`
6. `inventory/group_vars/all.yml`
7. `scripts/deploy_dedicated_routers.sh`
8. `playbooks/validate-ha.yml`
9. 相关 playbook、role template 和测试

`AGENTS.md` 是更严格规则。代码与文档冲突时，以当前实现和
`inventory/group_vars/all.yml` 的实际行为为依据，并同步修正文档。

## 2. 单一真相源

- 非敏感运行时配置：`inventory/group_vars/all.yml`
- 主操作入口：`scripts/deploy_dedicated_routers.sh`
- 兼容包装：`deploy.sh`
- 主 CI 门：`.github/workflows/ansible-ci.yml`
- 本地拓扑：Git 忽略的 `inventory/hosts.local.yml`
- Secret：Git 忽略且加密的 Vault，或外部 Secret Manager

历史 `inventory/group_vars/all-*.yml` 只供参考。不要新增运行时配置副本、第二个
部署入口或永久“临时”脚本。

## 3. 当前支持主线

- MySQL Server 与 InnoDB Cluster 部署
- MySQL Router
- HAProxy + Keepalived VIP
- MySQL 扩容、切主与缩容
- Router / HAProxy 缩容
- 滚动应用配置
- MySQL Shell 逻辑备份
- Percona XtraBackup 物理备份
- `local` / `nfs` / `rsync` 备份目标
- fail-closed HA 健康检查

所有操作优先扩展 `scripts/deploy_dedicated_routers.sh`。

## 4. 安全不变量

### 4.1 Inventory 与 Secret

- tracked inventory 只保留脱敏示例，不得写入真实 IP、SSH 凭据、私钥或 Secret。
- `scripts/setup-servers.sh` 默认生成 Git 忽略的本地 inventory。
- 每个独立集群必须生成唯一
  `mysql_group_replication_group_name_override`。
- MySQL 密码与 Keepalived 口令通过 Vault / 外部 Secret 覆盖。
- 主入口必须继续透传 `-e` / `--extra-vars`、`--ask-vault-pass` 和
  `--vault-password-file`。
- 不要把密码放入命令行参数、日志、`debug` 或异常信息。
- `cluster-status.sh` 和 `failover-test.sh` 只能隐藏交互读取，或从受保护进程环境
  读取 `MYSQL_CLUSTER_PASSWORD`，并通过 stdin 传给 mysqlsh；禁止密码 argv。

### 4.2 SSH

- 全局和 inventory 必须严格校验 host key。
- 禁止 `StrictHostKeyChecking=no`。
- 禁止 `UserKnownHostsFile=/dev/null`。
- rsync 备份必须要求受保护、预置 fingerprint 的
  `backup_config.ssh_known_hosts_file`。
- rsync `known_hosts` 必须为 root 所有、group / other 不可写的普通文件；可选
  私钥必须为 root 所有普通文件，权限仅 `0400` / `0600`。

### 4.3 供应链

- GitHub Actions 使用完整 commit SHA。
- MySQL repo key 使用 URL、节点路径、本地 file URL 和 SHA-256 字典结构。
- Percona release DEB / RPM 使用固定 URL 与 SHA-256。
- 不要把 checksum 改为“下载最新”或跳过校验。
- 控制节点 `requirements.txt` 只包含带范围的 `ansible-core`；collections
  单独声明。控制节点要求 Python 3.12+，目标节点首次连接前要求 Python 3.9+，
  目标 PyMySQL 由可信系统仓库安装。

## 5. 运行时不变量

### 5.1 集群与 Router 幂等

- Router 已有 bootstrap 配置时默认跳过。
- 只有显式 `mysql_router_rebootstrap: true` 才重建 Router。
- bootstrap 不创建跨节点共享 Router 账号；密码只从标准输入传入。
- Cluster 配置先查询成员身份；只有 standalone 节点运行配置检查并加入，已有成员
  不得重复运行 `configureInstance`。
- 收敛完成必须确认 Cluster `OK`，且所有预期成员 `ONLINE`。

### 5.2 缩容

- 破坏性动作必须显式。
- `--limit` 型缩容必须精确匹配一台主机。
- 缩容后不能低于相应最小节点数。
- MySQL 缩容必须唯一解析目标 UUID 和当前 ONLINE primary。
- 移除当前 primary 前必须显式选择不同的有效新 primary。
- 默认不清理 MySQL 数据目录。
- MySQL 缩容完成后再次验证 `OK` 与剩余成员 `ONLINE`。

### 5.3 入口层

- HAProxy 只接 Router，不能恢复静态 MySQL primary 后端。
- stats 默认只绑定 `127.0.0.1`。
- Keepalived 直接检查 HAProxy systemd 状态，使用 `weight 0`；达到 fall 阈值
  进入 `FAULT` 并释放 VIP。
- Keepalived 配置包含口令，目标文件必须为 root `0600`，渲染任务保持 `no_log`。
- 回滚应先停 Keepalived，再停 HAProxy 与 Router；错误不能被吞掉。

### 5.4 MySQL datadir

- 自定义 datadir 只能从发行包已初始化的默认目录迁移。
- 目标目录非空且未初始化时必须阻断。
- 迁移前写入 0600 中断标记；中断重跑时继续幂等 rsync，完成后写完成标记并清理
  中断标记。
- 迁移时停止服务、使用 rsync、收敛权限，并同时处理 AppArmor 和启用状态下的
  SELinux 持久文件上下文 / `restorecon`。
- 配置写入后执行 `mysqld --validate-config`。
- 启动后查询 `@@datadir`，要求与配置一致。
- RedHat 重跑先用 0600 临时 option file 探测目标 root 密码；已生效时跳过首次
  临时密码流程，没有安全恢复路径时阻断。相关任务保持 `no_log`。

### 5.5 备份

- `backup_config.enabled` 默认 `false`。
- `logical` 使用 MySQL Shell `util.dumpInstance`。
- `xtrabackup` 使用受校验的 Percona 仓库包。
- 压缩 XtraBackup 且同一轮启用 prepare 时，必须先 `--decompress` 再
  `--prepare`。
- 备份成功不是恢复成功；恢复必须在隔离环境演练。

## 6. 健康检查契约

`playbooks/validate-ha.yml` 是组合门，先导入 preflight，再导入
`playbooks/health-check-ha.yml`。`--status`、`--test-connection` 和部署后的
profile 验证都不能绕过 preflight。运行时部分要求：

- 每个 inventory MySQL 节点是本地 `ONLINE` 成员
- InnoDB Cluster 状态严格等于 `OK`，且成员数与 inventory 一致
- 所有 Router 的服务和 RW / RO / R/W Split 端口可用
- 所有入口节点的 HAProxy、Keepalived 和三个业务端口可用
- VIP 恰好出现在一个 `haproxy_lb` 节点上

不要将失败降级为 warning、加 `ignore_errors` 或在 shell 包 `|| true`。

## 7. 变更顺序

行为变更按以下顺序：

1. 修改 `inventory/group_vars/all.yml`
2. 修改真正消费变量的 playbook / template / 主入口
3. 添加或更新 `tests/` 契约
4. 同步 README、指南、变量参考和 runbook
5. 运行本地静态检查
6. 运行全部 playbook syntax-check 与三个主 inventory 解析
7. 提交 PR，等待 required checks
8. 合并后以 exact main SHA 创建 tag 和 Release

如果变量没有消费者，就删除它或完成实现，不要保留“看起来支持”的配置。

## 8. CI 与验证

当前 CI 包含：

- Python 3.12 / 3.13 矩阵
- `pip check`
- shell `bash -n`
- `validate_deployment.ps1` PowerShell parser
- `git diff --check`
- Python unit / repository contract tests
- 全部 `playbooks/*.yml` syntax-check
- 三个主 inventory 的 site syntax-check 与 JSON 解析
- deprecated MySQL option guard
- 固定版本、阻断式 Markdown / YAML lint
- GitHub Actions CodeQL
- pip / GitHub Actions Dependabot

仓库默认 VIP `192.0.2.100` 是 RFC 5737 占位值，会被 preflight 阻断。实际
环境必须覆盖为已确认且未冲突的 IPv4；真实私网中的 `192.168.1.100` 可用。

本地最低门：

```bash
git diff --check
for script in deploy.sh validate_deployment.sh scripts/*.sh; do
  bash -n "$script" || exit 1
done
./.venv/bin/python -m unittest discover tests
npx --yes markdownlint-cli2@0.23.2
./.venv/bin/yamllint .

for inventory in \
  inventory/hosts.yml \
  inventory/hosts-ha-reference.yml \
  inventory/hosts-with-dedicated-routers.yml
do
  ./.venv/bin/ansible-playbook -i "$inventory" playbooks/site.yml --syntax-check
  ./.venv/bin/ansible-inventory -i "$inventory" --list >/dev/null
done
```

修改 playbook 时还应对全部 `playbooks/*.yml` 执行 syntax-check；
`playbooks/shrink-mysql.yml` 需要提供测试用 target / new-primary extra vars。

## 9. 文档与 ADR

行为变更需要同步：

- `README.md`
- `QUICK_START.md`
- `DEPLOYMENT_COMPLETE_GUIDE.md`
- `PRE_DEPLOYMENT_CHECKLIST.md`
- `docs/runbooks/OPERATOR_GUIDE.md`
- `docs/reference/VARIABLE_REFERENCE.md`

文档 lint 已是阻断门，不再是 advisory。ADR 应记录为什么选择某个昂贵且长期的架构
方向，不要仅复述代码。

## 10. 不能宣称的结论

静态检查、CI、tag 或 GitHub Release 都不能证明：

- 完整生产就绪
- 故障切换和客户端重连已验证
- 扩缩容已在真实集群通过
- 备份可恢复
- 性能或容量满足目标

只有带 exact commit / tag、环境信息、命令、时间和脱敏输出的真实演练记录才能支撑
这些结论。没有执行时，准确写：

> 静态验证和 Ansible syntax / inventory 校验已通过；真实 staging 验证仍待完成。

## 资料与证据索引

README 和文档首页专注使用者路径；版本说明进入 CHANGELOG，用户需要的兼容条件进入
runbook。调试过程和演练结果不追加到产品首页，也不能用文档清理代替修复或验收。

- [本地模拟方案](../runbooks/LOCAL_SIMULATION.md)
- [历史模拟报告](../reports/LOCAL_SIMULATION_2026-09-08.md)
- [架构与证据记录](../reference/ARCHITECTURE_AND_EVIDENCE.md)
- [容量分析](../reports/HARDWARE_CAPACITY_ANALYSIS.md)
- [Staging 模板](../templates/staging-validation-record.md)
- [故障演练模板](../templates/failover-drill-record.md)
- [隔离恢复模板](../templates/restore-drill-record.md)
- [发布检查](RELEASE_CHECKLIST_ZH.md)
