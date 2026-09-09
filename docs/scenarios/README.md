# 部署方案与操作手册

先按资源和故障域选择拓扑，再按组件选择操作。所有方案复用
`scripts/deploy_dedicated_routers.sh`，参数源仍是 `inventory/group_vars/all.yml`。

## 按部署方案选择

| 方案 | 物理主机 | MySQL / Router / HAProxy+Keepalived | 适用情况 | 详细步骤 |
| --- | ---: | --- | --- | --- |
| 独立部署 | 7 | 3 / 2 / 2 | 希望分别规划数据库、路由与入口资源 | [独立部署](DEDICATED.md) |
| 三主机共置 | 3 | 3 / 3 / 3 | 主机较少，接受组件共享故障域 | [共置部署](COLOCATED.md) |
| 混合部署 | 5 | 3 / 2（共置）/ 2（独立） | Router 与数据库共置，入口保持独立 | [混合部署](MIXED.md) |
| 三 Router、三入口 | 9 | 3 / 3 / 3 | 需要更多路由与入口节点 | [三节点接入层](THREE_ENTRY.md) |
| 只部署数据库或逐层接入 | 按阶段 | 先 MySQL，再 Router，再入口 | 已有集群或希望分阶段实施 | [组件单独部署](COMPONENTS.md) |
| 本机模拟 | 独立 VM 内 | 按本地方案 | 功能验证、学习与贡献 | [本地模拟](../runbooks/LOCAL_SIMULATION.md) |

物理主机数不含 Ansible 控制端。增加 Router/LB 不会改变 MySQL 复制组的多数派；
三台 Keepalived 仍只提供一个 VIP，不代表三台入口同时持有该地址。

## 按具体任务选择

| 任务 | 文档 |
| --- | --- |
| 准备 Python、SSH、inventory、Vault 和参数 | [公共准备](COMMON.md) |
| 仅优化内核 | [内核专项](KERNEL.md) |
| 仅部署 MySQL、Router、HAProxy、Keepalived | [组件操作](COMPONENTS.md) |
| 扩容 / 缩容 MySQL、Router、LB | [扩缩容](SCALING.md) |
| 调整硬件档位并滚动应用 | [配置变更](CONFIGURATION.md) |
| 启用逻辑 / 物理备份及选择存储目标 | [备份方案](BACKUPS.md) |
| 应用端口、事务、证书与连接池 | [应用接入](../runbooks/APPLICATION_CONNECTIONS.md) |
| 故障诊断和恢复 | [故障排查](../runbooks/TROUBLESHOOTING.md) · [隔离恢复](../runbooks/BACKUP_AND_RESTORE_GUIDE.md) |

每篇方案按“适用条件 → 配置 → 执行 → 验证 → 排障与回退”组织。示例里的文档地址和
占位参数必须替换为自己的环境值；不要直接连接模板地址，也不要降低 HA 门槛来通过检查。
