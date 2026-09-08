# 变量参考与配置示例

本文解释 `inventory/group_vars/all.yml` 当前实际被使用的运行时变量。它不是第二份
配置真相源；默认值或结构变化时，应先改 `all.yml` 和消费者，再同步本文。

## 1. 版本、仓库与校验

| 变量 | 当前默认值 | 说明 |
| --- | --- | --- |
| `mysql_release_line` | `"8.4"` | 支持 `8.0` / `8.4` |
| `mysql_version` | `mysql_release_line` | 兼容派生值 |
| `mysql_major_version` | `mysql_release_line` | 兼容派生值 |
| `mysql_supported_release_lines` | `["8.0", "8.4"]` | preflight 支持矩阵 |
| `mysql_repo_series_map."8.0"` | `"8.0"` | MySQL repo series |
| `mysql_repo_series_map."8.4"` | `"8.4-lts"` | MySQL repo series |
| `mysql_repo_series` | 映射后的版本线 | 安装 playbook 消费 |

`mysql_repo_gpg_keys` 是字典列表，每个元素都必须包含：

| 字段 | 说明 |
| --- | --- |
| `url` | 官方 HTTPS 下载地址 |
| `path` | 节点上的 ASCII key 文件路径 |
| `file_url` | RPM repo 使用的本地 `file://` URL |
| `sha256` | 下载内容的固定 SHA-256 |

当前配置同时固定 MySQL 2023 和 2025 key 摘要。不要把该结构改回仅 URL 列表，也
不要移除 `get_url` checksum 校验。

支持矩阵变量：

- `mysql_supported_redhat_major_versions`: `8`, `9`, `10`
- `mysql_supported_ubuntu_releases`: `jammy`, `noble`, `plucky`, `questing`
- `mysql_supported_debian_releases`: `bookworm`, `trixie`
- `mysql_architecture_map`: `x86_64`, `aarch64`, `arm64`

这些值只表达仓库当前静态支持分支，不证明每个发行版已完成真实部署验证。

控制节点运行 `ansible-core` 2.20 / 2.21，要求 Python 3.12+；
`requirements.txt` 不再安装其他 Python 包。目标节点必须在第一次 Ansible 模块连接
前预装 Python 3.9+，目标 PyMySQL 由可信系统仓库安装。

## 2. 凭据与集群身份

| 变量 | 当前默认值 | 要求 |
| --- | --- | --- |
| `mysql_root_password` | `CHANGE_ME_ROOT_PASSWORD` | 必须由 Vault / 外部 Secret 覆盖 |
| `mysql_cluster_user` | `clusteradmin` | 可按组织命名调整 |
| `mysql_cluster_password` | `CHANGE_ME_CLUSTER_PASSWORD` | 必须由 Vault / 外部 Secret 覆盖 |
| `mysql_replication_user` | `replicator` | 可按组织命名调整 |
| `mysql_replication_password` | `CHANGE_ME_REPLICATION_PASSWORD` | 必须由 Vault / 外部 Secret 覆盖 |
| `mysql_cluster_name` | `prodCluster` | InnoDB Cluster 名称 |
| `mysql_group_replication_group_name_override` | 无 | 每个独立集群必须提供唯一 UUID |
| `mysql_group_replication_group_name` | 从 override 派生；否则占位 UUID | 不直接修改派生表达式 |
| `mysql_cluster_recovery_method` | `clone` | 新成员恢复方式 |

本地 inventory 示例：

```yaml
all:
  vars:
    mysql_group_replication_group_name_override: "CHANGE_ME_UNIQUE_UUID"
```

上例只展示格式。实际部署应重新生成 UUID，不得复用示例、默认
`aaaaaaaa-...` 或另一集群的 UUID。

Secret 示例：

```bash
ansible-vault create inventory/vault.local.yml
./scripts/deploy_dedicated_routers.sh --check-prereq \
  -i inventory/hosts.local.yml \
  --ask-vault-pass -e @inventory/vault.local.yml
```

主入口也支持 `--vault-password-file`。真实 Secret、Vault 口令、IP 和私钥不得进入
tracked inventory、Issue、PR、日志或截图。

## 3. MySQL 服务与路径

| 变量 | 当前默认值 | 说明 |
| --- | --- | --- |
| `mysql_collation_server` | `utf8mb4_general_ci` | 兼容历史应用 |
| `mysql_port` | `3306` | MySQL 服务 |
| `mysql_admin_port` | `33062` | Admin port |
| `mysql_group_replication_port` | `33061` | Group Replication |
| `mysql_group_replication_ip_allowlist` | 常见私网网段 | 部署前按真实网段收敛 |
| `mysql_datadir` | `/data/mysql` | 必须是绝对路径 |
| `mysql_logdir` | `/var/log/mysql` | 日志目录 |
| `mysql_tmpdir` | `/tmp` | 临时目录 |
| `mysql_user` | `mysql` | 服务用户 |
| `mysql_group` | `mysql` | 服务组 |

