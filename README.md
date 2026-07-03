# MySQL InnoDB Cluster 自动化部署

[![Quality Gate](https://img.shields.io/github/actions/workflow/status/seaworld008/auto-install-mysql-innodb-cluster/ansible-ci.yml?branch=main&label=quality%20gate&logo=githubactions&logoColor=white&style=for-the-badge)](https://github.com/seaworld008/auto-install-mysql-innodb-cluster/actions/workflows/ansible-ci.yml)
[![Release](https://img.shields.io/github/v/release/seaworld008/auto-install-mysql-innodb-cluster?label=release&style=for-the-badge)](https://github.com/seaworld008/auto-install-mysql-innodb-cluster/releases)
[![MIT License](https://img.shields.io/badge/license-MIT-2E8B57?style=for-the-badge)](LICENSE)
[![Ansible](https://img.shields.io/badge/automation-Ansible-EE0000?logo=ansible&logoColor=white&style=for-the-badge)](collections/requirements.yml)
[![MySQL](https://img.shields.io/badge/MySQL-8.4%20LTS%20%7C%208.0-4479A1?logo=mysql&logoColor=white&style=for-the-badge)](inventory/group_vars/all.yml)
[![InnoDB Cluster](https://img.shields.io/badge/InnoDB%20Cluster-Group%20Replication-005C84?logo=mysql&logoColor=white&style=for-the-badge)](playbooks/configure-cluster.yml)
[![MySQL Router](https://img.shields.io/badge/MySQL%20Router-R%2FW%20Split-0F6CBD?style=for-the-badge)](playbooks/install-router.yml)
[![HA Entry](https://img.shields.io/badge/HAProxy%20%2B%20Keepalived-HA%20Entry-106DA9?style=for-the-badge)](docs/DEPLOYMENT_HA_BLUEPRINT_ZH.md)
[![Operations](https://img.shields.io/badge/Operations-Scale%20%7C%20Backup%20%7C%20Rolling%20Config-6A5ACD?style=for-the-badge)](DEPLOYMENT_COMPLETE_GUIDE.md)

面向运维和平台团队的 MySQL InnoDB Cluster 自动化部署与运维方案，基于 Ansible 编排 MySQL Server、MySQL Router、HAProxy、Keepalived、扩缩容、滚动配置应用和可选备份流程。

> 当前仓库以中文文档为主，适合需要快速落地 MySQL 高可用自动化主线的中文 DevOps、DBA、SRE 和后端团队。英文摘要见文末。

## 快速导航

- [Quick Start](#quick-start)
- [English Summary](README_EN.md)
- [部署指南](DEPLOYMENT_COMPLETE_GUIDE.md)
- [部署前检查清单](PRE_DEPLOYMENT_CHECKLIST.md)
- [备份与恢复指南](docs/BACKUP_AND_RESTORE_GUIDE.md)
- [高可用部署蓝图](docs/DEPLOYMENT_HA_BLUEPRINT_ZH.md)
- [变量参考](docs/VARIABLE_REFERENCE.md)
- [架构图与证据留存](docs/ARCHITECTURE_AND_EVIDENCE.md)
- [文档站点入口](docs/index.md)
- [故障排查](TROUBLESHOOTING.md)
- [Release](https://github.com/seaworld008/auto-install-mysql-innodb-cluster/releases)
- [Issues](https://github.com/seaworld008/auto-install-mysql-innodb-cluster/issues)

## 项目定位

这个项目不是单次执行的安装脚本集合，而是一条可持续维护的 MySQL InnoDB Cluster 自动化主线。它把数据库层、路由层和入口层的常见部署动作收敛到同一套 Ansible inventory、group vars、playbooks 和入口脚本中，方便团队在后续扩容、缩容、配置变更和备份时继续复用。

核心目标：

- 用 Ansible 自动化部署 MySQL InnoDB Cluster。
- 通过 MySQL Router、HAProxy 和 Keepalived 提供分层接入能力。
- 支持显式读写端口、显式只读端口和单端口自动读写分离入口。
- 将扩容、缩容、滚动配置应用、内核优化和可选备份纳入统一入口。
- 让仓库成为可审计、可协作、可继续演进的运维资产。

## 适合场景

- 从零部署 3 节点 MySQL InnoDB Cluster。
- 为 MySQL Cluster 增加独立 MySQL Router 层。
- 通过 HAProxy + Keepalived 提供统一 VIP 入口。
- 将 MySQL 运维操作标准化为 Ansible playbook。
- 在测试、预生产或生产候选环境中验证 MySQL 8.0 / 8.4 高可用拓扑。
- 作为企业内部数据库自动化方案的起点进行二次定制。

不建议直接用于以下情况：

- 没有测试环境验证，直接对现网数据库执行首次部署。
- 未替换默认占位密码和示例 IP。
- 需要一键恢复覆盖现网数据的场景。本仓库提供备份自动化和恢复 runbook，恢复仍建议人工确认后执行。
- 需要已经验证的性能承诺或 SLA。本仓库提供自动化配置与静态校验，不替代真实压测、故障演练和容量评估。

## 核心能力

| 能力 | 当前支持情况 | 入口 |
| --- | --- | --- |
| MySQL Server 安装 | 支持 | `playbooks/install-mysql.yml` |
| InnoDB Cluster 配置 | 支持 | `playbooks/configure-cluster.yml` |
| MySQL Router 部署 | 支持 | `playbooks/install-router.yml` |
| HAProxy 部署 | 支持 | `playbooks/install-haproxy.yml` |
| Keepalived VIP | 支持 | `playbooks/install-keepalived.yml` |
| 单端口自动读写分离 | 支持 | HAProxy `3309`，Router `6450` |
| 显式读写 / 只读入口 | 支持 | HAProxy `3307/3308`，Router `6446/6447` |
| MySQL 扩容 / 缩容 | 支持 | `--scale-mysql-add` / `--scale-mysql-remove` |
| Router / HAProxy 缩容 | 支持 | `--shrink-router` / `--shrink-lb` |
| 滚动应用配置 | 支持 | `--apply-config` |
| 内核优化 | 支持 | `--kernel-optimize-only` |
| 逻辑备份 | 支持，可选 | `backup_config.method: logical` |
| XtraBackup 物理备份 | 支持，可选 | `backup_config.method: xtrabackup` |
| 自动恢复 | 不做一键覆盖 | 参考 `docs/BACKUP_AND_RESTORE_GUIDE.md` |

## 默认拓扑

默认高可用基线由 `inventory/group_vars/all.yml` 和预检查 playbook 控制：

| 层级 | 默认建议 | 说明 |
| --- | --- | --- |
| MySQL InnoDB Cluster | 3 节点 | `mysql_primary` + `mysql_secondary` |
| MySQL Router | 2 节点起 | 推荐独立部署，降低与数据库层的故障耦合 |
| HAProxy + Keepalived | 2 节点起 | 对应用提供统一 VIP / 四层入口 |
| MySQL 版本线 | `8.4` 默认，兼容 `8.0` | 由 `mysql_release_line` 控制 |
| 默认容量模型 | 8C32G MySQL + 4C8G Router | 作为仓库内置配置基线，不等同于压测结果 |

推荐链路：

```text
Application
  -> HAProxy VIP
  -> MySQL Router cluster
  -> MySQL InnoDB Cluster
```

## 端口矩阵

| 端口 | 所在层 | 类型 | 说明 |
| --- | --- | --- | --- |
| `3309` | HAProxy VIP | 自动读写分离 | 推荐给大多数应用评估的默认入口 |
| `3307` | HAProxy VIP | 强制读写 | DDL、批处理、强一致写入 |
| `3308` | HAProxy VIP | 强制只读 | 报表、查询服务、只读任务 |
| `6450` | MySQL Router | 自动读写分离 | 绕过 HAProxy 直连 Router 时使用 |
| `6446` | MySQL Router | 强制读写 | 运维直连或应急接入 |
| `6447` | MySQL Router | 强制只读 | 只读分析或排查 |
| `8404` | HAProxy | 监控 | HAProxy stats 页面 |

## Quick Start

### 1. 克隆仓库

```bash
git clone https://github.com/seaworld008/auto-install-mysql-innodb-cluster.git
cd auto-install-mysql-innodb-cluster
```

### 2. 安装本地依赖

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements.txt
ansible-galaxy collection install -r collections/requirements.yml
```

### 3. 修改 inventory 和主配置

```bash
vim inventory/hosts-with-dedicated-routers.yml
vim inventory/group_vars/all.yml
```

也可以使用 HA inventory 向导生成推荐拓扑：

```bash
./scripts/setup-servers.sh inventory/hosts-with-dedicated-routers.yml
```

至少需要确认：

- `ansible_host`、`ansible_user`、`ansible_ssh_pass` 或 SSH key 配置。
- `mysql_root_password`、`mysql_cluster_password`、`mysql_replication_password` 已替换为真实值。
- `keepalived_vip` 是当前内网可用且未被占用的 VIP。
- `mysql_release_line` 符合目标版本线，当前支持 `8.0` 和 `8.4`。
- 目标主机数量满足 `mysql_ha_min_nodes`、`router_ha_min_nodes`、`haproxy_ha_min_nodes`。

更安全的生产方式是使用 Ansible Vault 或外部 Secret 管理真实密码。示例见 `examples/production-inventory.yml` 和 `examples/vault-secrets.yml`。

### 4. 执行前置检查

```bash
./scripts/deploy_dedicated_routers.sh --check-prereq -i inventory/hosts-with-dedicated-routers.yml
```

### 5. 执行完整部署

```bash
./scripts/deploy_dedicated_routers.sh --production-ready -i inventory/hosts-with-dedicated-routers.yml
```

### 6. 查看状态

```bash
./scripts/deploy_dedicated_routers.sh --status -i inventory/hosts-with-dedicated-routers.yml
```

## 常用操作

```bash
# 仅部署 MySQL Cluster
./scripts/deploy_dedicated_routers.sh --mysql-only -i inventory/hosts-with-dedicated-routers.yml

# 仅部署或重配 MySQL Router
./scripts/deploy_dedicated_routers.sh --install-routers -i inventory/hosts-with-dedicated-routers.yml

# 仅部署或重配 HAProxy + Keepalived
./scripts/deploy_dedicated_routers.sh --configure-lb -i inventory/hosts-with-dedicated-routers.yml

# 修改主配置后滚动应用
./scripts/deploy_dedicated_routers.sh --apply-config -i inventory/hosts-with-dedicated-routers.yml

# 仅执行内核优化
./scripts/deploy_dedicated_routers.sh --kernel-optimize-only -i inventory/hosts-with-dedicated-routers.yml

# MySQL 扩容，目标主机需先加入 inventory
./scripts/deploy_dedicated_routers.sh --scale-mysql-add --limit mysql-node4 -i inventory/hosts-with-dedicated-routers.yml

# MySQL 缩容，缩容当前主节点时建议指定新主节点
./scripts/deploy_dedicated_routers.sh --scale-mysql-remove --target mysql-node3 --new-primary mysql-node2 -i inventory/hosts-with-dedicated-routers.yml

# Router / HAProxy 缩容
./scripts/deploy_dedicated_routers.sh --shrink-router --limit mysql-router-2 -i inventory/hosts-with-dedicated-routers.yml
./scripts/deploy_dedicated_routers.sh --shrink-lb --limit haproxy-2 -i inventory/hosts-with-dedicated-routers.yml

# 可选备份，需先启用 backup_config.enabled
./scripts/deploy_dedicated_routers.sh --backup -i inventory/hosts-with-dedicated-routers.yml
```

## 配置说明

主要配置入口：

| 文件 | 用途 |
| --- | --- |
| `inventory/group_vars/all.yml` | 当前运行时主配置，仓库的单一真相源 |
| `inventory/hosts-with-dedicated-routers.yml` | 推荐的独立 Router + HAProxy inventory 示例 |
| `inventory/hosts-ha-reference.yml` | 高可用拓扑参考 inventory |
| `collections/requirements.yml` | Ansible collections 依赖 |
| `ansible.cfg` | Ansible 默认配置 |

关键变量：

| 变量 | 默认值 | 是否必改 | 说明 |
| --- | --- | --- | --- |
| `mysql_release_line` | `8.4` | 视情况 | 支持 `8.0` / `8.4` |
| `mysql_root_password` | `CHANGE_ME_ROOT_PASSWORD` | 是 | root 初始密码 |
| `mysql_cluster_password` | `CHANGE_ME_CLUSTER_PASSWORD` | 是 | cluster admin 密码 |
| `mysql_replication_password` | `CHANGE_ME_REPLICATION_PASSWORD` | 是 | 复制用户密码 |
| `mysql_hardware_profile` | `optimized_8c32g` | 视情况 | 选择内置容量配置 |
| `keepalived_vip` | `192.168.1.100` | 是 | HAProxy 入口 VIP |
| `backup_config.enabled` | `false` | 视情况 | 备份默认关闭 |
| `backup_config.method` | `logical` | 视情况 | 支持 `logical` / `xtrabackup` |

## 项目结构

```text
.
├── README.md
├── QUICK_START.md
├── DEPLOYMENT_COMPLETE_GUIDE.md
├── PRE_DEPLOYMENT_CHECKLIST.md
├── TROUBLESHOOTING.md
├── ansible.cfg
├── collections/
│   └── requirements.yml
├── docs/
│   ├── BACKUP_AND_RESTORE_GUIDE.md
│   ├── DEPLOYMENT_HA_BLUEPRINT_ZH.md
│   ├── MYSQL_KERNEL_BEST_PRACTICES.md
│   └── ...
├── examples/
├── inventory/
│   ├── group_vars/all.yml
│   └── hosts-*.yml
├── playbooks/
├── roles/
├── scripts/
│   ├── deploy_dedicated_routers.sh
│   ├── config_manager.sh
│   └── ...
└── .github/workflows/ansible-ci.yml
```

更多说明见 [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)。

## 技术栈

- 自动化：Ansible、Ansible Collections。
- 数据库：MySQL InnoDB Cluster，默认 MySQL 8.4 LTS，兼容 MySQL 8.0。
- 路由层：MySQL Router。
- 入口层：HAProxy、Keepalived。
- 备份：MySQL Shell Dump、Percona XtraBackup。
- 脚本：Bash、PowerShell 验证脚本。
- CI：GitHub Actions，覆盖 Ansible syntax check、inventory 校验和静态守卫。

## 本地检查

```bash
# Shell 语法检查
bash -n deploy.sh validate_deployment.sh scripts/*.sh

# Ansible 语法检查
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --syntax-check
ansible-playbook -i inventory/hosts-ha-reference.yml playbooks/site.yml --syntax-check
ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/site.yml --syntax-check

# Inventory 校验
ansible-inventory -i inventory/hosts.yml --list >/tmp/inventory-hosts.json
ansible-inventory -i inventory/hosts-ha-reference.yml --list >/tmp/inventory-ha.json
ansible-inventory -i inventory/hosts-with-dedicated-routers.yml --list >/tmp/inventory-dedicated.json

# Diff 空白检查
git diff --check

# 可选文档质量检查（advisory）
npx --yes markdownlint-cli2
python -m pip install yamllint
yamllint .
```

## 文档

- [Quick Start](QUICK_START.md)
- [完整部署指南](DEPLOYMENT_COMPLETE_GUIDE.md)
- [部署前检查清单](PRE_DEPLOYMENT_CHECKLIST.md)
- [高可用部署蓝图](docs/DEPLOYMENT_HA_BLUEPRINT_ZH.md)
- [架构图与证据留存指南](docs/ARCHITECTURE_AND_EVIDENCE.md)
- [变量参考与配置示例](docs/VARIABLE_REFERENCE.md)
- [备份与恢复指南](docs/BACKUP_AND_RESTORE_GUIDE.md)
- [Staging 验证记录模板](docs/templates/staging-validation-record.md)
- [故障演练记录模板](docs/templates/failover-drill-record.md)
- [隔离环境恢复演练模板](docs/templates/restore-drill-record.md)
- [MySQL 内核优化最佳实践](docs/MYSQL_KERNEL_BEST_PRACTICES.md)
- [MySQL 8.0 / 8.4 交叉验证](docs/MYSQL80_CLUSTER_CROSS_VALIDATION.md)
- [GitHub Pages 文档站点入口](docs/index.md)
- [AI 维护说明](docs/AI_MAINTAINER_GUIDE.md)
- [故障排查](TROUBLESHOOTING.md)
- [English README](README_EN.md)

## 安全说明

- 不要把真实 SSH 密码、MySQL 密码、Vault 密钥、云厂商密钥提交到仓库。
- `inventory/group_vars/all.yml` 中的 `CHANGE_ME_*` 必须在部署前替换。
- 建议生产环境使用 Ansible Vault、SSH key、CI/CD Secret 或专用 Secret Manager。
- 公开披露安全问题前，请优先通过 GitHub Security Advisories 或维护者私下渠道报告。

## Roadmap

已完成的文档与协作增强：

- 可复用的 staging 验证记录、故障演练和隔离恢复演练模板。
- 架构图、端口视图、CLI 证据与截图留存规范。
- 英文 README，便于全球开发者检索和初步评估。
- 更细的变量参考表和配置示例。
- 可选 Markdown lint / YAML lint advisory workflow。
- GitHub Pages 文档站点入口与发布工作流。

仍需要真实环境补充的内容：

- 脱敏后的部署截图、HAProxy stats 截图和 CLI 运行截图。
- staging 故障演练记录。
- 隔离环境恢复演练记录。
- 压测、容量评估和生产级观测数据。

## FAQ

### 是否可以直接用于生产？

仓库面向生产候选拓扑设计，但静态检查和 Ansible syntax check 不等于真实生产验证。建议先在测试或预生产环境完成部署、压测、故障转移、备份恢复演练，再进入生产。

### 是否支持 Docker？

当前主线是 Ansible 远程部署，不提供 Docker Compose 一键运行 MySQL Cluster。后续可以考虑增加用于学习和演示的容器化实验环境。

### 默认密码可以直接用吗？

不可以。默认值是 `CHANGE_ME_*` 占位符，预检查会阻止继续部署。请使用真实强密码，生产环境建议使用 Ansible Vault 或外部 Secret 管理。

### 如何选择 MySQL 8.0 还是 8.4？

默认 `mysql_release_line: "8.4"`。如果你的环境仍要求 MySQL 8.0，可以改为 `8.0`，并在测试环境验证安装源、Router、备份工具和应用兼容性。

### 备份是否默认开启？

默认关闭。启用前请修改 `backup_config.enabled: true`，并确认 `method`、`type`、目标目录和权限。

### CI 能证明部署一定成功吗？

不能。CI 当前用于静态质量门：Ansible 语法、inventory 解析和部分过时参数守卫。真实部署仍依赖目标主机、网络、系统版本、权限、MySQL 源和安全策略。

## 贡献

欢迎通过 Issue 和 Pull Request 参与改进。提交前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)，并尽量运行本地检查命令。

如果这个项目对你有帮助，欢迎 Star 支持，也欢迎把真实问题、部署反馈和改进建议提交到 Issues。

## License

本仓库使用 [MIT License](LICENSE)。如你计划在商业或企业场景中复用，请在引入前自行确认许可证与组织合规要求。

## English Summary

`auto-install-mysql-innodb-cluster` is an Ansible-based automation project for deploying and operating MySQL InnoDB Cluster with MySQL Router, HAProxy, Keepalived, scaling workflows, rolling configuration updates, kernel tuning, and optional logical or physical backups. The documentation is currently Chinese-first, with MySQL 8.4 LTS as the default release line and MySQL 8.0 compatibility retained.

For a fuller English entrypoint, see [README_EN.md](README_EN.md).
