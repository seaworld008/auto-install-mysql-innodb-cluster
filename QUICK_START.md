# Quick Start

```bash
git clone <this-repo>
cd auto-install-mysql-innodb-cluster

# 控制节点需要 Python 3.12+；所有目标节点需预装 Python 3.9+
# RHEL 8 请先预装 python39

# 1. 生成被 Git 忽略的本地 inventory（默认权限 0600）
./scripts/setup-servers.sh

# 2. 在加密编辑器中写入三个 MySQL 密码和不超过 8 个字符的
#    keepalived_auth_pass
ansible-vault create inventory/vault.local.yml

# 3. 只检查非敏感主配置，不要写入真实 IP 或明文密码
vim inventory/group_vars/all.yml

# 4. 按 docs/runbooks/SERVER_CONFIGURATION.md 核验每台主机的
#    SSH fingerprint，确认一致后写入 ~/.ssh/known_hosts

# 5. 本地 dry-run 级别检查（不连接目标机器）
git diff --check
ansible-inventory -i inventory/hosts.local.yml --list >/tmp/inventory-local.json
ansible-playbook -i inventory/hosts.local.yml playbooks/site.yml --syntax-check \
  --ask-vault-pass -e @inventory/vault.local.yml

# 6. 前置检查（连接目标机器，但不安装服务）
./scripts/deploy_dedicated_routers.sh --check-prereq \
  -i inventory/hosts.local.yml \
  --ask-vault-pass -e @inventory/vault.local.yml

# 7. 完整部署
./scripts/deploy_dedicated_routers.sh --production-ready \
  -i inventory/hosts.local.yml \
  --ask-vault-pass -e @inventory/vault.local.yml

# 8. 查看状态
./scripts/deploy_dedicated_routers.sh --status \
  -i inventory/hosts.local.yml \
  --ask-vault-pass -e @inventory/vault.local.yml

# 9. 如只需批量执行内核优化
./scripts/deploy_dedicated_routers.sh --kernel-optimize-only \
  -i inventory/hosts.local.yml \
  --ask-vault-pass -e @inventory/vault.local.yml
```

`inventory/hosts.local.yml`、`inventory/vault.local.yml` 和本地备份均不会被 Git 跟踪。仓库内 `hosts-*.yml` 仅用于脱敏示例与 CI；禁止向其中写入真实 IP、密码或私钥路径。向导会为当前独立集群生成唯一 `mysql_group_replication_group_name_override`，不能跨集群复用。SSH host key 校验默认启用，不能使用跳过校验的参数。

`--ask-vault-pass` 在多阶段流程中可能重复询问。自动化推荐改用仓库外、
权限 `0600` 的 `--vault-password-file`；禁止把 Vault 口令文件提交到 Git。

连接信息：

- HAProxy VIP：`3309` (自动读写分离，推荐默认入口)
- HAProxy VIP：`3307` (强制 RW) / `3308` (强制 RO)
- Router 直连：`6450` (自动读写分离) / `6446` (强制 RW) / `6447` (强制 RO)

更多说明见：

- `README.md`
- `README_EN.md`
- `DEPLOYMENT_COMPLETE_GUIDE.md`
- `docs/runbooks/OPERATOR_GUIDE.md`
- `inventory/README.md`
- `docs/reference/VARIABLE_REFERENCE.md`
- `docs/reference/ARCHITECTURE_AND_EVIDENCE.md`

## v0.3.1 部署修复与升级注意事项

- 首次安装不再依赖其他 MySQL 节点尚未采集的 facts；Group Replication 使用
  `ansible_host`，未定义时使用 inventory 主机名。该地址必须能被所有集群节点直接访问；
  SSH NAT / 跳板地址不能作为数据库节点地址，需为节点使用可互通的 inventory 地址。
- Ubuntu 24.04/25.04/25.10 与 Debian 13 使用 `libaio1t64`，旧发行版使用 `libaio1`。
- 任一节点失败即中止后续部署批次与操作；MySQL 滚动批次固定要求一台。
- `mysql_primary` 必须有一个管理节点，`mysql_secondary` 覆盖其余集群成员。
- 已有 Router 的端口、连接数、超时与路由策略由 `--apply-config` 原子更新；
  保留 Router 身份和 keyring，有变化才重启，并按节点完成连接验证。
  自动读写分离统一到 `routing:bootstrap_rw_split`，清除历史重复路由。
- `--limit` 仅支持 MySQL 扩容、Router/LB 缩容和内核优化；其他操作传入该参数会在
  执行前报错，避免静默变成全组操作。全组配置更新使用 `--apply-config`。
- 当前配置中未被消费的 Router 线程、内存、连接池和 metadata 缓存字段已移除。

升级前保存受保护的现有配置，在维护窗口执行 `--check-prereq`、`--apply-config` 和
`--status`。自定义 Router 路由名称不属于本仓库 bootstrap 结构，会被明确拒绝；
先人工核对迁移，不能通过清空 keyring 或自动强制 bootstrap 绕过。

静态及本地回归测试不替代真实环境验收。首次部署、重复执行、故障切换、扩缩容、
备份恢复和容量测试仍需在隔离 staging 执行并留存记录。

## v0.4.0 模拟验证与运行修复

本版集成 Rocky/MySQL 8.4 实测的包冲突、caching_sha2 账号、secondary 重复授权、
mysqlsh 认证、Router bootstrap、Keepalived 脚本安全和 Percona RPM 公钥修复。
管理账号在独立实例或当前在线 primary 收敛，secondary 依赖复制；不关闭只读保护。
升级时应在 staging 运行完整部署与重复执行；`--apply-config` 不承担包安装与账号迁移。

外置盘本地模拟使用独立 Lima VM（6 CPU / 12 GiB），配置生成、重建、测试顺序与
定向清理见 [本机模拟方案](docs/runbooks/LOCAL_SIMULATION.md)。低资源档位
`simulation_minimal` 仅用于模拟；50 总连接对应 45 用户连接，生产默认规格保持原值。

[实测报告](docs/reports/LOCAL_SIMULATION_2026-09-08.md)记录了通过及未通过项。
混合端口事务路由、严格 TLS 和组 UUID 配置归属仍待解决，不能据此声明已完成生产验收。