自定义 datadir 安装流程只会在目标目录未初始化且为空时，从发行包已经初始化的
`/var/lib/mysql` 安全迁移。迁移前写入 0600 中断标记，重跑发现标记时继续幂等
rsync；迁移完整后写入完成标记并清理中断标记。非空未知目录会阻断。

Debian / Ubuntu 为 datadir / logdir 配置 AppArmor local profile；启用 SELinux
的 RedHat 节点通过 `semanage fcontext` 持久配置 `mysqld_db_t` /
`mysqld_log_t`，再执行 `restorecon`。启动后查询 `@@datadir` 验证最终路径。

RedHat root 初始化会先用 0600 临时 option file 探测目标密码。目标密码已生效则
跳过首次临时密码流程；探测失败时必须找到首次临时密码，否则阻断。密码和临时文件
任务保持 `no_log`。

`firewall_ports` 当前包含 MySQL、admin 和 Group Replication 三个 TCP 端口。

## 4. MySQL 硬件 Profile

只通过下列变量切换：

```yaml
mysql_hardware_profile: "optimized_8c32g"
```

`mysql_config_profiles` 当前有 `optimized_8c32g` 和 `original_10k`。每个 profile
包含同一组字段：

- `innodb_buffer_pool_size`
- `innodb_redo_log_capacity`
- `max_connections`
- `thread_cache_size`
- `table_open_cache`
- `sort_buffer_size`
- `read_buffer_size`
- `read_rnd_buffer_size`
- `bulk_insert_buffer_size`
- `tmp_table_size`
- `max_heap_table_size`
- `innodb_buffer_pool_instances`
- `innodb_io_capacity`
- `innodb_io_capacity_max`
- `innodb_read_io_threads`
- `innodb_write_io_threads`
- `innodb_thread_concurrency`
- `back_log`
- `thread_stack`
- `table_open_cache_instances`
- `open_files_limit`
- `join_buffer_size`
- `max_allowed_packet`
- `wait_timeout`
- `interactive_timeout`
- `connect_timeout`
- `net_read_timeout`
- `net_write_timeout`

`mysql_innodb_*`、`mysql_max_connections` 等顶层变量从当前 profile 派生，并由
MySQL 模板消费。不要创建新的 `group_vars/all-xxx.yml` 运行配置副本。

`memory_analysis_*` 和 `performance_expectations` 是容量分析元数据，不是自动验收门，
也不能作为性能或可用性实测结论。

## 5. HA 最小节点与缩容策略

| 变量 | 当前默认值 | 说明 |
| --- | --- | --- |
| `mysql_ha_min_nodes` | `3` | MySQL preflight 最小节点数 |
| `router_ha_required` | `true` | 是否要求 Router HA |
| `router_ha_min_nodes` | `2` | Router 最小节点数 |
| `haproxy_ha_required` | `true` | 是否要求入口层 HA |
| `haproxy_ha_min_nodes` | `2` | HAProxy 最小节点数 |

`scale_policy` 的当前字段：

| 字段 | 默认值 | 说明 |
| --- | --- | --- |
| `mysql_min_nodes` | `3` | 缩容后 MySQL 下限 |
| `mysql_scale_target_group` | `mysql_secondary` | 扩容目标组 |
| `mysql_remove_cleanup_data` | `false` | 默认保留数据 |
| `mysql_remove_stop_service` | `true` | 成功移除后停止服务 |
| `require_primary_switchover_before_removal` | `true` | 移除 primary 前切主 |
| `rolling_apply_batch_size` | `1` | 生产安全门要求每批一台 |
| `rolling_apply_pause_seconds` | `10` | 批次间暂停秒数 |

缩容 playbook 还会按运行时身份唯一识别目标 UUID 和当前 ONLINE primary，并在操作
后要求 Cluster `OK`、剩余成员全部 `ONLINE`。

## 6. 备份配置

`backup_config` 的当前字段：

| 字段 | 默认值 | 说明 |
| --- | --- | --- |
| `enabled` | `false` | opt-in 开关 |
| `method` | `logical` | `logical` / `xtrabackup` |
| `type` | `local` | `local` / `nfs` / `rsync` |
| `base_dir` | `/backup/mysql` | 本地或挂载目录 |
| `retention_days` | `7` | 保留天数 |
| `create_manifest` | `true` | 生成 manifest |
| `threads` | `4` | MySQL Shell 线程数 |
| `consistent` | `true` | 逻辑备份一致性选项 |
| `compression` | `zstd` | 逻辑备份压缩 |
| `remote_host` | 空 | rsync 目标 |
| `remote_user` | `backup` | rsync 用户 |
| `remote_dir` | 空 | rsync 远端目录 |
| `ssh_key_path` | 空 | 可选私钥 |
| `ssh_known_hosts_file` | `/root/.ssh/known_hosts` | 必须为绝对路径并预置 |
| `run_on_host_group` | `mysql_primary` | 执行备份的组 |
| `logical_tool` | `mysqlsh-dump-instance` | 逻辑工具标识 |

