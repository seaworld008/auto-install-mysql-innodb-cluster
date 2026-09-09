# MySQL InnoDB Cluster 部署总览

当前仓库只有一条推荐主线：

```text
Git 忽略的本地 inventory + inventory/group_vars/all.yml
  -> scripts/deploy_dedicated_routers.sh
  -> preflight -> deploy / operate -> fail-closed health gate
```

tracked `inventory/hosts*.yml` 只用于脱敏示例与 CI。真实 IP、SSH 凭据、私钥、
Vault 文件和 Secret 不得写入 tracked inventory。

## 推荐入口

- 主入口：`./scripts/deploy_dedicated_routers.sh`
- 主配置：`inventory/group_vars/all.yml`
- Inventory 与 Vault：`inventory/README.md`
- 操作员指南：`docs/runbooks/OPERATOR_GUIDE.md`
- 前置检查：`playbooks/preflight-ha.yml`
- 组合 preflight + health：`playbooks/validate-ha.yml`
- 运行时健康检查实现：`playbooks/health-check-ha.yml`

## 首次准备

控制节点要求 Python 3.12+。所有目标节点必须在 Ansible 首次连接前预装
Python 3.9+；RHEL 8 需要先安装 `python39`。

安装依赖：

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --requirement requirements.txt
ansible-galaxy collection install --requirements-file collections/requirements.yml
```

控制节点 `requirements.txt` 只安装 `ansible-core`；目标 PyMySQL 由安装
playbook 从可信系统仓库部署，不需要在控制节点额外安装。

通过向导创建 Git 忽略的本地 inventory：

```bash
./scripts/setup-servers.sh
```

向导会生成每个集群专用的
`mysql_group_replication_group_name_override`。请通过可信渠道核验 SSH
fingerprint，再写入本机 `known_hosts`；不要关闭主机密钥校验。

`inventory/group_vars/all.yml` 的默认 VIP 是 RFC 5737 文档地址
`192.0.2.100`，preflight 会主动阻断。必须由本地 inventory 覆盖成目标环境已
确认且未冲突的 IPv4；真实私网中的 `192.168.1.100` 可以使用。

创建加密 Vault：

```bash
ansible-vault create inventory/vault.local.yml
```

Vault 至少覆盖以下变量：

```yaml
mysql_root_password: "CHANGE_ME_ROOT_PASSWORD"
mysql_cluster_password: "CHANGE_ME_CLUSTER_PASSWORD"
mysql_replication_password: "CHANGE_ME_REPLICATION_PASSWORD"
keepalived_auth_pass: "CHANGE_ME"
```

`keepalived_auth_pass` 必须替换占位值，且 VRRP PASS 口令最长 8 个字符。
生成的 `/etc/keepalived/keepalived.conf` 包含该口令，自动化以 `0600` 权限写入，
且渲染任务使用 `no_log`。

## 部署与操作

下列示例以 `inventory/hosts.local.yml` 和 Vault 密码文件为例。密码文件必须受限权限
并保持 Git 忽略；交互执行也可改用 `--ask-vault-pass`。

```bash
INVENTORY=inventory/hosts.local.yml
VAULT_ARGS=(--vault-password-file ~/.config/ansible/mysql-cluster-vault-pass)

# 目标环境前置检查
./scripts/deploy_dedicated_routers.sh --check-prereq \
  -i "$INVENTORY" "${VAULT_ARGS[@]}" -e @inventory/vault.local.yml

# 完整部署
./scripts/deploy_dedicated_routers.sh --production-ready \
  -i "$INVENTORY" "${VAULT_ARGS[@]}" -e @inventory/vault.local.yml

# 查看状态
./scripts/deploy_dedicated_routers.sh --status \
  -i "$INVENTORY" "${VAULT_ARGS[@]}" -e @inventory/vault.local.yml

