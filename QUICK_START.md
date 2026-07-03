# Quick Start

```bash
git clone <this-repo>
cd auto-install-mysql-innodb-cluster

# 1. 修改 inventory
vim inventory/hosts-with-dedicated-routers.yml

# 或使用 HA inventory 向导生成推荐拓扑
./scripts/setup-servers.sh inventory/hosts-with-dedicated-routers.yml

# 2. 检查主配置
vim inventory/group_vars/all.yml

# 3. 本地 dry-run 级别检查（不连接目标机器）
git diff --check
ansible-inventory -i inventory/hosts-with-dedicated-routers.yml --list >/tmp/inventory-dedicated.json
ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/site.yml --syntax-check

# 4. 前置检查（连接目标机器，但不安装服务）
./scripts/deploy_dedicated_routers.sh --check-prereq -i inventory/hosts-with-dedicated-routers.yml

# 5. 完整部署
./scripts/deploy_dedicated_routers.sh --production-ready -i inventory/hosts-with-dedicated-routers.yml

# 6. 查看状态
./scripts/deploy_dedicated_routers.sh --status -i inventory/hosts-with-dedicated-routers.yml

# 7. 如只需批量执行内核优化
./scripts/deploy_dedicated_routers.sh --kernel-optimize-only -i inventory/hosts-with-dedicated-routers.yml
```

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
