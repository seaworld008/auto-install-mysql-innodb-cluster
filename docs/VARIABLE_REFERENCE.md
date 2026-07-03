# 变量参考与配置示例

本文档解释 `inventory/group_vars/all.yml` 中最重要的运行时变量。它是人读参考，不是新的配置真相源；真实运行配置仍只以 `inventory/group_vars/all.yml` 为准。

## 1. 版本与安装源

| 变量 | 默认值 | 建议 | 说明 |
| --- | --- | --- | --- |
| `mysql_release_line` | `8.4` | 部署前确认 | 支持 `8.0` / `8.4`，默认 MySQL 8.4 LTS |
| `mysql_supported_release_lines` | `8.0`, `8.4` | 不建议随意扩展 | 预检查和仓库支持矩阵依据 |
| `mysql_repo_gpg_keys` | MySQL 2023/2025 GPG key | 保持官方源 | 安装官方 MySQL 包时使用 |
| `mysql_repo_series_map` | `8.0`, `8.4-lts` | 跟随官方仓库 | 由版本线映射到官方 repo series |

示例：

```yaml
mysql_release_line: "8.4"
```

## 2. 凭据与集群身份

| 变量 | 默认值 | 是否必改 | 说明 |
| --- | --- | --- | --- |
| `mysql_root_password` | `CHANGE_ME_ROOT_PASSWORD` | 是 | MySQL root 初始密码 |
| `mysql_cluster_user` | `clusteradmin` | 视情况 | InnoDB Cluster 管理用户 |
| `mysql_cluster_password` | `CHANGE_ME_CLUSTER_PASSWORD` | 是 | Cluster 管理用户密码 |
| `mysql_replication_user` | `replicator` | 视情况 | 复制用户 |
| `mysql_replication_password` | `CHANGE_ME_REPLICATION_PASSWORD` | 是 | 复制用户密码 |
| `keepalived_auth_pass` | `MySQLHApass` | 生产建议修改 | Keepalived VRRP 认证口令 |

生产建议：

- 使用 Ansible Vault 或外部 Secret Manager。
- 不要把真实密码提交到 Git。
- Issue、PR 和截图中必须脱敏。

## 3. MySQL 集群与端口

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `mysql_cluster_name` | `prodCluster` | InnoDB Cluster 名称 |
| `mysql_group_replication_group_name` | `aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa` | Group Replication UUID，生产建议替换 |
| `mysql_cluster_recovery_method` | `clone` | 新节点加入时的恢复方式 |
| `mysql_group_replication_ip_allowlist` | 私网网段 | Group Replication 允许访问范围 |
| `mysql_port` | `3306` | MySQL 服务端口 |
| `mysql_admin_port` | `33062` | MySQL admin port |
| `mysql_group_replication_port` | `33061` | Group Replication 端口 |
| `mysql_datadir` | `/data/mysql` | 数据目录 |
| `mysql_logdir` | `/var/log/mysql` | 日志目录 |
| `mysql_tmpdir` | `/tmp` | 临时目录 |

## 4. 硬件配置 Profile

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `mysql_hardware_profile` | `optimized_8c32g` | 当前启用的 MySQL profile |
| `mysql_config_profiles.optimized_8c32g` | 8C32G 生产余量配置 | 默认基线 |
| `mysql_config_profiles.original_10k` | 历史高连接配置 | 仅供高内存压力容忍场景评估 |

当前默认 profile 重点参数：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `innodb_buffer_pool_size` | `18G` | 给 OS、连接和峰值预留空间 |
| `innodb_redo_log_capacity` | `6G` | MySQL 8.0.30+ 推荐 redo 变量 |
| `max_connections` | `2500` | 默认更偏稳健，不追求极限连接数 |
| `tmp_table_size` | `64M` | 内存临时表上限 |
| `max_heap_table_size` | `64M` | MEMORY 表上限 |
| `open_files_limit` | `65535` | 文件句柄上限 |

切换 profile 时只改：

```yaml
mysql_hardware_profile: "optimized_8c32g"
```

不要新增整份 `inventory/group_vars/all-*.yml` 作为运行配置。

## 5. 高可用基线

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `mysql_ha_min_nodes` | `3` | MySQL 最小 HA 节点数 |
| `router_ha_required` | `true` | 是否要求 Router HA |
| `router_ha_min_nodes` | `2` | Router 最小 HA 节点数 |
| `haproxy_ha_required` | `true` | 是否要求 HAProxy HA |
| `haproxy_ha_min_nodes` | `2` | HAProxy 最小 HA 节点数 |

测试环境临时单节点可显式覆盖，但不建议生产使用：

```bash
ansible-playbook -i inventory/hosts.yml playbooks/preflight-ha.yml \
  -e router_ha_required=false -e haproxy_ha_required=false
```

## 6. 部署能力开关

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `deployment_features.mysql_cluster` | `true` | 启用 MySQL Cluster 主线 |
| `deployment_features.mysql_router` | `true` | 启用 Router 层 |
| `deployment_features.haproxy` | `true` | 启用 HAProxy |
| `deployment_features.keepalived` | `true` | 启用 Keepalived VIP |
| `deployment_features.backup` | `false` | 备份默认关闭 |

这些变量表达能力边界；真实入口仍应通过 `scripts/deploy_dedicated_routers.sh` 执行。

