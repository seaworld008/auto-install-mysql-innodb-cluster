# MySQL InnoDB Cluster 部署总览

当前仓库的生产主线已经统一为：

1. 修改 `inventory/hosts-*.yml`
2. 检查 `inventory/group_vars/all.yml`
3. 执行本地 dry-run 级别检查
4. 执行目标环境前置检查
5. 执行部署
6. 执行健康检查
7. 根据需要执行扩容、缩容、配置滚动应用或可选备份

说明：

- 走主入口脚本执行完整部署或单独部署时，默认会对对应目标节点执行内核优化。
- 缩容与备份不会额外触发内核优化。
- 如需跳过，可在主入口脚本中使用 `--skip-kernel-optimization`。
- 如需单独执行内核优化，可使用 `--kernel-optimize-only`。

## 推荐入口

- 主入口脚本：`./scripts/deploy_dedicated_routers.sh`
- 主配置文件：`inventory/group_vars/all.yml`
- Inventory 选择说明：`inventory/README.md`
- 操作员指南：`docs/runbooks/OPERATOR_GUIDE.md`
- 前置检查：`playbooks/preflight-ha.yml`
- 健康检查：`./scripts/health-check-ha.sh`

## 推荐命令

```bash
# 本地 dry-run 级别检查
git diff --check
ansible-inventory -i inventory/hosts-with-dedicated-routers.yml --list >/tmp/inventory-dedicated.json
ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/site.yml --syntax-check

# 目标环境前置检查
./scripts/deploy_dedicated_routers.sh --check-prereq -i inventory/hosts-with-dedicated-routers.yml

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

## 幂等性与重复执行

- `--check-prereq`、`--status`、`--test-connection` 适合反复执行。
- `--production-ready` 会执行完整部署链路，重复执行可能重新渲染配置、reload/restart 服务和再次执行内核优化。生产环境建议在首次部署或维护窗口中使用。
- 修改 `inventory/group_vars/all.yml` 后，优先使用 `--apply-config` 滚动应用。
- Router 默认不会重复 bootstrap，除非显式设置 `mysql_router_rebootstrap: true`。
- 缩容、停止入口层、数据清理等动作必须显式触发。

更完整的 dry-run、重复执行和配置变更说明见 `docs/runbooks/OPERATOR_GUIDE.md`。

## 连接模型

- HAProxy VIP 自动读写分离：`3309`
- HAProxy VIP 强制读写：`3307`
- HAProxy VIP 强制只读：`3308`
- 直连 Router 自动读写分离：`6450`
- 直连 Router 强制读写：`6446`
- 直连 Router 强制只读：`6447`

## 详细文档

- 主说明：`README.md`
- 英文入口：`README_EN.md`
- 操作员上手与变更：`docs/runbooks/OPERATOR_GUIDE.md`
- 服务器配置：`docs/runbooks/SERVER_CONFIGURATION.md`
- 备份恢复：`docs/runbooks/BACKUP_AND_RESTORE_GUIDE.md`
- 故障排查：`docs/runbooks/TROUBLESHOOTING.md`
- HA 蓝图：`docs/reference/DEPLOYMENT_HA_BLUEPRINT_ZH.md`
- 架构图与证据留存：`docs/reference/ARCHITECTURE_AND_EVIDENCE.md`
- 变量参考与配置示例：`docs/reference/VARIABLE_REFERENCE.md`
- 交叉验证：`docs/reference/MYSQL80_CLUSTER_CROSS_VALIDATION.md`
- Staging 验证模板：`docs/templates/staging-validation-record.md`
- 故障演练模板：`docs/templates/failover-drill-record.md`
- 隔离恢复演练模板：`docs/templates/restore-drill-record.md`
- 文档站点入口：`docs/index.md`
- 发布清单：`docs/maintainers/RELEASE_CHECKLIST_ZH.md`

历史分析报告位于 `docs/reports/`，可用于理解容量推导和旧方案背景，但运行时配置仍以 `inventory/group_vars/all.yml` 为准。
