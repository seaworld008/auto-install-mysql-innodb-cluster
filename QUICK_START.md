# Quick Start

```bash
git clone https://github.com/seaworld008/auto-install-mysql-innodb-cluster.git
cd auto-install-mysql-innodb-cluster

# 控制节点需要 Python 3.12+；所有目标节点需预装 Python 3.9+
# RHEL 8 请先预装 python39
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
ansible-galaxy collection install -r collections/requirements.yml

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
ansible-inventory -i inventory/hosts.local.yml --list >/dev/null
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

在 Vault 编辑器中填写以下字段，将占位值替换为独立的强密码；VRRP 口令最长 8 个字符：

```yaml
mysql_root_password: "CHANGE_ME_ROOT_PASSWORD"
mysql_cluster_password: "CHANGE_ME_CLUSTER_PASSWORD"
mysql_replication_password: "CHANGE_ME_REPLICATION_PASSWORD"
keepalived_auth_pass: "CHANGE_ME"
```

按向导确认 VIP、网卡与节点地址。业务连接使用另行创建的最小权限账号。

`inventory/hosts.local.yml`、`inventory/vault.local.yml` 和本地备份均不会被 Git 跟踪。仓库内 `hosts-*.yml` 仅用于脱敏示例与 CI；禁止向其中写入真实 IP、密码或私钥路径。向导会为当前独立集群生成唯一 `mysql_group_replication_group_name_override`，不能跨集群复用。SSH host key 校验默认启用，不能使用跳过校验的参数。

`--ask-vault-pass` 在多阶段流程中可能重复询问。自动化推荐改用仓库外、
权限 `0600` 的 `--vault-password-file`；禁止把 Vault 口令文件提交到 Git。

连接信息：

- HAProxy VIP：`3309` (可选自动读写分离，先验证应用兼容性)
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

事务型应用优先选择 `3307`，并使用有界应用连接池。证书与连接池配置见 [应用接入指南](docs/runbooks/APPLICATION_CONNECTIONS.md)。

## 其他拓扑与组件操作

默认示例之外，可选择 [独立、共置、混合或三节点接入层](docs/scenarios/README.md)。
[组件指南](docs/scenarios/COMPONENTS.md) 覆盖只部署 MySQL、Router、HAProxy、Keepalived；
[内核专项](docs/scenarios/KERNEL.md) 可单独执行。只读状态检查使用 `--scope` 选择范围，
默认 full 保留全部 HA 检查；该选项不能用于缩减完整部署范围。

新生成的 inventory 使用每台主机的 `ansible_host` 作为 `mysql_report_host`，
使新集群可以按 IPv4 地址发现成员。手动维护 inventory 时，按
[通告地址说明](docs/scenarios/CONFIGURATION.md#数据库通告地址与-dns) 配置；
使用系统主机名时必须提前做好各节点之间的 DNS/hosts 解析。
已有集群的注册地址应保持不变。
