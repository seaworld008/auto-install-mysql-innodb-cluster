# 部署前检查清单

## 控制节点

- [ ] 控制节点使用 Python 3.12+
- [ ] Ansible / ansible-playbook / ansible-inventory 可用
- [ ] 已安装项目依赖：`pip install -r requirements.txt`

## 目标节点

- [ ] 真实拓扑只写入 Git 忽略的 `inventory/hosts.local.yml`，文件权限为 `0600`
- [ ] 优先使用仓库外的 SSH 私钥；如使用密码，仅保存在本地 inventory 或外部 Secret
- [ ] 已通过可信渠道逐台核验 SSH fingerprint，再写入 `~/.ssh/known_hosts`
- [ ] SSH host key 严格校验保持启用，未使用跳过校验参数
- [ ] 所有目标节点已预装 Python 3.9+；RHEL 8 已预装 `python39`，并可由 `auto_silent` 发现
- [ ] MySQL 节点数量不少于 3
- [ ] Router 节点数量不少于 2
- [ ] HAProxy 节点数量不少于 2
- [ ] 节点间网络互通
- [ ] 时间同步正常
- [ ] 存储挂载与 `/data/mysql` 规划完成

## 配置检查

- [ ] 已按 `inventory/README.md` 选择正确 inventory
- [ ] `inventory/group_vars/all.yml` 的非敏感配置已确认，未写入真实密码
- [ ] `inventory/vault.local.yml` 是有效 Vault 密文且未被 Git 跟踪，或已配置等价外部 Secret
- [ ] `mysql_hardware_profile` 已确认
- [ ] 已按 `docs/reference/VARIABLE_REFERENCE.md` 复核关键变量
- [ ] Vault / 外部 Secret 已覆盖三个 `CHANGE_ME_*` 业务密码占位符
- [ ] `keepalived_auth_pass` 已通过 Vault / 外部 Secret 覆盖，非占位值且不超过 8 个字符
- [ ] `server_id` 唯一
- [ ] `mysql_group_replication_group_name_override` 是当前独立集群专用的唯一 UUID，且解析后的 Group Replication group name 与其一致
- [ ] Keepalived 网卡名与真实系统一致
- [ ] 若启用备份，`backup_config` 已完整配置
- [ ] 若使用 rsync 备份，已通过可信渠道核验目标 SSH fingerprint，并预置 `backup_config.ssh_known_hosts_file`

## 验证记录

- [ ] 已准备 staging 验证记录：`docs/templates/staging-validation-record.md`
- [ ] 如涉及 HA 行为，已准备故障演练记录：`docs/templates/failover-drill-record.md`
- [ ] 如涉及备份恢复，已准备隔离恢复演练记录：`docs/templates/restore-drill-record.md`
- [ ] 截图和 CLI 输出会按 `docs/reference/ARCHITECTURE_AND_EVIDENCE.md` 脱敏留存

## 推荐执行顺序

```bash
git diff --check
ansible-inventory -i inventory/hosts.local.yml --list >/tmp/inventory-local.json
ansible-playbook -i inventory/hosts.local.yml playbooks/site.yml --syntax-check \
  --ask-vault-pass -e @inventory/vault.local.yml
./scripts/deploy_dedicated_routers.sh --check-prereq \
  -i inventory/hosts.local.yml \
  --ask-vault-pass -e @inventory/vault.local.yml
./scripts/deploy_dedicated_routers.sh --production-ready \
  -i inventory/hosts.local.yml \
  --ask-vault-pass -e @inventory/vault.local.yml
./scripts/deploy_dedicated_routers.sh --status \
  -i inventory/hosts.local.yml \
  --ask-vault-pass -e @inventory/vault.local.yml
```

## 参考

- `README.md`
- `DEPLOYMENT_COMPLETE_GUIDE.md`
- `docs/runbooks/OPERATOR_GUIDE.md`
- `inventory/README.md`
- `docs/reference/VARIABLE_REFERENCE.md`
- `docs/reference/ARCHITECTURE_AND_EVIDENCE.md`
- `docs/runbooks/TROUBLESHOOTING.md`

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
