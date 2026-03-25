# Quick Start

```bash
git clone <this-repo>
cd auto-install-mysql-innodb-cluster

# 1. 修改 inventory
vim inventory/hosts-with-dedicated-routers.yml

# 2. 检查主配置
vim inventory/group_vars/all.yml

# 3. 前置检查
./scripts/deploy_dedicated_routers.sh --check-prereq -i inventory/hosts-with-dedicated-routers.yml

# 4. 完整部署
./scripts/deploy_dedicated_routers.sh --production-ready -i inventory/hosts-with-dedicated-routers.yml

# 5. 查看状态
./scripts/deploy_dedicated_routers.sh --status -i inventory/hosts-with-dedicated-routers.yml
```

连接信息：

- HAProxy VIP：`3307` (RW) / `3308` (RO)
- Router 直连：`6446` (RW) / `6447` (RO)

更多说明见：

- `README.md`
- `DEPLOYMENT_COMPLETE_GUIDE.md`