# 滚动应用当前配置
./scripts/deploy_dedicated_routers.sh --apply-config \
  -i "$INVENTORY" "${VAULT_ARGS[@]}" -e @inventory/vault.local.yml

# 可选备份；backup_config.enabled 必须先显式设为 true
./scripts/deploy_dedicated_routers.sh --backup \
  -i "$INVENTORY" "${VAULT_ARGS[@]}" -e @inventory/vault.local.yml
```

主入口同时支持 `-e` / `--extra-vars`、`--ask-vault-pass` 和
`--vault-password-file`，并将其透传给 preflight、部署、inventory 解析及健康检查。
不要把 Vault 口令直接写入命令历史或 tracked 文件。

## 幂等与安全边界

- Router 默认 `mysql_router_rebootstrap: false`；已有配置时跳过 bootstrap。
  只有明确恢复或重建 Router 时才临时设为 `true`。
- 集群配置先识别已有成员，只对 standalone 节点执行
  `checkInstanceConfiguration` 并加入集群；已有成员跳过
  `configureInstance`，完成时等待 inventory 中预期成员全部 `ONLINE`。
- MySQL 缩容会唯一识别目标实例和 primary，移除当前 primary 前要求显式切主，
  完成后再次验证 Cluster `OK` 及剩余成员全部 `ONLINE`。
- Router / HAProxy 缩容要求 `--limit` 精确匹配一台主机，且缩容后仍满足最小
  HA 节点数。
- 自定义 `mysql_datadir` 只会从发行包已初始化的默认目录迁移；非空、未识别的目标
  目录会阻断，不会被覆盖。迁移中断标记允许重跑继续幂等 rsync；Debian / Ubuntu
  收敛 AppArmor，启用 SELinux 的 RedHat 节点持久设置文件上下文并执行
  `restorecon`。
- RedHat 重跑先使用 0600 临时 option file 和无副作用查询探测目标 root 密码；
  已生效时跳过首次临时密码流程，无法安全探测或恢复时直接阻断。
- Router 默认关闭跨客户端空闲后端连接复用（`mysql_router_max_idle_server_connections: 0`），
  应用使用有界连接池；连接与会话语义见 [应用接入指南](docs/runbooks/APPLICATION_CONNECTIONS.md)。
- HAProxy 只接入 Router，避免主从切换后静态 MySQL primary 路径失效。
- HAProxy stats 默认仅监听 `127.0.0.1:8404`。
- Keepalived 跟踪 HAProxy systemd 状态；连续检查失败后进入 `FAULT` 并释放 VIP。
  配置文件保持 `0600`，模板渲染保持 `no_log`。
- MySQL GPG key 和 Percona release 包使用固定 SHA-256；rsync 备份要求严格
  `known_hosts` 校验，并验证 root owner、禁止 group/other 写入；可选私钥必须为
  root 所有且权限仅 `0400` / `0600`。
- 备份支持 MySQL Shell 逻辑备份与 Percona XtraBackup，目标支持
  `local`、`nfs`、`rsync`，且默认关闭。压缩物理备份在同一轮启用 prepare 时，
  先执行 `xtrabackup --decompress`，再执行 `xtrabackup --prepare`。
- `cluster-status.sh`、`failover-test.sh` 等辅助脚本通过隐藏输入或受保护环境变量
  取得密码，再从 stdin 交给 mysqlsh；密码不得出现在 argv。

## 健康检查语义

`scripts/health-check-ha.sh` 执行 `playbooks/validate-ha.yml`，因此
`--status` 和 `--test-connection` 不是单纯探活：它们先执行 preflight，再执行
fail-closed 运行时健康检查。`--production-ready`、`--apply-config`、MySQL
扩容和分层部署结束时也使用对应 full / mysql / router profile 的组合门。

只有对应 profile 启用的以下条件全部成立才返回成功：

- 每个 inventory MySQL 节点都是 `ONLINE` 成员
- InnoDB Cluster 状态严格等于 `OK`，且 ONLINE / topology 成员数与 inventory
  一致
- 所有 Router 的 `mysqlrouter` 服务和 `6446 / 6447 / 6450` 端口可用
- 所有入口节点的 HAProxy、Keepalived 服务和 `3307 / 3308 / 3309` 端口可用
- Keepalived VIP 恰好出现在一个 `haproxy_lb` 节点上，未绑定或双重绑定都失败

健康检查失败会返回非零，不应通过忽略退出码继续发布。

MySQL 缩容因为旧 inventory 在操作完成前仍包含已摘除节点，先在缩容 playbook 内
验证剩余成员；随后必须从 inventory 删除目标，再执行 `--status` 全栈组合检查。

## 本地与 CI 验证

```bash
git diff --check
for script in deploy.sh validate_deployment.sh scripts/*.sh; do
  bash -n "$script" || exit 1
done
./.venv/bin/python -m unittest discover tests
npx --yes markdownlint-cli2@0.23.2
./.venv/bin/yamllint .

for inventory in \
  inventory/hosts.yml \
  inventory/hosts-ha-reference.yml \
  inventory/hosts-with-dedicated-routers.yml
do
  ./.venv/bin/ansible-playbook -i "$inventory" playbooks/site.yml --syntax-check
  ./.venv/bin/ansible-inventory -i "$inventory" --list >/dev/null
done
```

CI 还覆盖全部 playbook syntax-check、Python 3.12 / 3.13、固定 SHA 的 Actions、
阻断式文档 lint、GitHub Actions CodeQL 和 Dependabot 依赖更新。

## 真实环境验收

静态检查、syntax-check、inventory 解析和 CI 通过不证明真实环境已经生产就绪。
上线前仍需在隔离 staging 留存以下证据：

- 完整部署与重复执行
- Router、HAProxy、Keepalived 和 VIP 故障切换
- MySQL 扩容、切主与缩容
- 逻辑或物理备份，以及隔离恢复
- 业务连接、容量和性能

使用 `docs/templates/` 下的记录模板。未实际执行时，应明确写“真实环境验证仍待完成”。

## 详细文档

- 主说明：`README.md`
- 英文入口：`README_EN.md`
- 操作员指南：`docs/runbooks/OPERATOR_GUIDE.md`
- 服务器准备：`docs/runbooks/SERVER_CONFIGURATION.md`
- 备份恢复：`docs/runbooks/BACKUP_AND_RESTORE_GUIDE.md`
- 故障排查：`docs/runbooks/TROUBLESHOOTING.md`
- HA 蓝图：`docs/reference/DEPLOYMENT_HA_BLUEPRINT_ZH.md`
- 变量参考：`docs/reference/VARIABLE_REFERENCE.md`
- 架构与证据：`docs/reference/ARCHITECTURE_AND_EVIDENCE.md`
- 发布清单：`docs/maintainers/RELEASE_CHECKLIST_ZH.md`

## 配置归属与应用接入

新集群的组 UUID 显式传给 AdminAPI；已有集群升级前，应以查询得到的实际组 UUID
校正本地 override。组身份不一致会阻断状态检查，不会自动更改健康集群的 UUID。
完整部署承担依赖安装与账号收敛，`--apply-config` 仅用于受管配置更新。
应用端口、TLS 和重试行为见 [应用接入指南](docs/runbooks/APPLICATION_CONNECTIONS.md)。

## 其他拓扑与组件操作

默认示例之外，可选择 [独立、共置、混合或三节点接入层](docs/scenarios/README.md)。
[组件指南](docs/scenarios/COMPONENTS.md) 覆盖只部署 MySQL、Router、HAProxy、Keepalived；
[内核专项](docs/scenarios/KERNEL.md) 可单独执行。只读状态检查使用 `--scope` 选择范围，
默认 full 保留全部 HA 检查；该选项不能用于缩减完整部署范围。