`backup_config.percona_release` 固定 XtraBackup 仓库安装器：

| 字段 | 当前值 |
| --- | --- |
| `deb_url` | `https://repo.percona.com/apt/percona-release_1.0-33.generic_all.deb` |
| `deb_sha256` | `313ebd0fbab685bf448ff41d7d62f5ee3b2bcd8a45b0c52ed842606a2d5deeae` |
| `rpm_url` | `https://repo.percona.com/yum/percona-release-1.0-33.noarch.rpm` |
| `rpm_sha256` | `b644b932670501cf42445382b208cada2c01888026326f9cd2668d938d6f57aa` |

`backup_config.xtrabackup` 字段：

| 字段 | 默认值 |
| --- | --- |
| `parallel` | `4` |
| `compress` | `false` |
| `compress_algorithm` | `zstd` |
| `compress_threads` | `2` |
| `prepare` | `false` |
| `target_subdir` | `xtrabackup` |
| `use_memory` | `1G` |

rsync 强制 BatchMode、`StrictHostKeyChecking=yes` 和指定的
`UserKnownHostsFile`。该文件必须是 root 所有的普通文件，并禁止 group / other
写入；`ssh_key_path` 非空时必须是 root 所有普通文件，权限只能为 `0400` 或
`0600`。不要重新加入任意 `rsync_opts` / `extra_args` 字符串注入字段。

当 `xtrabackup.compress: true` 且 `xtrabackup.prepare: true` 时，任务先执行
`xtrabackup --decompress`，再执行 `xtrabackup --prepare`。`prepare: false`
时不会自动解压或 prepare。

## 7. HAProxy

| 变量 | 当前默认值 | 说明 |
| --- | --- | --- |
| `haproxy_backend_target` | `router` | 唯一允许值 |
| `haproxy_bind_address` | `0.0.0.0` | MySQL 入口监听 |
| `haproxy_balance_algorithm` | `leastconn` | Router 后端均衡 |
| `haproxy_health_check_interval_ms` | `2000` | 后端检查间隔 |
| `haproxy_mysql_rw_port` | `3307` | 强制读写 |
| `haproxy_mysql_ro_port` | `3308` | 强制只读 |
| `haproxy_mysql_rwsplit_port` | `3309` | 自动读写分离 |
| `haproxy_stats_bind_address` | `127.0.0.1` | stats 仅本机 |
| `haproxy_stats_port` | `8404` | stats 端口 |
| `haproxy_stats_uri` | `/stats` | stats 路径 |
| `haproxy_global_maxconn` | `100000` | 全局连接上限 |
| `haproxy_timeout_connect` | `10s` | 后端连接超时 |
| `haproxy_timeout_client` | `1m` | 客户端超时 |
| `haproxy_timeout_server` | `1m` | 服务端超时 |
| `haproxy_retries` | `3` | 连接重试 |

`haproxy_backend_target` 不再支持 `mysql`。stats 如需远程访问，应使用 SSH tunnel
或受控监控代理，而不是改为公网监听。

## 8. Keepalived

| 变量 | 当前默认值 | 说明 |
| --- | --- | --- |
| `keepalived_interface` | 自动探测或 `eth0` | 必须存在于入口节点 |
| `keepalived_virtual_router_id` | `51` | 同一 VRRP 组一致 |
| `keepalived_auth_pass` | `CHANGE_ME` | 必须覆盖，最长 8 字符 |
| `keepalived_vip` | `192.0.2.100` | RFC 5737 占位值；preflight 必定阻断 |
| `keepalived_vip_cidr` | `24` | VIP CIDR |
| `keepalived_check_interval` | `2` | 检查间隔秒数 |
| `keepalived_check_timeout` | `2` | 检查超时秒数 |
| `keepalived_check_fall` | `2` | 连续失败阈值 |
| `keepalived_check_rise` | `2` | 连续恢复阈值 |

健康脚本检查 HAProxy systemd 服务，使用 `weight 0`。达到 fall 阈值时 VRRP 实例
进入 `FAULT` 并释放 VIP；不是仅降低 priority。

必须覆盖为目标环境已确认、未冲突的合法 IPv4；真实私网中的
`192.168.1.100` 可用。无效、回环、组播和 RFC 5737 文档地址会被 preflight
阻断。运行时健康门要求该 VIP 恰好出现在一个入口节点。

`keepalived_auth_pass` 会进入 `/etc/keepalived/keepalived.conf`，因此目标文件
保持 root 所有和 `0600`，模板渲染任务保持 `no_log`。

