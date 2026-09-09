# 扩缩容：MySQL、Router 与入口节点

## 准备

完成 [公共准备](COMMON.md)，使用正在管理的本地 inventory/settings/Vault，定义共用参数。
先执行 `"$DEPLOY" --status "${COMMON_ARGS[@]}"`；仅数据库环境使用 `--scope mysql`。
变更前保存 inventory 和配置，准备业务维护窗口与可恢复备份。

```bash
umask 077
(set -o noclobber; cat "$INVENTORY" > "${INVENTORY}.backup.$(date +%Y%m%d%H%M%S)")
```

## 增加第四台 MySQL

以方案模板中的 db1/db2/db3 为基础，在本地 inventory 的现有 `all.hosts` 中新增 db4，
并在现有 `mysql_secondary.hosts` 中引用它。不要重复创建另一个 `all` 或 `children` 键：

```yaml
# 合并到 all.hosts
  db4:
    ansible_host: 192.0.2.14
    mysql_server_id: 4
# 合并到 all.children.mysql_cluster.children.mysql_secondary.hosts
  db4: {}
```

替换 IP，准备 SSH 指纹、Python、提权和磁盘。server_id 必须唯一。

```bash
ansible-inventory "${COMMON_ARGS[@]}" --graph
"$DEPLOY" --scale-mysql-add --limit db4 --skip-kernel-optimization "${COMMON_ARGS[@]}"
"$DEPLOY" --status --scope mysql "${COMMON_ARGS[@]}"
```

新增节点由主流程安装并加入集群；内核参数如需调整，先执行 [内核专项](KERNEL.md)。
不要直接启动一个预装镜像后将其当作已经加入的成员。

## 移除 MySQL 节点

目标必须仍在 inventory 中，操作成功后才能摘除。示例将 db1 指定为接替写节点：

```bash
"$DEPLOY" --scale-mysql-remove --target db4 --new-primary db1 "${COMMON_ARGS[@]}"
```

如果 db4 是当前 primary，会先切主再移除；剩余成员必须达到完整健康状态。
成功后从 `mysql_secondary` 和其他不再使用的组移除 db4。若移除的是 `mysql_primary` 中的
管理节点，还需把一个剩余成员设为唯一的 mysql_primary，其余放 mysql_secondary。

```bash
${EDITOR:-vi} "$INVENTORY"
"$DEPLOY" --status --scope mysql "${COMMON_ARGS[@]}"
```

不允许从三节点缩到两节点来规避默认 HA 基线。缩容默认停止目标 MySQL 服务但保留数据，
不能在未核实备份和归属的情况下另行删除数据。

## 从两台增加到三台 Router / LB

在 `all.hosts` 添加 router3 或 lb3，并在对应组引用；也可直接参照
[三接入节点模板](https://github.com/seaworld008/auto-install-mysql-innodb-cluster/blob/main/examples/topologies/three-entry.yml) 的组关系，但不要覆盖正在使用的 inventory。

```yaml
# 新 Router：合并到 all.hosts
  router3:
    ansible_host: 192.0.2.23
# 再合并到 mysql_router.hosts
  router3: {}

# 新入口：合并到 all.hosts
  lb3:
    ansible_host: 192.0.2.33
    keepalived_priority: 100
# 再合并到 haproxy_lb.hosts
  lb3: {}
```

每次只新增一种角色；不要先把未准备的 LB 与 Router 一起登记，再期待完整检查通过。
核对所有 LB 的优先级唯一，例如 150/120/100。新增 Router 后，需要让 HAProxy 后端列表收敛：

```bash
"$DEPLOY" --install-routers --skip-kernel-optimization "${COMMON_ARGS[@]}"
"$DEPLOY" --install-haproxy "${COMMON_ARGS[@]}"
"$DEPLOY" --status "${COMMON_ARGS[@]}"
```

新增入口时使用组合操作，依次安装 HAProxy 和 Keepalived：

```bash
"$DEPLOY" --configure-lb --skip-kernel-optimization "${COMMON_ARGS[@]}"
"$DEPLOY" --status "${COMMON_ARGS[@]}"
```

这些操作会对角色组收敛，而不是只碰新主机；已有 Router 默认保留 keyring 与身份。
若只运行 HAProxy 阶段，检查用 `--scope haproxy`；完成 Keepalived 后再用完整状态门。

## 缩减 Router / LB

```bash
"$DEPLOY" --shrink-router --limit router3 "${COMMON_ARGS[@]}"
# 成功后从 mysql_router 组移除 router3；共置主机不要从其他角色组删除
${EDITOR:-vi} "$INVENTORY"
"$DEPLOY" --install-haproxy "${COMMON_ARGS[@]}"
"$DEPLOY" --status "${COMMON_ARGS[@]}"

"$DEPLOY" --shrink-lb --limit lb3 "${COMMON_ARGS[@]}"
# 成功后从 haproxy_lb 组移除 lb3
${EDITOR:-vi} "$INVENTORY"
"$DEPLOY" --status "${COMMON_ARGS[@]}"
```

Router 缩容后更新 HAProxy，去掉旧后端。LB 缩容前确认 VIP 与剩余节点状态；三台缩到两台可以，
两台缩到一台会被默认 HA 门阻断。`--limit` 必须精确匹配一台主机，不能传整个角色组。

## 排障与回退

- 新节点加入失败：保留原健康集群，检查版本、连接、空间、GTID 与 clone 前置条件后重试。
- inventory 数量与实际成员不一致：先判断操作是否完成，再修正 inventory，不能跳过状态门。
- 共置主机：移除 Router 或 LB 角色不等于删除整台主机；保留数据库分组及其连接变量。
- 回退扩容：先通过缩容操作移除已加入的成员，再调整 inventory；不要先停机或直接删除数据。
- 已移除节点重新使用时先核对残留数据和身份，按加入流程处理，不盲目启动旧实例。

MySQL 新节点必须同时属于 `mysql_secondary` 与 `scale_policy.mysql_scale_target_group`
（默认也是 `mysql_secondary`）；自定义目标组可作为扩容允许名单，但应引用同一个主机身份。
目标归属不正确会在内核配置和数据库安装前被拒绝。
