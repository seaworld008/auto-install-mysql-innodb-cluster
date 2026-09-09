# 部署前检查清单

## 控制节点

- [ ] 控制节点使用 Python 3.12+
- [ ] 已安装 `collections/requirements.yml` 声明的 collections
- [ ] Ansible / ansible-playbook / ansible-inventory 可用
- [ ] 已安装项目依赖：`pip install -r requirements.txt`

## 目标节点

安装流程接受 RHEL 系 8/9/10、Ubuntu jammy/noble/plucky/questing、Debian bookworm/trixie；
具体安装源和解释器要求以 `inventory/group_vars/all.yml` 为准。发行版支持范围不等于
每种系统安全策略与硬件组合已经完成生产验收。

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
ansible-inventory -i inventory/hosts.local.yml --list >/dev/null
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

## 应用接入

- [ ] 已按 [应用接入指南](docs/runbooks/APPLICATION_CONNECTIONS.md) 选择端口与重试策略
- [ ] 使用受信任 CA 和匹配连接名称的证书，验证两段 TLS 链路
- [ ] 已部署集群的 override 与实际组 UUID 一致，未尝试热改组身份
