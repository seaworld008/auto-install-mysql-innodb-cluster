# MySQL InnoDB Cluster 安装/配置/扩容交叉验证（官方实践对照）

> 更新时间：2026-03-12  
> 说明：本次为**仓库静态交叉验证**（安装编排、配置模板、扩容流程、运行态检查项），对照 MySQL 8.0/8.4 官方 AdminAPI、Group Replication、MySQL Router 的通用最佳实践，以及 Percona 等社区生产实践。

## 1. 验证范围

- 安装与初始化：`playbooks/install-mysql.yml`、`playbooks/configure-cluster.yml`
- 关键配置：`roles/mysql-server/templates/my.cnf.j2`、`inventory/group_vars/all.yml`
- Router/入口层：`playbooks/install-router.yml`、`playbooks/scale-router.yml`、`playbooks/install-haproxy.yml`
- 扩容动作：`configure-cluster.yml`（加节点）、`scale-router.yml`、`scale-haproxy.yml`
- 观测与验收：`scripts/cluster-status.sh`、`validate_deployment.sh`

---

## 2. 交叉验证结论（摘要）

### ✅ 与官方/主流实践一致的部分

1. **复制与 GR 核心前置项完整**  
   已启用 `gtid_mode=ON`、`enforce_gtid_consistency=ON`、`log_replica_updates=ON`、`binlog_format=ROW`，满足 InnoDB Cluster 关键前置要求。

2. **8.0 参数命名已现代化**  
   已采用 `replica_*`、`log_replica_updates`、`binlog_expire_logs_seconds`、`innodb_redo_log_capacity`，避开大量旧参数命名。

3. **集群编排逻辑清晰**  
   先 `dba.configureInstance()`，再 `dba.createCluster()`，随后 `cluster.addInstance()`，流程与官方 AdminAPI 建议顺序一致。

4. **扩容入口已标准化**  
   Router 与 HAProxy 分别有独立扩容 playbook（`scale-router.yml`、`scale-haproxy.yml`），适合分层横向扩展。

### ⚠️ 建议尽快改进的部分

1. **Router 仓库安装关闭了 GPG 校验**  
   `install-router.yml` 中 `disable_gpg_check: yes` 不符合生产供应链安全基线，建议改为严格校验。

2. **Router bootstrap 使用集群管理员明文口令**  
   当前命令行直接拼接账号密码，建议切换为 Ansible Vault + 临时登录路径（login-path）或环境变量注入，减少泄露面。

3. **`cluster.addInstance()` 固定 `recoveryMethod: 'clone'`**  
   对大数据量恢复效率高，但会覆盖目标实例数据；建议在文档中明确适用边界，或支持 `auto` 可配置切换。

4. **状态检查脚本主机列表硬编码**  
   `scripts/cluster-status.sh` 中节点 IP 固定为 `192.168.1.10~12`，不利于多环境复用，建议读取 inventory 或传参列表。

---

## 3. 配置项逐条核验（安装与配置）

| 检查项 | 当前状态 | 结论 |
|---|---|---|
| GTID（`gtid_mode` + `enforce_gtid_consistency`） | 已开启 | ✅ |
| Binlog 行格式（`binlog_format=ROW`） | 已开启 | ✅ |
| 写入转发（`log_replica_updates=ON`） | 已开启 | ✅ |
| Group Replication 插件（`plugin_load_add='group_replication.so'`） | 已配置 | ✅ |
| 单主模式（`group_replication_single_primary_mode=ON`） | 已配置 | ✅ |
| 复制并行回放（`replica_parallel_workers`） | 已配置为 `read_io_threads/2` | ✅ |
| 过期日志保留（`binlog_expire_logs_seconds=604800`） | 7 天 | ✅ |
| 已移除参数规避（如 Query Cache、`NO_AUTO_CREATE_USER`） | 未发现旧参数 | ✅ |
| Router YUM 安装 GPG 校验 | 被禁用 | ⚠️ |

---

## 4. 扩容流程核验（MySQL/Router/HAProxy）

### 4.1 MySQL 节点扩容

- 当前通过 `cluster.addInstance(..., {recoveryMethod: 'clone'})` 执行加入。  
- 优点：新节点追平速度快、步骤简化。  
- 风险：目标实例会被 clone 覆盖，必须保证是“可重建节点”。

**建议**：在 `group_vars` 增加 `mysql_cluster_recovery_method`（`clone|auto|incremental`），按环境显式选择。

### 4.2 Router 横向扩容

- `scale-router.yml` 实际复用 `install-router.yml`，一致性好。  
- `mysqlrouter --bootstrap ... --account-create always --force` 可快速重建节点。

**建议**：为 bootstrap 增加“幂等保护 + 凭据保护”策略（Vault/Secrets 管理 + 仅必要权限账号）。

### 4.3 HAProxy/Keepalived 扩容

- `scale-haproxy.yml` 复用安装 playbook，符合“不可变基础设施”思路。  
- 与 Router 分层部署思路一致，满足高可用入口扩展。

---

## 5. 推荐运行态交叉验证 SQL（上线后每次变更执行）

```sql
-- 版本与关键参数
SHOW VARIABLES WHERE Variable_name IN (
  'version',
  'gtid_mode',
  'enforce_gtid_consistency',
  'binlog_format',
  'log_replica_updates',
  'innodb_redo_log_capacity',
  'replica_parallel_workers',
  'group_replication_single_primary_mode',
  'group_replication_ip_allowlist'
);

-- 集群成员与角色
SELECT MEMBER_ID, MEMBER_HOST, MEMBER_PORT, MEMBER_STATE, MEMBER_ROLE
FROM performance_schema.replication_group_members
ORDER BY MEMBER_HOST, MEMBER_PORT;

-- 复制线程与延迟（在只读副本或诊断场景）
SHOW REPLICA STATUS\G
```

验收标准：
- 所有成员 `MEMBER_STATE=ONLINE`
- 单主模式下仅 1 个 `PRIMARY`
- `Replica_IO_Running/Replica_SQL_Running=Yes`
- 参数值与 inventory 期望一致

---

## 6. 建议整改优先级

### P0（安全与合规）
1. Router 安装恢复 GPG 校验。  
2. 删除命令行明文口令，改为 Vault 或受控密文注入。

### P1（可运维性）
1. `cluster-status.sh` 改为 inventory 驱动。  
2. `recoveryMethod` 参数化，减少误用 clone 的风险。

### P2（持续改进）
1. 增加 “扩容后自动健康检查” 任务（SQL + Router 连通性）。  
2. 将交叉验证 SQL 固化到 `validate_deployment.sh` 的 post-check 阶段。

---

## 7. 最终判断

- 当前仓库在 **MySQL InnoDB Cluster 主干能力（安装、建群、基础扩容）上可用且结构清晰**。  
- 与官方/主流生产实践相比，主要差距集中在 **供应链安全（GPG）与凭据管理（明文口令）**。  
- 若先完成 P0 项整改，再执行一次全链路演练（建群→扩容→故障切换→回滚），即可达到更稳健的生产落地标准。
