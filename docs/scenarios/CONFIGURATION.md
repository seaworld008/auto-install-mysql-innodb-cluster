# 配置调整与滚动应用

## 适用条件

适用于已部署拓扑的参数收敛，不是 MySQL 版本升级或数据库恢复。
完成 [公共准备](COMMON.md)，复用当前环境的参数文件、inventory 和 Vault。

## 修改参数

本地 `inventory/settings.local.yml` 只写需要覆盖的值，其余来自唯一配置源。
例如修改连接空闲超时与 Router 连接上限，合并以下字段到现有文件，不覆盖整个文件：

```yaml
mysql_wait_timeout: 900
mysql_interactive_timeout: 900
mysql_router_max_total_connections: 1000
mysql_router_max_idle_server_connections: 0
mysql_router_route_max_connections: 500
```

这些数字只是演示值，应根据业务连接池、资源和容量评估选择。

硬件档位有两种选择方式：

```bash
./scripts/config_manager.sh --list
./scripts/config_manager.sh --current
./scripts/config_manager.sh --validate
```

单个环境可直接修改 settings 中的 `mysql_hardware_profile`。若要调整仓库工作副本的公共默认档位：

```bash
./scripts/config_manager.sh --switch optimized_8c32g
```

settings 中存在同名字段时，它会优先于修改后的默认值；不要误以为修改了默认档位就改变了
所有环境。配置管理器只修改选择项并保存受限备份，不会立即修改远端。

## 执行与验证

```bash
"$DEPLOY" --check-prereq "${COMMON_ARGS[@]}"
"$DEPLOY" --apply-config --skip-kernel-optimization "${COMMON_ARGS[@]}"
"$DEPLOY" --status "${COMMON_ARGS[@]}"
```

操作复用安装 playbook，可能检查软件包、账号并重启服务；安排维护窗口。
如果只部署了部分组件，使用 [组件对应入口](COMPONENTS.md) 收敛该层，不用完整 apply-config。

通过受保护的交互连接查询实际参数，不把密码写在命令行：

```sql
SHOW GLOBAL VARIABLES WHERE Variable_name IN ('wait_timeout', 'interactive_timeout', 'max_connections');
```

Router 的配置观察命令：

```bash
ansible mysql_router "${COMMON_ARGS[@]}" -b -m command \
  -a 'grep max_total_connections /var/lib/mysqlrouter/mysqlrouter.conf'
```

配置文件存在不代表全部连接行为已验证；还应在实际应用连接池中确认超时、连接数和重连行为。

## 排障与回退

- 值没有改变：检查 settings 是否覆盖默认值，确认命令加载了同一份参数文件。
- 节点失败：停止后续变更，检查该节点日志；不要一次重启整个复制组。
- 回退参数：恢复变更前的本地 settings，再通过相同入口逐台应用并检查状态。
- `config_manager.sh --restore <备份文件名>` 只恢复备份里的档位，不覆盖当前其他配置。
- 不修改运行集群的 UUID 来解决配置冲突，应把本地配置对齐到确认过的实际组身份。

## MySQL 文件句柄容量

`mysql_open_files_limit` 来自所选硬件档位，也可在 settings 中明确覆盖。部署会写入
`/etc/systemd/system/mysqld.service.d/50-innodb-cluster-limits.conf`（Debian / Ubuntu 为
`mysql.service.d`），与其他 MySQL 配置一起逐节点重启，并读取进程的实际 soft / hard
限制确认容量。无需修改发行包自带的 service 文件。

目标必须不大于 `fs.nr_open` / `fs.file-max`；保留其他管理员 drop-in，但若其解析结果
与目标或内核上限冲突，会在重启前中止。不要只修改 my.cnf 的 `open_files_limit`，因为
systemd 管理的服务还受 `LimitNOFILE` 约束。

## Router 文件句柄容量

`mysql_router_nofile_limit` 默认按 `3 × mysql_router_max_total_connections +
mysql_router_max_idle_server_connections + 1024` 计算，覆盖客户端、自动分流会话的读写后端、
空闲池与管理开销。它写入 Router 的 systemd unit，避免连接数配置先碰到操作系统默认的
1024 soft limit。该预算是资源上限配置，不是连接容量压测结论。

目标超出主机内核上限时会中止；调整连接上限后，经 `--install-routers` 或 `--apply-config`
逐台应用。已有 unit 正确但进程仍使用旧限制时，重跑也会恢复；正常重跑不重启健康 Router。

`mysql_table_definition_cache` 默认按表缓存容量的一半计算，但至少为 MySQL 接受的 400。
因此低资源档位不会生成随后被服务端自动改写的 128，便于对照配置与运行值。

## 数据库通告地址与 DNS

MySQL Shell 和 Router 会读取集群元数据中的成员地址。SSH 能连接 `ansible_host`，
不代表其他节点能解析数据库的系统主机名。新集群若使用固定 IPv4 地址，可在
本地 settings 或 inventory 的 `all.vars` 中设置：

```yaml
mysql_report_host_override: "{{ ansible_host }}"
```

`mysql_report_host_override` 是本地输入，最终解析为运行变量 `mysql_report_host`；
使用单独的覆盖名称，避免 inventory 的 all.vars 被默认 group_vars 覆盖。
每台数据库使用自身 inventory 地址通告成员，不需要为其系统主机名额外配置 DNS。
也可按主机配置稳定的 DNS 名称；该名称必须从所有 MySQL 和 Router 节点解析并连通。
通告地址不包含端口，端口仍由 `mysql_port` 管理。
采用严格 TLS 校验时，证书 SAN 必须覆盖所用地址。

默认留空：新实例沿用 MySQL 的系统主机名；已有集群成员保留实际 `report_host`，
不会因为移除本地覆盖项而改回系统主机名。首次 bootstrap 前应选定稳定的通告地址。
对已注册成员设置不同地址时，普通安装或配置更新会在写入新 my.cnf 前拒绝；
地址变更须另行规划成员维护与元数据更新，不能当作普通滚动参数修改。

若各主机使用不同的通告名称，先移除 settings 文件中的全局覆盖项，再在对应 MySQL 主机
的 inventory 变量下设置 `mysql_report_host_override`，避免 `-e` 的全局值覆盖逐机设置。
此参数控制成员通告，不替代网络连通要求：inventory 地址及通告地址都必须按部署流程
在相关数据库和 Router 节点之间可达。

已有成员的前置地址检查使用安装流程中的 root 本地连接；集群管理员账号在后续步骤创建或更新，
因此地址检查不依赖尚待收敛的管理员账号及其目标密码。
