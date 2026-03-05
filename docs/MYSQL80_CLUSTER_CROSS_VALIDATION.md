# MySQL 8.0+ InnoDB Cluster 交叉验证清单

> 目标：确保部署配置与 MySQL 8.0 官方参数命名一致，并能在 8.0.30+ 稳定运行。

## 1) 配置兼容性核查（静态）

重点确认已替换/移除的参数：

- 使用 `innodb_redo_log_capacity`，不再使用 `innodb_log_file_size`。
- 使用 `log_replica_updates` / `replica_parallel_workers` 等新命名，避免旧 `slave_*` 命名。
- 使用 `binlog_expire_logs_seconds`，避免旧 `expire_logs_days`。
- 不再配置 MySQL 8.0 已移除的 Query Cache 相关参数。
- `sql_mode` 不包含 `NO_AUTO_CREATE_USER`（MySQL 8.0 已移除）。

## 2) 部署后运行时核查（SQL）

在每个 MySQL 节点执行：

```sql
SHOW VARIABLES WHERE Variable_name IN (
  'version',
  'innodb_redo_log_capacity',
  'log_replica_updates',
  'replica_parallel_workers',
  'binlog_expire_logs_seconds',
  'group_replication_ip_allowlist',
  'sql_mode'
);
```

校验点：

- `version` 为 `8.0.x`（建议 `>= 8.0.30`）。
- `innodb_redo_log_capacity` 与 inventory 对应硬件配置一致。
- `log_replica_updates=ON`。
- `replica_parallel_workers > 0`。
- `binlog_expire_logs_seconds=604800`（7 天）。
- `group_replication_ip_allowlist` 覆盖实际网段。
- `sql_mode` 不含 `NO_AUTO_CREATE_USER`。

## 3) Group Replication 健康检查

```sql
SELECT MEMBER_ID, MEMBER_HOST, MEMBER_PORT, MEMBER_STATE, MEMBER_ROLE
FROM performance_schema.replication_group_members
ORDER BY MEMBER_HOST, MEMBER_PORT;
```

预期：

- 所有节点 `MEMBER_STATE=ONLINE`。
- 单主模式下仅 1 个 `PRIMARY`，其余为 `SECONDARY`。

## 4) 复制延迟与并行回放验证

```sql
SHOW REPLICA STATUS\G
```

重点观察：

- `Replica_IO_Running: Yes`
- `Replica_SQL_Running: Yes`
- `Seconds_Behind_Source` 持续较低（业务相关）

## 5) 与本仓库配置的对应关系

- 服务器模板：`roles/mysql-server/templates/my.cnf.j2`
- 默认变量：`inventory/group_vars/all.yml`
- 优化变量：`inventory/group_vars/all-8c32g-optimized.yml`
- 历史高并发配置：`inventory/group_vars/all-original-10k-config.yml`

