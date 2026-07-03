# Inventory 使用说明

本目录放 Ansible inventory 和全局运行时变量。第一次接手时，请先记住一条原则：

**主机拓扑看 `hosts-*.yml`，运行时参数看 `group_vars/all.yml`。**

如果某个 inventory 文件里也写了 Router、HAProxy、端口或性能参数，而它和 `group_vars/all.yml` 冲突，以 `group_vars/all.yml` 作为当前运行时真相源。

首次部署、dry-run、重复执行和已部署后改配置的完整流程见 `docs/runbooks/OPERATOR_GUIDE.md`。

## 推荐选择

| 文件 | 推荐程度 | 适用场景 | 说明 |
| --- | --- | --- | --- |
| `hosts-with-dedicated-routers.yml` | 首选 | 新部署、生产候选、完整 HA 拓扑 | 3 台 MySQL + 2 台独立 Router + 2 台 HAProxy/Keepalived。主入口脚本默认使用这份 inventory。 |
| `hosts-ha-reference.yml` | 推荐参考 | 精简 HA 示例、文档演示、CI syntax-check | 结构更短，表达最小 HA 拓扑。适合看清分组关系，也可作为 staging 示例。 |
| `hosts.yml` | 基础示例 | 本地理解、基础语法检查、资源受限测试 | Router 和 HAProxy 示例可与 MySQL 同机，不是生产默认拓扑。 |
| `hosts-recommended-router.yml` | 场景参考 | 对比 Router 部署方式 | 包含独立 Router、应用侧 Router、容器化等片段。不要把它当作当前主部署入口直接照搬。 |
| `group_vars/all.yml` | 必改 | 所有部署和运维 | 当前唯一运行时主配置，包含版本、密码占位符、profile、HA、备份、Router、HAProxy、Keepalived 等参数。 |

## 日常怎么用

### 生产候选或标准 HA 部署

优先使用：

```bash
vim inventory/hosts-with-dedicated-routers.yml
vim inventory/group_vars/all.yml

./scripts/deploy_dedicated_routers.sh --check-prereq -i inventory/hosts-with-dedicated-routers.yml
./scripts/deploy_dedicated_routers.sh --production-ready -i inventory/hosts-with-dedicated-routers.yml
```

这也是 README、Quick Start 和主部署脚本默认推荐的路径。

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

- `ansible_host`
- `ansible_user`
- SSH 密码或 SSH key 配置
- `mysql_server_id` 唯一
- `keepalived_vip` 是未被占用的内网 VIP
- `mysql_root_password`
- `mysql_cluster_password`
- `mysql_replication_password`
- `mysql_release_line` 符合目标版本线

生产环境建议使用 Ansible Vault、SSH key、CI/CD Secret 或专用 Secret Manager，不要把真实密码长期明文提交到仓库。

## 文件之间的主要区别

| 对比项 | `hosts-with-dedicated-routers.yml` | `hosts-ha-reference.yml` | `hosts.yml` | `hosts-recommended-router.yml` |
| --- | --- | --- | --- | --- |
| MySQL 节点 | 3 | 3 | 3 | 3 |
| Router 节点 | 2 独立节点 | 2 独立节点，可扩 3 | 示例可与 MySQL 同机 | 多种场景片段 |
| HAProxy 节点 | 2 独立节点 | 2 独立节点，可扩 3 | 示例可与 MySQL 同机 | 2 节点示例 |
| 适合生产候选 | 是 | 可作为参考 | 不推荐默认使用 | 不推荐直接使用 |
| 适合学习结构 | 可以 | 最清晰 | 可以 | 适合研究 Router 方案 |
| 是否主入口默认 | 是 | 否 | 否 | 否 |

## 验证命令

修改 inventory 后，至少运行：

```bash
./.venv/bin/ansible-inventory -i inventory/hosts-with-dedicated-routers.yml --list >/tmp/inventory-dedicated.json
./.venv/bin/ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/site.yml --syntax-check
./scripts/deploy_dedicated_routers.sh --check-prereq -i inventory/hosts-with-dedicated-routers.yml
```

如果你改的是 `hosts-ha-reference.yml` 或 `hosts.yml`，也要分别跑对应的 `ansible-inventory --list` 和 `ansible-playbook ... --syntax-check`。

## 不要做什么

- 不要把历史 `group_vars/all-*.yml` 复制覆盖成当前 `all.yml`。
- 不要新增一份新的运行时 `group_vars/all-xxx.yml`。
- 不要在 inventory 中偷偷定义一套与 `group_vars/all.yml` 冲突的运行参数。
- 不要把真实密码、私钥、Vault 密钥或云厂商密钥提交到仓库。
- 不要仅凭 syntax-check 宣称生产就绪；真实环境部署、故障演练、恢复演练仍需单独执行。
