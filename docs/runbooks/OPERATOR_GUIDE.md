# 操作员上手与变更指南

本文面向首次接手部署或维护的 DBA / SRE。目标是使用唯一主入口完成安全准备、
部署、状态检查、配置变更、扩缩容和备份，并区分静态结果与真实环境证据。

## 1. 唯一主线

```text
inventory/hosts.local.yml                  # Git 忽略，本地拓扑
inventory/vault.local.yml                  # Git 忽略，Ansible Vault
inventory/group_vars/all.yml               # tracked 非敏感运行时真相源
  -> scripts/deploy_dedicated_routers.sh    # 唯一主操作入口
```

tracked `inventory/hosts*.yml` 只用于脱敏示例与 CI。不要直接在其中写入真实 IP、
SSH 密码、私钥路径或 Secret。历史 `inventory/group_vars/all-*.yml` 不是运行时
配置。

推荐拓扑：

- 3 个 MySQL InnoDB Cluster 节点
- 至少 2 个独立 Router 节点
- 至少 2 个 HAProxy + Keepalived 节点

应用链路固定为：

```text
App -> HAProxy VIP -> MySQL Router -> InnoDB Cluster
```

HAProxy 不支持直接指向静态 MySQL primary。

## 2. 首次准备

### 2.1 安装本地依赖

控制节点要求 Python 3.12+。所有目标节点必须预装 Python 3.9+；
RHEL 8 在首次连接前需安装 `python39`。

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --requirement requirements.txt
ansible-galaxy collection install --requirements-file collections/requirements.yml
python -m pip check
```

`requirements.txt` 只安装控制节点的 `ansible-core`。Ansible collections 由
`collections/requirements.yml` 安装；目标 PyMySQL 由安装 playbook 从可信系统
仓库部署。

### 2.2 创建本地 inventory

```bash
./scripts/setup-servers.sh
```

默认输出是 Git 忽略的 `inventory/hosts.local.yml`。向导会：

- 收集 3 MySQL + 2 Router + 2 HAProxy 拓扑
- 写入 `StrictHostKeyChecking=yes`
- 为该集群生成唯一 `mysql_group_replication_group_name_override`
- 不向 inventory 写入 MySQL 明文密码

先通过可信渠道核验每台主机的 SSH fingerprint，再将公钥写入本机
`~/.ssh/known_hosts`。不得使用 `StrictHostKeyChecking=no` 或
`UserKnownHostsFile=/dev/null` 绕过校验。

每个 MySQL 节点必须有唯一 `mysql_server_id`，每个 HAProxy 节点应设置不同的
`keepalived_priority`。

### 2.3 创建 Vault

```bash
ansible-vault create inventory/vault.local.yml
```

加密文件至少包含：

```yaml
mysql_root_password: "CHANGE_ME_ROOT_PASSWORD"
mysql_cluster_password: "CHANGE_ME_CLUSTER_PASSWORD"
mysql_replication_password: "CHANGE_ME_REPLICATION_PASSWORD"
keepalived_auth_pass: "CHANGE_ME"
```

`keepalived_auth_pass` 必须不是占位值，且最长 8 个字符。Vault 文件可以保留在
本地 inventory 目录，也可以由 CI/CD Secret 或外部 Secret Manager 在运行时
生成；不得提交解密后的值或 Vault 口令。

主入口支持三类 Ansible 参数透传：

```text
-e / --extra-vars <表达式或 @文件>
--ask-vault-pass
--vault-password-file <受保护文件>
```

后文以交互式 Vault 为例：

```bash
INVENTORY=inventory/hosts.local.yml
COMMON_ARGS=(--ask-vault-pass -e @inventory/vault.local.yml)
```

### 2.4 修改非敏感主配置

编辑 `inventory/group_vars/all.yml`，至少确认：

```yaml
mysql_release_line: "8.4"
mysql_hardware_profile: "optimized_8c32g"
mysql_datadir: "/data/mysql"

