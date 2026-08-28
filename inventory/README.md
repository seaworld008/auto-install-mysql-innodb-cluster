# Inventory 使用说明

本目录放 Ansible inventory 和全局运行时变量。第一次接手时，请先记住一条原则：

**真实主机拓扑看被 Git 忽略的 `hosts.local.yml`，非敏感运行时参数看 `group_vars/all.yml`。**

仓库内已跟踪的 `hosts-*.yml` 只用于脱敏示例与 CI，不得写入真实 IP、SSH 凭据或私钥路径。如果本地 inventory 也写了 Router、HAProxy、端口或性能参数，而它和 `group_vars/all.yml` 冲突，以 `group_vars/all.yml` 作为非敏感运行时真相源；Secret 通过 Vault 或外部 Secret 在执行时覆盖。

首次部署、dry-run、重复执行和已部署后改配置的完整流程见 `docs/runbooks/OPERATOR_GUIDE.md`。

控制节点要求 Python 3.12+，目标节点要求 Python 3.9+。向导使用
`ansible_python_interpreter: auto_silent`；RHEL 8 必须先预装
`python39`，混合发行版环境可在本地 inventory 中按主机显式覆盖解释器路径。

## 推荐选择

| 文件 | 推荐程度 | 适用场景 | 说明 |
| --- | --- | --- | --- |
| `hosts.local.yml` | 实际部署首选 | 新部署、生产候选、完整 HA 拓扑 | 向导生成的本地文件：3 台 MySQL + 2 台独立 Router + 2 台 HAProxy/Keepalived；Git 忽略，权限 `0600`。 |
| `vault.local.yml` | 实际部署必备 | Ansible Vault 加密变量 | 保存三个 MySQL 运行时密码变量；Git 忽略，通过主入口 `-e` 传入。 |
| `hosts-with-dedicated-routers.yml` | 首选模板 | 拓扑参考、CI syntax-check | 完整 HA 脱敏模板，不得写入真实环境数据。 |
| `hosts-ha-reference.yml` | 推荐参考 | 精简 HA 示例、文档演示、CI syntax-check | 结构更短，表达最小 HA 拓扑。适合看清分组关系，也可作为 staging 示例。 |
| `hosts.yml` | 基础示例 | 本地理解、基础语法检查、资源受限测试 | Router 和 HAProxy 示例可与 MySQL 同机，不是生产默认拓扑。 |
| `hosts-recommended-router.yml` | 场景参考 | 对比 Router 部署方式 | 包含独立 Router、应用侧 Router、容器化等片段。不要把它当作当前主部署入口直接照搬。 |
| `group_vars/all.yml` | 必改 | 所有部署和运维 | 当前唯一运行时主配置，包含版本、密码占位符、profile、HA、备份、Router、HAProxy、Keepalived 等参数。 |

## 日常怎么用

### 生产候选或标准 HA 部署

优先使用：

```bash
./scripts/setup-servers.sh
ansible-vault create inventory/vault.local.yml

# 这里只维护非敏感参数
vim inventory/group_vars/all.yml

./scripts/deploy_dedicated_routers.sh --check-prereq \
  -i inventory/hosts.local.yml \
  --ask-vault-pass -e @inventory/vault.local.yml
./scripts/deploy_dedicated_routers.sh --production-ready \
  -i inventory/hosts.local.yml \
  --ask-vault-pass -e @inventory/vault.local.yml
```

这也是 README 和 Quick Start 推荐的安全路径。主操作仍统一通过 `scripts/deploy_dedicated_routers.sh`。
多阶段流程使用 `--ask-vault-pass` 时可能重复询问；自动化推荐仓库外
权限 `0600` 的 `--vault-password-file`。

### 只想看清最小 HA 分组

看：

```bash
inventory/hosts-ha-reference.yml
```

它保留了核心分组：

- `mysql_cluster`
- `mysql_primary`
- `mysql_secondary`
- `mysql_router`
- `haproxy_lb`

适合学习拓扑、做轻量 staging 示例或运行 syntax-check。真实部署仍要替换 IP、SSH 用户、认证方式和 VIP。

### 资源有限的测试环境

可以参考：

```bash
inventory/hosts.yml
```

这份示例展示 Router / HAProxy 与 MySQL 同机部署的形态，适合实验或基础检查。生产环境不建议以同机部署作为默认基线，因为数据库层、路由层和入口层故障域会耦合。

### 研究 Router 部署方式

看：

```bash
inventory/hosts-recommended-router.yml
```

这份文件更像“场景清单”，里面有独立 Router、应用侧 Router、容器化 Router、连接串示例等片段。它的价值是帮助你理解方案取舍，不是替代 `hosts-with-dedicated-routers.yml` 成为主部署 inventory。

