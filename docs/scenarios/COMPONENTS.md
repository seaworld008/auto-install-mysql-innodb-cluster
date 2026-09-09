# 组件单独部署与分层检查

## 范围与依赖

“单独部署”指仅安装或收敛所选组件，依赖层保持原样，但会被读取和检查。
本项目的 HAProxy 后端固定指向 MySQL Router，Keepalived 检查同机 HAProxy；
它们不是面向任意应用的通用负载均衡/VRRP 安装器。

完成 [公共准备](COMMON.md)，选择适合的拓扑并定义 `DEPLOY`、`COMMON_ARGS`。
inventory 可以先包含最终计划的全部节点，分层操作只连接当前范围内的主机。
所有 MySQL/Router/入口分组仍须满足对应最小数量，不要求必须是 2 个 Router 或 2 个 LB。

| 操作 | 会修改 | 必须先具备 | 成功后检查 |
| --- | --- | --- | --- |
| `--mysql-only` | MySQL / Cluster；默认含其内核优化 | 数据库主机 | MySQL |
| `--install-routers` | Router；默认含其内核优化 | 已有 MySQL Cluster | MySQL + Router |
| `--install-haproxy` | 仅 HAProxy | 健康的 MySQL + Router | MySQL + Router + HAProxy，不要求 VIP |
| `--install-keepalived` | 仅 Keepalived | 同机 HAProxy 和上游均健康 | 完整拓扑及 VIP |
| `--configure-lb` | HAProxy + Keepalived；默认含入口内核优化 | 已有 MySQL + Router | 完整拓扑 |
| `--full-deploy` | Router + HAProxy + Keepalived | 已有 MySQL Cluster | 完整拓扑 |

两个新的单组件入口不会隐式优化内核，也不会调用另一组件的安装 playbook。
目前它们对整个 `haproxy_lb` 组逐台收敛，不接受 `--limit`，避免跳过 HA 验证。

## 1. 只部署数据库

```bash
"$DEPLOY" --check-prereq --scope mysql "${COMMON_ARGS[@]}"
"$DEPLOY" --mysql-only --skip-kernel-optimization "${COMMON_ARGS[@]}"
"$DEPLOY" --status --scope mysql "${COMMON_ARGS[@]}"
```

此范围不要求 Router、HAProxy 或 VIP 已配置完成。移除 `--skip-kernel-optimization`
会按现有流程先处理数据库主机的内核参数。业务暂时直接连接数据库，应用需自行处理连接节点选择。

## 2. 在已有集群上部署 Router

```bash
"$DEPLOY" --check-prereq --scope router "${COMMON_ARGS[@]}"
"$DEPLOY" --install-routers --skip-kernel-optimization "${COMMON_ARGS[@]}"
"$DEPLOY" --status --scope router "${COMMON_ARGS[@]}"
```

Router 可以在专用主机、数据库主机或应用所在主机上；后两者必须使用同一个 inventory
主机身份加入对应组，并核对端口和资源。仓库默认仍要求至少两台 Router。
单台客户端内嵌 Router 不在这套 HA 操作保证范围内。

## 3. 只部署 HAProxy，暂不启用 VIP

```bash
"$DEPLOY" --check-prereq --scope haproxy "${COMMON_ARGS[@]}"
"$DEPLOY" --install-haproxy "${COMMON_ARGS[@]}"
"$DEPLOY" --status --scope haproxy "${COMMON_ARGS[@]}"
```

先验证数据库和 Router 依赖，再安装 HAProxy，最后检查全部 HAProxy 端口。
此操作不安装、重启或停止 Keepalived，也不要求提供可用 VIP。应用可通过每台 HAProxy
地址接入，由外部已有入口负责切换；若此前已经配置 Keepalived，HAProxy 重启可能触发其 VIP 漂移。

## 4. 只部署 Keepalived，接入已有 HAProxy

```bash
"$DEPLOY" --status --scope haproxy "${COMMON_ARGS[@]}"
"$DEPLOY" --install-keepalived "${COMMON_ARGS[@]}"
"$DEPLOY" --status "${COMMON_ARGS[@]}"
```

填写真实 VIP、网卡和 VRRP 口令，并确保入口节点之间允许 VRRP（IP 协议 112）及目标网络支持
浮动地址。Keepalived 与 HAProxy 使用同一 `haproxy_lb` 组，不单独创建另一组机器。
三台入口配置不同优先级，如 150/120/100；VIP 仍恰好归属一台。

## 5. 一次部署接入层

```bash
# 已有数据库与 Router，只配置 HAProxy + Keepalived
"$DEPLOY" --configure-lb --skip-kernel-optimization "${COMMON_ARGS[@]}"
# 已有数据库，从 Router 开始配置整个接入层（与上条按需要二选一）
"$DEPLOY" --full-deploy --skip-kernel-optimization "${COMMON_ARGS[@]}"
```

## 验证与排障

`--scope` 仅允许用于 `--check-prereq`、`--status`、`--test-connection`。
范围逐层累加：mysql → router → haproxy → full；full 为默认值并包含 Keepalived/VIP。
它不是降低部署要求的开关，不能用于 `--production-ready` 或 `--apply-config`。

依赖检查失败时，HAProxy/Keepalived 单组件安装不会开始。先检查对应范围中的 SQL、服务和端口，
修复后重跑同一个命令。错误使用 `--limit` 或 `--scope` 会在操作前被拒绝。

## 回退

- 变更前备份该组件配置，出现错误时恢复文件并重新校验该组件，再检查对应范围。
- 仅需停止本轮新启用的 Keepalived 时，以下命令会释放 VIP，业务连接会受影响：

```bash
ansible haproxy_lb "${COMMON_ARGS[@]}" -b -m systemd -a 'name=keepalived state=stopped enabled=no'
"$DEPLOY" --status --scope haproxy "${COMMON_ARGS[@]}"
```

- `--rollback` 会停止整个接入层，包括 Router，不要把它当作单组件回退。
- 完整配置回退、数据恢复和软件降级是不同操作；数据恢复见 [恢复指南](../runbooks/BACKUP_AND_RESTORE_GUIDE.md)。
