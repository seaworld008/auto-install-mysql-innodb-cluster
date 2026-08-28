# MySQL InnoDB Cluster 安装、配置与扩缩容交叉验证

> 更新时间：2026-08-28
> 证据边界：本文记录当前仓库的静态实现对照，不代表真实环境部署、故障切换、
> 备份恢复或性能验收已经完成。

## 1. 验证范围

- 安装与初始化：`playbooks/install-mysql.yml`
- 集群配置与扩缩容：`playbooks/configure-cluster.yml`、
  `playbooks/scale-mysql.yml`、`playbooks/shrink-mysql.yml`
- Router 与入口层：`playbooks/install-router.yml`、
  `playbooks/install-haproxy.yml`、`playbooks/install-keepalived.yml`
- 配置真相源：`inventory/group_vars/all.yml`
- 运行态健康门：`playbooks/validate-ha.yml`、
  `playbooks/health-check-ha.yml`
- 操作入口：`scripts/deploy_dedicated_routers.sh`

## 2. 当前静态结论

### 与当前支持线一致

1. MySQL 发行线由 `mysql_release_line` 统一选择 `8.0` 或 `8.4`，并校验
   repository series 与 major version 一致。
2. 模板启用 GTID、ROW binlog、`log_replica_updates`、单主 Group Replication
   及现代 `replica_*` 参数。
3. standalone 实例先运行 `dba.checkInstanceConfiguration()`；已有成员跳过
   `configureInstance()`，避免重复配置破坏幂等性。
4. 集群不存在时才执行 `dba.createCluster()`；secondary 仅在尚未成为成员时执行
   `addInstance()`，恢复方式由 `mysql_cluster_recovery_method` 显式配置。
5. 最终门要求 Cluster 为 `OK`、全部 inventory 成员为 `ONLINE`，且 topology
   成员数与 inventory 一致。
6. Router 只在首次部署或显式 `mysql_router_rebootstrap: true` 时 bootstrap；
   每台 Router 使用独立生成的 Router 账号。
7. HAProxy 只连接 Router 后端；Keepalived 通过 HAProxy systemd 状态决定是否
   进入 `FAULT` 并释放 VIP。

### 安全与供应链状态

- MySQL repository key 和 Percona release 包均使用固定 SHA-256 校验。
- MySQL Shell、Router bootstrap 和 XtraBackup 不把数据库密码写入命令行参数；
  密码通过 stdin 或临时 `0600` option file 传入，并配合 `no_log`。
- SSH host-key 校验默认严格；rsync 备份要求预置可信 `known_hosts`，并校验文件
  所有权与私钥权限。
- tracked inventory 只保留脱敏示例；真实 inventory、Vault 文件与备份输出必须
  留在 Git 忽略范围。

## 3. 关键配置核验

| 检查项 | 当前实现 | 静态结论 |
| --- | --- | --- |
| GTID 与一致性 | `gtid_mode=ON`、`enforce_gtid_consistency=ON` | 通过 |
| Binlog | `binlog_format=ROW`、`log_replica_updates=ON` | 通过 |
| Group Replication | 单主、唯一 UUID、显式 allowlist 与 seeds | 通过 |
| 过时参数 guard | CI 阻断已移除的 MySQL 参数 | 通过 |
| Cluster 幂等 | 识别成员后再决定 create/add | 通过 |
| Router bootstrap | 已有配置默认跳过，显式开关才重建 | 通过 |
| Repository 完整性 | 固定 key/package SHA-256 | 通过 |
| 健康门 | Cluster、成员、服务、端口、唯一 VIP | 通过 |

## 4. 扩缩容边界

### MySQL

- 扩容通过 `--scale-mysql-add --limit <new-host>` 精确限制目标。
- `mysql_cluster_recovery_method` 当前默认 `clone`，目标节点必须是可重建节点；
  如环境策略不同，应在部署前显式评审并覆盖。
- 缩容要求单一目标并保留最小节点数；若目标为动态 primary，必须先通过
  `--new-primary` 显式切主。
- MySQL 摘除后先在 shrink playbook 内验证剩余 topology；操作员从 inventory
  删除旧节点后，再运行全栈 `--status`。

### Router 与 HAProxy

- Router 与 HAProxy/Keepalived 扩容复用各自安装 playbook。
- 缩容入口只允许精确匹配一个节点，并在停服前检查剩余数量不低于 HA 下限。
- 停服后必须先更新 inventory，再执行全栈健康检查，避免用旧拓扑制造误报。

## 5. 真实环境验证建议

每次 staging 变更至少保存以下证据：

```sql
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

SELECT MEMBER_ID, MEMBER_HOST, MEMBER_PORT, MEMBER_STATE, MEMBER_ROLE
FROM performance_schema.replication_group_members
ORDER BY MEMBER_HOST, MEMBER_PORT;
```

同时执行：

```bash
./scripts/deploy_dedicated_routers.sh --status \
  -i inventory/hosts.local.yml \
  --ask-vault-pass -e @inventory/vault.local.yml
```

验收时应确认：

- Cluster 为 `OK`，全部预期成员为 `ONLINE`，且仅一个 `PRIMARY`
- Router、HAProxy、Keepalived 与所有公开业务端口正常
- VIP 恰好归属一个入口节点
- 扩缩容、故障切换与回滚均保留变更记录
- 备份已在隔离环境完成实际恢复，而不只是生成归档

## 6. 最终判断

当前代码的静态安全性、幂等性和 fail-closed 门禁已经收敛；剩余发布边界是目标
环境资格验证。只有完成 staging 全链路部署、切换、扩缩容及恢复演练后，才能据此
作出生产接受结论。