## 7. 扩缩容与滚动配置策略

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `scale_policy.mysql_min_nodes` | `3` | 缩容后 MySQL 最小节点数 |
| `scale_policy.mysql_scale_target_group` | `mysql_secondary` | 新增 MySQL 节点默认加入的 inventory 组 |
| `scale_policy.mysql_remove_cleanup_data` | `false` | 缩容是否清理数据，默认保守 |
| `scale_policy.mysql_remove_stop_service` | `true` | 缩容时是否停止服务 |
| `scale_policy.require_primary_switchover_before_removal` | `true` | 移除主节点前要求切主 |
| `scale_policy.rolling_apply_batch_size` | `1` | 滚动配置批大小 |
| `scale_policy.rolling_apply_pause_seconds` | `10` | 滚动间隔 |

## 8. 备份配置

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `backup_config.enabled` | `false` | 默认关闭备份 |
| `backup_config.method` | `logical` | `logical` / `xtrabackup` |
| `backup_config.type` | `local` | `local` / `nfs` / `rsync` |
| `backup_config.base_dir` | `/backup/mysql` | 本地或挂载备份目录 |
| `backup_config.retention_days` | `7` | 保留天数 |
| `backup_config.create_manifest` | `true` | 是否生成 manifest |
| `backup_config.threads` | `4` | 备份线程数 |
| `backup_config.run_on_host_group` | `mysql_primary` | 执行备份的主机组 |
| `backup_config.logical_tool` | `mysqlsh-dump-instance` | 逻辑备份工具 |

逻辑备份到本地：

```yaml
backup_config:
  enabled: true
  method: "logical"
  type: "local"
  base_dir: "/backup/mysql"
  retention_days: 7
  run_on_host_group: "mysql_primary"
```

物理备份到从节点本地目录：

```yaml
backup_config:
  enabled: true
  method: "xtrabackup"
  type: "local"
  base_dir: "/backup/mysql"
  run_on_host_group: "mysql_secondary"
  xtrabackup:
    parallel: 4
    compress: false
    prepare: false
    use_memory: "1G"
```

## 9. HAProxy 与 Keepalived

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `haproxy_backend_target` | `router` | 后端目标，推荐 `router` |
| `haproxy_bind_address` | `0.0.0.0` | 监听地址 |
| `haproxy_balance_algorithm` | `leastconn` | 负载均衡算法 |
| `haproxy_mysql_rw_port` | `3307` | 强制读写入口 |
| `haproxy_mysql_ro_port` | `3308` | 强制只读入口 |
| `haproxy_mysql_rwsplit_port` | `3309` | 自动读写分离入口 |
| `haproxy_stats_port` | `8404` | stats 页面端口 |
| `keepalived_enabled` | `true` | 是否启用 VIP |
| `keepalived_interface` | 自动探测或 `eth0` | 需要与真实网卡一致 |
| `keepalived_virtual_router_id` | `51` | VRRP router id |
| `keepalived_vip` | `192.168.1.100` | 生产必须替换 |
| `keepalived_vip_cidr` | `24` | VIP 掩码 |

生产示例：

```yaml
haproxy_backend_target: "router"
keepalived_interface: "ens192"
keepalived_virtual_router_id: 51
keepalived_vip: "10.20.30.100"
keepalived_vip_cidr: 24
```

## 10. MySQL Router

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `mysql_router_port` | `6446` | 强制读写入口 |
| `mysql_router_ro_port` | `6447` | 强制只读入口 |
| `mysql_router_rwsplit_port` | `6450` | 自动读写分离入口 |
| `mysql_router_admin_port` | `8443` | Router admin 端口 |
| `mysql_router_rebootstrap` | `false` | 默认不重新 bootstrap |
| `mysql_router_max_total_connections` | `30000` | Router 总连接上限 |
| `mysql_router_route_max_connections` | `15000` | 单 route 连接上限 |
| `mysql_router_metadata_connect_timeout` | `5` | metadata 连接超时 |
| `mysql_router_metadata_read_timeout` | `30` | metadata 读取超时 |
| `mysql_router_routing_connect_timeout` | `5` | 路由连接超时 |
| `mysql_router_client_connect_timeout` | `9` | 客户端连接 Router 超时 |

注意：

- `mysql_router_rebootstrap` 默认应保持 `false`。
- 不要把 Router 连接建立超时理解成 SQL 执行超时。
- Router 参数应确认最终进入模板或 bootstrap 命令，避免“配置写了但不生效”。

## 11. 最小生产候选覆盖示例

```yaml
mysql_release_line: "8.4"
mysql_group_replication_group_name: "11111111-2222-3333-4444-555555555555"
mysql_hardware_profile: "optimized_8c32g"

mysql_root_password: "{{ vault_mysql_root_password }}"
mysql_cluster_password: "{{ vault_mysql_cluster_password }}"
mysql_replication_password: "{{ vault_mysql_replication_password }}"

keepalived_interface: "ens192"
keepalived_vip: "10.20.30.100"

backup_config:
  enabled: true
  method: "logical"
  type: "rsync"
  base_dir: "/backup/mysql"
  remote_host: "10.20.40.20"
  remote_user: "backup"
  remote_dir: "/data/mysql-backups"
  ssh_key_path: "/root/.ssh/backup_rsa"
  retention_days: 14
```

## 12. 变更后验证

修改变量后至少执行：

```bash
git diff --check
ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/site.yml --syntax-check
ansible-inventory -i inventory/hosts-with-dedicated-routers.yml --list
```

如果改动涉及备份、缩容、恢复或入口流量，必须在隔离环境或 staging 环境做演练记录。