## `group_vars/` 说明

| 文件 | 状态 | 用途 |
| --- | --- | --- |
| `group_vars/all.yml` | 当前主配置 | 唯一运行时真相源。所有新增参数、profile、备份配置、HA 基线都应进入这里。 |
| `group_vars/all-8c32g-optimized.yml` | 历史快照 | 旧的 8C32G 优化副本，保留用于对比，不建议复制覆盖 `all.yml`。 |
| `group_vars/all-original-10k-config.yml` | 历史快照 | 旧的 10K 连接配置副本，容量压力更高，保留用于参考，不是运行时配置。 |

新增硬件或容量方案时，不要新增新的 `all-xxx.yml` 运行副本。应在 `group_vars/all.yml` 的 `mysql_config_profiles` 下新增 profile，然后通过：

```bash
./scripts/config_manager.sh
```

或直接修改：

```yaml
mysql_hardware_profile: "optimized_8c32g"
```

来选择当前 profile。

## 必须替换的内容

部署前至少确认：

- `inventory/hosts.local.yml` 未被 Git 跟踪且权限为 `0600`
- `ansible_host`
- `ansible_user`
- 优先使用仓库外的 SSH key；若使用 SSH 密码，只能保存在本地 inventory 或外部 Secret
- 每台主机的 SSH fingerprint 已通过可信渠道核验并写入 `known_hosts`
- `mysql_server_id` 唯一
- `mysql_group_replication_group_name_override` 是该独立集群专用的唯一 UUID，不能复用默认或其他集群的 UUID
- `keepalived_vip` 是未被占用的内网 VIP
- 加密 Vault 或外部 Secret 已覆盖 `mysql_root_password`
- 加密 Vault 或外部 Secret 已覆盖 `mysql_cluster_password`
- 加密 Vault 或外部 Secret 已覆盖 `mysql_replication_password`
- `mysql_release_line` 符合目标版本线

向导会为每次生成的本地 inventory 创建新的 Group Replication UUID。生产环境建议使用 Ansible Vault、SSH key、CI/CD Secret 或专用 Secret Manager；不得把真实 IP、密码、私钥或 Vault 口令写入 tracked 文件。

## 文件之间的主要区别

下表只比较仓库内已跟踪的脱敏模板；它们都不应直接承载真实环境数据。

| 对比项 | `hosts-with-dedicated-routers.yml` | `hosts-ha-reference.yml` | `hosts.yml` | `hosts-recommended-router.yml` |
| --- | --- | --- | --- | --- |
| MySQL 节点 | 3 | 3 | 3 | 3 |
| Router 节点 | 2 独立节点 | 2 独立节点，可扩 3 | 示例可与 MySQL 同机 | 多种场景片段 |
| HAProxy 节点 | 2 独立节点 | 2 独立节点，可扩 3 | 示例可与 MySQL 同机 | 2 节点示例 |
| 适合生产候选拓扑参考 | 是 | 可作为参考 | 不推荐默认使用 | 不推荐直接使用 |
| 适合学习结构 | 可以 | 最清晰 | 可以 | 适合研究 Router 方案 |
| 是否允许写入真实环境数据 | 否 | 否 | 否 | 否 |

## 验证命令

修改 inventory 后，至少运行：

```bash
./.venv/bin/ansible-inventory -i inventory/hosts.local.yml --list >/tmp/inventory-local.json
./.venv/bin/ansible-playbook -i inventory/hosts.local.yml playbooks/site.yml \
  --syntax-check --ask-vault-pass -e @inventory/vault.local.yml
./scripts/deploy_dedicated_routers.sh --check-prereq \
  -i inventory/hosts.local.yml \
  --ask-vault-pass -e @inventory/vault.local.yml
```

仓库 CI 会另外校验已跟踪的脱敏模板；真实环境命令只指向 `hosts.local.yml`。

## 不要做什么

- 不要把历史 `group_vars/all-*.yml` 复制覆盖成当前 `all.yml`。
- 不要新增一份新的运行时 `group_vars/all-xxx.yml`。
- 不要在 inventory 中偷偷定义一套与 `group_vars/all.yml` 冲突的运行参数。
- 不要编辑 tracked inventory 来部署真实环境。
- 不要把真实 IP、密码、私钥、Vault 口令或云厂商密钥提交到仓库。
- 不要关闭 SSH host key 校验；fingerprint 变化时先查明原因。
- 不要仅凭 syntax-check 宣称生产就绪；真实环境部署、故障演练、恢复演练仍需单独执行。
