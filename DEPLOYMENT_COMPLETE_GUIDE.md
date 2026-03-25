# MySQL InnoDB Cluster 部署总览

当前仓库的生产主线已经统一为：

1. 修改 `inventory/hosts-*.yml`
2. 检查 `inventory/group_vars/all.yml`
3. 执行前置检查
4. 执行部署
5. 执行健康检查
6. 根据需要执行扩容、缩容、配置滚动应用或可选备份

说明：

- 走主入口脚本执行完整部署或单独部署时，默认会对对应目标节点执行内核优化。
- 缩容与备份不会额外触发内核优化。
- 如需跳过，可在主入口脚本中使用 `--skip-kernel-optimization`。
- 如需单独执行内核优化，可使用 `--kernel-optimize-only`。

## 推荐入口

- 主入口脚本：`./scripts/deploy_dedicated_routers.sh`
- 主配置文件：`inventory/group_vars/all.yml`
- 前置检查：`playbooks/preflight-ha.yml`
- 健康检查：`./scripts/health-check-ha.sh`

## 推荐命令

```bash
# 完整部署
./scripts/deploy_dedicated_routers.sh --production-ready -i inventory/hosts-with-dedicated-routers.yml

# 查看状态
./scripts/deploy_dedicated_routers.sh --status -i inventory/hosts-with-dedicated-routers.yml

# 滚动应用当前配置
./scripts/deploy_dedicated_routers.sh --apply-config -i inventory/hosts-with-dedicated-routers.yml

# 仅执行内核优化
./scripts/deploy_dedicated_routers.sh --kernel-optimize-only -i inventory/hosts-with-dedicated-routers.yml

# 仅部署 Router
./scripts/deploy_dedicated_routers.sh --install-routers -i inventory/hosts-with-dedicated-routers.yml

# 仅部署 HAProxy + Keepalived
./scripts/deploy_dedicated_routers.sh --configure-lb -i inventory/hosts-with-dedicated-routers.yml

# MySQL 扩容
./scripts/deploy_dedicated_routers.sh --scale-mysql-add --limit mysql-node4 -i inventory/hosts-with-dedicated-routers.yml

# MySQL 缩容
./scripts/deploy_dedicated_routers.sh --scale-mysql-remove --target mysql-node3 --new-primary mysql-node2 -i inventory/hosts-with-dedicated-routers.yml

# 可选备份（默认关闭，需先启用 backup_config.enabled=true）
./scripts/deploy_dedicated_routers.sh --backup -i inventory/hosts-with-dedicated-routers.yml
```

## 连接模型

- HAProxy VIP 自动读写分离：`3309`
- HAProxy VIP 强制读写：`3307`
- HAProxy VIP 强制只读：`3308`
- 直连 Router 自动读写分离：`6450`
- 直连 Router 强制读写：`6446`
- 直连 Router 强制只读：`6447`

## 详细文档

- 主说明：`README.md`
- 备份恢复：`docs/BACKUP_AND_RESTORE_GUIDE.md`
- HA 蓝图：`docs/DEPLOYMENT_HA_BLUEPRINT_ZH.md`
- 容量分析：`docs/HARDWARE_CAPACITY_ANALYSIS.md`
- Router 说明：`docs/ROUTER_DEPLOYMENT_COMPLETE.md`
- 交叉验证：`docs/MYSQL80_CLUSTER_CROSS_VALIDATION.md`
- 发布清单：`docs/RELEASE_CHECKLIST_ZH.md`