## 9. MySQL Router

| 变量 | 当前默认值 | 说明 |
| --- | --- | --- |
| `mysql_router_port` | `6446` | 强制读写 |
| `mysql_router_ro_port` | `6447` | 强制只读 |
| `mysql_router_rwsplit_port` | `6450` | 自动读写分离 |
| `mysql_router_admin_port` | `8443` | admin 端口 |
| `mysql_router_rebootstrap` | `false` | 默认跳过已有 bootstrap |

`mysql_router_4c8g_optimized` 当前字段：

- `max_total_connections`
- `route_max_connections`
- `metadata_connect_timeout`
- `metadata_read_timeout`
- `routing_connect_timeout`
- `client_connect_timeout`
- `max_connect_errors`
- `routing_strategy_rw`
- `routing_strategy_ro`
- `routing_strategy_rwsplit`

模板 / bootstrap 实际消费的派生变量是
`mysql_router_metadata_connect_timeout`、`mysql_router_metadata_read_timeout`、
`mysql_router_routing_connect_timeout`、`mysql_router_client_connect_timeout`、
`mysql_router_max_connect_errors`、`mysql_router_max_total_connections` 和
`mysql_router_route_max_connections`。

已有 bootstrap 配置且 `mysql_router_rebootstrap: false` 时不会重复 bootstrap。
受管端口、连接数、超时和策略会直接原子更新现有配置，保留 Router 身份和 keyring；
有实际变化才滚动重启。自动读写分离统一使用 `routing:bootstrap_rw_split`，
自动移除历史重复的 `routing:read_write_split`。没有消费者的线程、内存、连接池和
metadata 缓存字段已移除，不能把这些旧字段当成实际生效的调优。
只有明确恢复或重建时才临时设为 `true`，完成后恢复默认。

## 10. 最小覆盖示例

非敏感本地 inventory：

```yaml
all:
  vars:
    mysql_group_replication_group_name_override: "GENERATE-A-NEW-UUID"
    keepalived_interface: "ens192"
    keepalived_vip: "10.20.30.100"
```

加密 Vault：

```yaml
mysql_root_password: "CHANGE_ME_ROOT_PASSWORD"
mysql_cluster_password: "CHANGE_ME_CLUSTER_PASSWORD"
mysql_replication_password: "CHANGE_ME_REPLICATION_PASSWORD"
keepalived_auth_pass: "CHANGE_ME"
```

rsync 逻辑备份：

```yaml
backup_config:
  enabled: true
  method: "logical"
  type: "rsync"
  base_dir: "/backup/mysql"
  retention_days: 14
  create_manifest: true
  threads: 4
  consistent: true
  compression: "zstd"
  remote_host: "backup.internal.example"
  remote_user: "backup"
  remote_dir: "/data/mysql-backups"
  ssh_key_path: "/root/.ssh/backup"
  ssh_known_hosts_file: "/root/.ssh/known_hosts"
  run_on_host_group: "mysql_primary"
  logical_tool: "mysqlsh-dump-instance"
```

完整覆盖 `backup_config` 时，必须保留 `percona_release` 和 `xtrabackup` 嵌套结构；
更稳妥的方式是在 `inventory/group_vars/all.yml` 中修改需要变更的叶子值，避免
Ansible 高优先级变量替换整个字典。

## 11. 已删除的无效变量

以下变量不是当前运行时接口，不应在文档或新 inventory 中重新加入：

- `deployment_features.*`
- `keepalived_enabled`
- `backup_config.rsync_opts`
- `backup_config.extra_args`

## 12. 变更后验证

```bash
git diff --check
./.venv/bin/python -m unittest discover tests
npx --yes markdownlint-cli2@0.23.2
./.venv/bin/yamllint .
./.venv/bin/ansible-playbook \
  -i inventory/hosts-with-dedicated-routers.yml \
  playbooks/site.yml --syntax-check
./.venv/bin/ansible-inventory \
  -i inventory/hosts-with-dedicated-routers.yml --list >/dev/null
```

涉及 datadir、备份、入口流量、集群成员或缩容的变更，还必须在隔离 staging 演练。

## v0.4.0 模拟与签名配置

`mysql_config_profiles.simulation_minimal` 是唯一配置源中的低资源功能模拟档位，
通过 `mysql_hardware_profile: simulation_minimal` 选择；不得用作生产容量承诺。
`max_user_connections` 从总连接数预留 10%（最多 100），结果至少为 1。

`backup_config.percona_release.rpm_key_url`、`rpm_key_sha256`、`rpm_key_fingerprint`
分别限定 Percona Release 签名公钥来源、下载内容与导入指纹。自定义 backup_config
覆盖字典需要保留这些字段；不允许通过禁用 GPG 校验解决安装失败。