keepalived_interface: "{{ ansible_default_ipv4.interface | default('eth0') }}"
keepalived_vip: "10.20.30.100"
```

主配置中的 `192.0.2.100` 是 RFC 5737 文档地址，preflight 必定阻断。必须覆盖为
目标环境已确认且未冲突的 IPv4；真实私网中的 `192.168.1.100` 是合法候选。

集群 UUID 不直接修改默认表达式，而是由本地 inventory 覆盖：

```yaml
mysql_group_replication_group_name_override: "UNIQUE-UUID-FOR-THIS-CLUSTER"
```

## 3. 部署前检查

### 3.1 本地静态门

```bash
git diff --check
bash -n deploy.sh validate_deployment.sh scripts/*.sh
./.venv/bin/python -m unittest discover tests
npx --yes markdownlint-cli2@0.23.2
./.venv/bin/yamllint .
./.venv/bin/ansible-inventory -i "$INVENTORY" \
  "${COMMON_ARGS[@]}" --list >/tmp/mysql-cluster-inventory.json
./.venv/bin/ansible-playbook -i "$INVENTORY" \
  "${COMMON_ARGS[@]}" playbooks/site.yml --syntax-check
```

### 3.2 目标环境 preflight

```bash
./scripts/deploy_dedicated_routers.sh --check-prereq \
  -i "$INVENTORY" "${COMMON_ARGS[@]}"
```

preflight 会阻断：

- 节点数低于 HA 最小值
- 密码、Keepalived 口令或 UUID 仍为占位值
- MySQL `server_id` 缺失或重复
- `mysql_datadir` 不是绝对路径
- HAProxy 后端不是 `router`
- VIP 是默认 `192.0.2.100`、其他 RFC 5737 文档地址、无效 / 回环 / 组播地址
- 版本线、备份目标或 rsync `known_hosts` 参数不合法
- 所选目标节点无法找到 Python 3.9+
- Keepalived 网卡不存在

`--mysql-only` 会显式关闭 Router / HAProxy 数量要求，但不会放宽 MySQL 或 Secret
检查。

### 3.3 Check mode 的边界

可以在隔离 staging 预览：

```bash
./.venv/bin/ansible-playbook -i "$INVENTORY" \
  "${COMMON_ARGS[@]}" playbooks/site.yml --check --diff
```

包安装、MySQL Shell、Router bootstrap 和 systemd 任务不能全部被 check mode
真实模拟。该结果不是部署成功证据。

## 4. 首次部署与状态门

```bash
./scripts/deploy_dedicated_routers.sh --production-ready \
  -i "$INVENTORY" "${COMMON_ARGS[@]}"
```

默认顺序是 preflight、内核优化、MySQL、Cluster、Router、HAProxy、Keepalived 和
健康检查。仅在明确不希望本轮改变内核参数时添加
`--skip-kernel-optimization`。

部署后可重复执行：

```bash
./scripts/deploy_dedicated_routers.sh --status \
  -i "$INVENTORY" "${COMMON_ARGS[@]}"
```

`--status` 调用 `scripts/health-check-ha.sh`，后者执行
`playbooks/validate-ha.yml`：先运行 profile 对应的 preflight，再运行
fail-closed 健康检查。`--test-connection` 使用同一组合门，并不是绕过 preflight
的单纯端口探测。

以下任何一项失败都会返回非零：

- 任一 inventory MySQL 节点不是本地 Group Replication `ONLINE` 成员
- InnoDB Cluster 状态不严格等于 `OK`，或 topology / ONLINE 数量与 inventory
  不一致
- 任一 Router 的服务或 `6446 / 6447 / 6450` 监听失败
- 任一入口节点的 HAProxy / Keepalived 服务失败
- `3307 / 3308 / 3309` 任一 HAProxy 端口未监听
- VIP 未绑定，或同时绑定到多个 `haproxy_lb` 节点；健康状态要求恰好一处

不要使用 `|| true`、禁用失败检查或只读日志文本来绕过该门。

## 5. 重复执行与配置变更

### 5.1 全量部署不是日常状态命令

`--production-ready` 以收敛为目标，但可能重新渲染配置、检查软件包、reload /
restart 服务和再次应用内核参数。已部署环境优先使用 `--status`、
`--check-prereq`、`--apply-config` 或具体操作，并在维护窗口执行有扰动的变更。

### 5.2 Router bootstrap

默认：

```yaml
mysql_router_rebootstrap: false
```

存在 bootstrap 配置时会跳过。只有明确恢复或重建 Router 时才临时设置为 `true`；
完成后恢复 `false`。bootstrap 不配置跨节点共享 Router 账号，密码通过标准输入
传递。

### 5.3 集群配置

集群 playbook 会查询成员身份：

- 已是成员：跳过 `configureInstance`
- standalone：运行 `checkInstanceConfiguration`，要求 Ansible 管理的配置已合格，
  再加入集群
- 结束时：要求 Cluster `OK` 且 inventory 预期成员全部 `ONLINE`

这仍不能替代真实维护窗口中的重复执行和故障演练。

### 5.4 自定义 datadir

安装流程会先让发行包在默认 `/var/lib/mysql` 完成初始化，再在目标
`mysql_datadir` 未初始化且为空时使用 rsync 迁移。它会：

- 拒绝覆盖非空、未识别的目标目录
- 迁移前写入 0600 中断标记；重跑发现标记时允许继续幂等 rsync，完成后写入
  完成标记并清理中断标记
- 停止 MySQL 后迁移并收敛 owner / mode
- 为 Debian / Ubuntu 配置 AppArmor
- 为启用 SELinux 的 RedHat 节点持久配置 datadir / logdir 文件上下文并运行
  `restorecon`
- 运行 `mysqld --validate-config`
- 启动后查询 `@@datadir` 并要求与配置一致

RedHat 重跑还会先创建 0600 临时 option file，用目标 root 密码执行无副作用
`SELECT 1`。密码已生效时跳过临时密码重置；只有探测失败且找到首次临时密码时才
重置，二者均不可用时 fail closed。临时文件和相关任务保持 `no_log`。

已有数据的迁移仍应先备份，并在 staging 验证停机窗口和回滚。

### 5.5 滚动应用

修改 `inventory/group_vars/all.yml` 后：

```bash
./scripts/deploy_dedicated_routers.sh --check-prereq \
  -i "$INVENTORY" "${COMMON_ARGS[@]}"
./scripts/deploy_dedicated_routers.sh --apply-config \
  -i "$INVENTORY" "${COMMON_ARGS[@]}"
```

`--apply-config` 完成后运行同一 fail-closed 健康门。

## 6. 扩缩容

### 6.1 新增 MySQL 节点

先将新节点加入本地 inventory，再执行：

```bash
./scripts/deploy_dedicated_routers.sh --scale-mysql-add \
  --limit mysql-node4 -i "$INVENTORY" "${COMMON_ARGS[@]}"
```

`--limit` 必须精确匹配一台 MySQL 主机。

### 6.2 移除 MySQL 节点

```bash
./scripts/deploy_dedicated_routers.sh --scale-mysql-remove \
  --target mysql-node3 --new-primary mysql-node2 \
  -i "$INVENTORY" "${COMMON_ARGS[@]}"
```

流程会唯一识别目标 UUID 和当前 ONLINE primary。移除当前 primary 时必须提供
不同且有效的 `--new-primary`；缩容后必须满足最小节点数，并再次确认 Cluster
`OK` 和剩余成员全部 `ONLINE`。默认：

```yaml
scale_policy:
  mysql_remove_cleanup_data: false
  mysql_remove_stop_service: true
```

只有已确认备份、隔离恢复和回滚方案时才启用数据清理。

缩容 playbook 结束时旧 inventory 仍包含已摘除节点，因此不会立即运行全栈
`validate-ha.yml`。先从本地 inventory 删除目标，再执行 `--status`。

### 6.3 缩容 Router 或入口节点

```bash
./scripts/deploy_dedicated_routers.sh --shrink-router \
  --limit router-node2 -i "$INVENTORY" "${COMMON_ARGS[@]}"
./scripts/deploy_dedicated_routers.sh --shrink-lb \
  --limit lb-node2 -i "$INVENTORY" "${COMMON_ARGS[@]}"
```

`--limit` 必须在对应组中精确匹配一台主机，且删除后不能低于配置的最小节点数。

## 7. 入口层

- HAProxy 只连接 Router 的 RW、RO 和 R/W Split 端口。
- 应用默认使用 VIP `3309`；显式 RW / RO 为 `3307 / 3308`。
- stats 默认只监听 `127.0.0.1:8404`，如需远程查看请使用 SSH tunnel 或受控
  监控代理。
- Keepalived 使用 `/usr/bin/systemctl is-active --quiet haproxy`，
  `weight 0`；连续 `keepalived_check_fall` 次失败后实例进入 `FAULT` 并释放 VIP，
  连续 `keepalived_check_rise` 次成功后恢复。
- `/etc/keepalived/keepalived.conf` 含认证口令，保持 root 所有、`0600`，Ansible
  模板渲染任务使用 `no_log`。
- `--rollback` 按 Keepalived、HAProxy、Router 顺序停止入口层；任一步失败会返回
  非零，且不会删除 MySQL 数据。恢复应重新运行相应安装 / 配置入口并通过健康门。

## 8. 备份

`backup_config.enabled` 默认是 `false`。支持：

- `method: logical`：MySQL Shell `util.dumpInstance`
- `method: xtrabackup`：Percona XtraBackup
- `type: local | nfs | rsync`

执行：

```bash
./scripts/deploy_dedicated_routers.sh --backup \
  -i "$INVENTORY" "${COMMON_ARGS[@]}"
```

供应链与传输约束：

- MySQL GPG key 和 Percona release 安装包必须匹配 `all.yml` 固定 SHA-256。
- Percona 仓库只通过 HTTPS 启用。
- rsync 目标必须预先核验 fingerprint，并配置绝对路径
  `backup_config.ssh_known_hosts_file`。
- rsync 强制 BatchMode 和严格主机密钥校验。
- `known_hosts` 必须是 root 所有的普通文件，且 group / other 不可写；可选
  `ssh_key_path` 必须是 root 所有普通文件，权限只能为 `0400` 或 `0600`。
- 压缩 XtraBackup 同时启用 `prepare: true` 时，先运行
  `xtrabackup --decompress`，再运行 `xtrabackup --prepare`。
- 数据库密码不放入命令行参数。

备份任务成功不代表可恢复。至少选择一种备份方法在隔离环境执行 restore drill。

辅助 `cluster-status.sh` / `failover-test.sh` 只允许隐藏交互输入，或由自动化通过
受保护的 `MYSQL_CLUSTER_PASSWORD` 环境变量注入；密码经
`--passwords-from-stdin` 送入 mysqlsh，不得作为位置参数或 `--password` argv。
`failover-test.sh` 还要求隔离环境显式设置 `ALLOW_FAILOVER_DRILL=1`。

## 9. 真实环境验收

静态检查和 CI 仅证明仓库可解析、契约检查通过。生产变更前仍需留存：

- staging 首次部署与重复收敛记录
- MySQL / Router / HAProxy / Keepalived 故障演练
- VIP 漂移和业务端重连验证
- 扩容、切主、缩容记录
- 逻辑或物理备份的隔离恢复记录
- 容量和性能验证

记录模板在 `docs/templates/`。如果没有执行，应准确写“真实环境验证仍待完成”。
