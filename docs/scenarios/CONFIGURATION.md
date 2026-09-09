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
