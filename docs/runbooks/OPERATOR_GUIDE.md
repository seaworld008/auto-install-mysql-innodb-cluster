# 操作员上手与变更指南

这份指南面向第一次接手本仓库的人，目标是回答四个问题：

- 应该用哪份配置安装
- 修改配置时改哪里
- 部署前如何检查和 dry-run
- 已经部署过以后再次执行是否安全

如果只想快速跑通主线，按本文顺序执行即可。

## 1. 先记住主线

当前仓库只有一条推荐主线：

```text
inventory/hosts-with-dedicated-routers.yml
  + inventory/group_vars/all.yml
  -> scripts/deploy_dedicated_routers.sh
```

含义：

- `inventory/hosts-with-dedicated-routers.yml`：推荐生产候选拓扑，定义哪些机器属于 MySQL、Router、HAProxy。
- `inventory/group_vars/all.yml`：唯一运行时主配置，定义版本、密码、端口、profile、备份、HAProxy、Keepalived、Router 参数。
- `scripts/deploy_dedicated_routers.sh`：主操作入口，部署、检查、扩缩容、滚动配置和备份都从这里走。

不要把 `inventory/group_vars/all-*.yml` 当作当前配置，它们只是历史快照。

## 2. 第一次部署怎么做

### 2.1 安装本地依赖

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements.txt
ansible-galaxy collection install -r collections/requirements.yml
```

### 2.2 选择 inventory

推荐直接使用：

```bash
inventory/hosts-with-dedicated-routers.yml
```

这份 inventory 表达的是：

- 3 台 MySQL InnoDB Cluster 节点
- 2 台独立 MySQL Router 节点
- 2 台 HAProxy + Keepalived 节点

如果不知道其他 inventory 是什么，先看 `inventory/README.md`，不要猜。

### 2.3 修改主机拓扑

编辑：

```bash
vim inventory/hosts-with-dedicated-routers.yml
```

至少替换：

- `ansible_host`
- `ansible_user`
- `ansible_ssh_pass` 或 SSH key 配置
- MySQL 节点的 `mysql_server_id`
- HAProxy 节点的 `keepalived_priority`

要求：

- MySQL 至少 3 节点。
- Router 至少 2 节点。
- HAProxy / Keepalived 至少 2 节点。
- 每个 MySQL 节点的 `mysql_server_id` 必须唯一。

### 2.4 修改运行时主配置

编辑：

```bash
vim inventory/group_vars/all.yml
```

第一次部署至少确认：

```yaml
mysql_release_line: "8.4"
mysql_hardware_profile: "optimized_8c32g"

mysql_root_password: "CHANGE_ME_ROOT_PASSWORD"
mysql_cluster_password: "CHANGE_ME_CLUSTER_PASSWORD"
mysql_replication_password: "CHANGE_ME_REPLICATION_PASSWORD"

