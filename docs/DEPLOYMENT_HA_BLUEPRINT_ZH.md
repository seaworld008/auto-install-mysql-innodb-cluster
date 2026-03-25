# MySQL InnoDB Cluster 高可用部署蓝图（中文）

## 1. 目标与默认高可用基线

本仓库当前默认按以下最小高可用要求执行预检查：

- MySQL InnoDB Cluster：**至少 3 节点**（1 主 + 2 从）
- MySQL Router：**至少 2 节点**（可扩到 3）
- HAProxy：**至少 2 节点**（可扩到 3）

对应预检查在 `playbooks/preflight-ha.yml` 中自动执行。

## 2. 组件职责与推荐路径

- **MySQL InnoDB Cluster**：数据一致性与主从故障切换。
- **MySQL Router**：感知集群拓扑，负责读写路由。
- **HAProxy**：对应用提供统一入口，对多个 Router 或 MySQL 后端做四层负载与故障摘除。

推荐链路（行业常见实践）：

`App -> HAProxy VIP/DNS -> MySQL Router 集群 -> InnoDB Cluster`

## 3. Router / HAProxy 部署选项（都支持）

### A. 与 MySQL 同机部署（资源紧张场景）
- 优点：机器少、成本低。
- 风险：资源争抢，故障域耦合。
- 建议：仅用于测试或小规模生产。

### B. Router 独立部署（推荐）
- 优点：路由层与数据库层故障隔离。
- 建议：2 节点起步，重要业务可 3 节点。

### C. HAProxy 独立部署（推荐）
- 优点：统一入口、连接治理能力更强。
- 建议：2 节点起步（通常配合 Keepalived VIP 或 DNS 健康切换）。

### D. Router + HAProxy 均独立多节点（最佳实践）
- 优点：分层解耦、可维护性最强。
- 适合：中大型生产环境。

## 4. 自动化能力（本仓库）

- 全流程入口：`playbooks/site.yml`
- 自动预检查：`playbooks/preflight-ha.yml`
- MySQL 安装：`playbooks/install-mysql.yml`
- 集群配置：`playbooks/configure-cluster.yml`
- Router 安装：`playbooks/install-router.yml`
- HAProxy 自动化：`playbooks/install-haproxy.yml`

## 5. 可扩展性说明

- 你可以随时在 inventory 中新增 `mysql_router` 或 `haproxy_lb` 节点。
- 重新执行 `playbooks/site.yml` 后，配置会自动渲染并下发。
- HAProxy 后端可通过 `haproxy_backend_target` 切换：
  - `router`（默认，推荐）
  - `mysql`（无 Router 场景下可用）

## 6. 一次部署建议流程

1) 准备 inventory（推荐基于 `inventory/hosts-ha-reference.yml`）

2) 先做语法与拓扑预检查：

```bash
ansible-playbook -i inventory/hosts-ha-reference.yml playbooks/preflight-ha.yml
```

3) 执行全量部署：

```bash
ansible-playbook -i inventory/hosts-ha-reference.yml playbooks/site.yml
```

4) 交叉验证：
- MySQL 侧：`docs/MYSQL80_CLUSTER_CROSS_VALIDATION.md`
- 入口侧：
  - Router 端口（6446/6447/6450）
  - HAProxy 端口（3307/3308/3309）
  - HAProxy stats（8404）

## 7. 最小 HA 说清楚（强约束）

- 只部署 1 个 Router 或 1 个 HAProxy，不满足入口层 HA。
- 本仓库默认 `router_ha_required: true`、`haproxy_ha_required: true`，会在预检查阶段阻断。
- 如测试环境临时单节点，可显式覆盖变量关闭阻断（不建议生产）：

```bash
ansible-playbook -i inventory/hosts.yml playbooks/preflight-ha.yml \
  -e router_ha_required=false -e haproxy_ha_required=false
```