keepalived_interface: "{{ ansible_default_ipv4.interface | default('eth0') }}"
keepalived_vip: "192.168.1.100"
```

必须替换所有 `CHANGE_ME_*`。生产环境建议使用 Ansible Vault 或外部 Secret，不要提交真实密码。

### 2.5 部署前检查

先跑不改目标机器的本地检查：

```bash
git diff --check
bash -n deploy.sh validate_deployment.sh scripts/*.sh
./.venv/bin/ansible-inventory -i inventory/hosts-with-dedicated-routers.yml --list >/tmp/inventory-dedicated.json
./.venv/bin/ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/site.yml --syntax-check
```

再跑会连接目标机器、但不安装服务的前置检查：

```bash
./scripts/deploy_dedicated_routers.sh --check-prereq -i inventory/hosts-with-dedicated-routers.yml
```

`--check-prereq` 会验证：

- MySQL / Router / HAProxy 节点数量是否满足最小 HA 要求
- MySQL 密码是否仍是占位符
- inventory 中 SSH 密码是否仍是示例值
- `mysql_server_id` 是否存在且唯一
- MySQL 发行线配置是否一致
- 备份配置在启用时是否完整
- Keepalived 网卡名是否存在

### 2.6 执行部署

确认以上检查通过后执行：

```bash
./scripts/deploy_dedicated_routers.sh --production-ready -i inventory/hosts-with-dedicated-routers.yml
```

部署完成后查看状态：

```bash
./scripts/deploy_dedicated_routers.sh --status -i inventory/hosts-with-dedicated-routers.yml
```

## 3. Dry-run 应该怎么理解

本仓库把 dry-run 分成三层。

### 3.1 本地静态 dry-run

不连接目标机器，只验证仓库、YAML、inventory 和 playbook 语法：

```bash
git diff --check
bash -n deploy.sh validate_deployment.sh scripts/*.sh
./.venv/bin/ansible-inventory -i inventory/hosts-with-dedicated-routers.yml --list >/tmp/inventory-dedicated.json
./.venv/bin/ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/site.yml --syntax-check
```

适合：

- PR 前验证
- 修改 inventory 后确认 YAML 和分组没写坏
- 修改 playbook 后确认语法没写坏

### 3.2 目标环境 preflight

连接目标机器，验证部署前条件，但不安装 MySQL、Router、HAProxy：

```bash
./scripts/deploy_dedicated_routers.sh --check-prereq -i inventory/hosts-with-dedicated-routers.yml
```

适合：

- 首次部署前
- 改 inventory 后
- 改密码、VIP、版本线、备份配置后

### 3.3 Ansible check mode

Ansible 支持 `--check --diff`，但本仓库包含包安装、MySQL Shell、Router bootstrap、系统服务和 shell 命令，并不是每个任务都能完整模拟。

可以在 staging 中把它当作“额外预览”：

```bash
./.venv/bin/ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/site.yml --check --diff
```

不要把 check mode 通过理解成真实部署一定成功。最终仍以 staging 部署、健康检查、故障演练和恢复演练为准。

## 4. 已经部署过，再执行会不会有风险

设计目标是保持幂等和收敛，但不是“零影响”。

### 4.1 相对安全的重复操作

这些操作可以反复执行，用于检查或读取状态：

```bash
./scripts/deploy_dedicated_routers.sh --check-prereq -i inventory/hosts-with-dedicated-routers.yml
./scripts/deploy_dedicated_routers.sh --status -i inventory/hosts-with-dedicated-routers.yml
./scripts/deploy_dedicated_routers.sh --test-connection -i inventory/hosts-with-dedicated-routers.yml
```

### 4.2 首次部署后不建议随手重复全量部署

`--production-ready` 是完整部署 / 收敛入口。它会执行：

- preflight
- 内核优化
- MySQL 安装与配置
- InnoDB Cluster 配置
- Router 部署
- HAProxy / Keepalived 部署
- 健康检查

这些 playbook 尽量使用 Ansible 幂等模块和条件判断，但重复执行仍可能：

- 重新渲染配置
- 重启或 reload 服务
- 再次执行内核优化
- 触发包管理器检查
- 对入口层产生短暂扰动

所以生产环境中不要把 `--production-ready` 当作日常状态检查命令。已经部署后，优先使用 `--status`、`--check-prereq`、`--apply-config` 或具体的扩缩容入口。

如确实需要重新收敛全量部署，应在维护窗口执行，并先在 staging 验证。

### 4.3 Router bootstrap 的幂等边界

Router 默认不会重复 bootstrap：

```yaml
mysql_router_rebootstrap: false
```

只有在明确需要重新 bootstrap Router 时才改为 `true`。改完后应再改回 `false`，避免后续重复执行造成不必要扰动。

### 4.4 破坏性操作必须显式

这些操作不会隐藏在普通部署中，必须显式指定：

```bash
./scripts/deploy_dedicated_routers.sh --scale-mysql-remove --target <host> --new-primary <host> -i inventory/hosts-with-dedicated-routers.yml
./scripts/deploy_dedicated_routers.sh --shrink-router --limit <router-host> -i inventory/hosts-with-dedicated-routers.yml
./scripts/deploy_dedicated_routers.sh --shrink-lb --limit <haproxy-host> -i inventory/hosts-with-dedicated-routers.yml
```

MySQL 缩容默认不清理数据目录：

```yaml
scale_policy:
  mysql_remove_cleanup_data: false
```

只有确认备份、恢复路径和回滚方案后，才考虑改成清理数据。

## 5. 已部署后如何改配置

### 5.1 修改 MySQL 参数

1. 修改 `inventory/group_vars/all.yml`
2. 确认变量已被 `roles/mysql-server/templates/my.cnf.j2` 使用
3. 跑静态检查和 preflight
4. 使用滚动配置入口

```bash
./scripts/deploy_dedicated_routers.sh --apply-config -i inventory/hosts-with-dedicated-routers.yml
```

`--apply-config` 会按当前主配置滚动应用 MySQL、Router、HAProxy、Keepalived 相关配置。生产环境建议维护窗口执行。

### 5.2 切换硬件 profile

只切换：

```yaml
mysql_hardware_profile: "optimized_8c32g"
```

不要新增或复制整份 `group_vars/all-xxx.yml` 作为运行配置。

可使用：

```bash
./scripts/config_manager.sh
```

切换后执行：

```bash
./scripts/deploy_dedicated_routers.sh --check-prereq -i inventory/hosts-with-dedicated-routers.yml
./scripts/deploy_dedicated_routers.sh --apply-config -i inventory/hosts-with-dedicated-routers.yml
```

### 5.3 修改 VIP 或 HAProxy 入口

修改：

```yaml
keepalived_interface: "ens192"
keepalived_vip: "10.20.30.100"
haproxy_mysql_rw_port: 3307
haproxy_mysql_ro_port: 3308
haproxy_mysql_rwsplit_port: 3309
```

然后执行：

```bash
./scripts/deploy_dedicated_routers.sh --check-prereq -i inventory/hosts-with-dedicated-routers.yml
./scripts/deploy_dedicated_routers.sh --configure-lb -i inventory/hosts-with-dedicated-routers.yml
./scripts/deploy_dedicated_routers.sh --status -i inventory/hosts-with-dedicated-routers.yml
```

### 5.4 修改备份配置

修改 `backup_config`，例如：

```yaml
backup_config:
  enabled: true
  method: "logical"
  type: "rsync"
  base_dir: "/backup/mysql"
  remote_host: "10.20.40.20"
  remote_user: "backup"
  remote_dir: "/data/mysql-backups"
```

先检查：

```bash
./scripts/deploy_dedicated_routers.sh --check-prereq -i inventory/hosts-with-dedicated-routers.yml
```

再手动执行一次备份：

```bash
./scripts/deploy_dedicated_routers.sh --backup -i inventory/hosts-with-dedicated-routers.yml
```

备份恢复验证必须在隔离环境执行，不能只看备份命令成功。

## 6. 常见任务入口

| 任务 | 推荐命令 |
| --- | --- |
| 部署前检查 | `./scripts/deploy_dedicated_routers.sh --check-prereq -i inventory/hosts-with-dedicated-routers.yml` |
| 完整首次部署 | `./scripts/deploy_dedicated_routers.sh --production-ready -i inventory/hosts-with-dedicated-routers.yml` |
| 查看状态 | `./scripts/deploy_dedicated_routers.sh --status -i inventory/hosts-with-dedicated-routers.yml` |
| 修改配置后滚动应用 | `./scripts/deploy_dedicated_routers.sh --apply-config -i inventory/hosts-with-dedicated-routers.yml` |
| 仅部署 / 重配 Router | `./scripts/deploy_dedicated_routers.sh --install-routers -i inventory/hosts-with-dedicated-routers.yml` |
| 仅部署 / 重配 HAProxy + Keepalived | `./scripts/deploy_dedicated_routers.sh --configure-lb -i inventory/hosts-with-dedicated-routers.yml` |
| 新增 MySQL 节点 | `./scripts/deploy_dedicated_routers.sh --scale-mysql-add --limit <new-host> -i inventory/hosts-with-dedicated-routers.yml` |
| 移除 MySQL 节点 | `./scripts/deploy_dedicated_routers.sh --scale-mysql-remove --target <host> --new-primary <host> -i inventory/hosts-with-dedicated-routers.yml` |
| 缩容 Router | `./scripts/deploy_dedicated_routers.sh --shrink-router --limit <router-host> -i inventory/hosts-with-dedicated-routers.yml` |
| 缩容 HAProxy | `./scripts/deploy_dedicated_routers.sh --shrink-lb --limit <haproxy-host> -i inventory/hosts-with-dedicated-routers.yml` |
| 执行一次备份 | `./scripts/deploy_dedicated_routers.sh --backup -i inventory/hosts-with-dedicated-routers.yml` |

## 7. 每次变更后的最低验收

文档或 inventory 变更：

```bash
git diff --check
npx --yes markdownlint-cli2
./.venv/bin/ansible-inventory -i inventory/hosts-with-dedicated-routers.yml --list >/tmp/inventory-dedicated.json
./.venv/bin/ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/site.yml --syntax-check
```

脚本、playbook、模板或变量行为变更：

```bash
git diff --check
bash -n deploy.sh validate_deployment.sh scripts/*.sh
./.venv/bin/ansible-playbook -i inventory/hosts.yml playbooks/site.yml --syntax-check
./.venv/bin/ansible-playbook -i inventory/hosts-ha-reference.yml playbooks/site.yml --syntax-check
./.venv/bin/ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/site.yml --syntax-check
./.venv/bin/ansible-inventory -i inventory/hosts.yml --list >/tmp/inventory-hosts.json
./.venv/bin/ansible-inventory -i inventory/hosts-ha-reference.yml --list >/tmp/inventory-ha.json
./.venv/bin/ansible-inventory -i inventory/hosts-with-dedicated-routers.yml --list >/tmp/inventory-dedicated.json
```

真实上线前还需要：

- staging 部署记录
- HA 故障演练记录
- 备份恢复演练记录
- 业务连接验证

静态检查通过只能说明语法和 inventory 解析通过，不能证明生产就绪。
