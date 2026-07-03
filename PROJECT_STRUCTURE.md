# 项目结构总览

本仓库维护一条统一的 MySQL InnoDB Cluster 自动化部署与运维主线。当前运行时真相源是 `inventory/group_vars/all.yml`，推荐入口是 `scripts/deploy_dedicated_routers.sh`。

## 顶层结构

```text
.
├── AGENTS.md
├── CHANGELOG.md
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── DEPLOYMENT_COMPLETE_GUIDE.md
├── LICENSE
├── PRE_DEPLOYMENT_CHECKLIST.md
├── PROJECT_STRUCTURE.md
├── QUICK_START.md
├── README.md
├── SECURITY.md
├── TROUBLESHOOTING.md
├── ansible.cfg
├── collections/
├── docs/
├── examples/
├── inventory/
├── playbooks/
├── roles/
├── scripts/
├── validate_deployment.ps1
└── validate_deployment.sh
```

## 核心入口

| 路径 | 说明 |
| --- | --- |
| `scripts/deploy_dedicated_routers.sh` | 当前推荐主入口，统一执行部署、检查、扩缩容、配置应用和备份 |
| `deploy.sh` | 兼容旧操作习惯的包装入口，内部转发到主入口 |
| `inventory/group_vars/all.yml` | 当前唯一运行时主配置 |
| `.github/workflows/ansible-ci.yml` | GitHub Actions 静态质量门 |

## 目录说明

### `inventory/`

Ansible inventory 与全局变量。

- `inventory/group_vars/all.yml`：主配置。
- `inventory/hosts-with-dedicated-routers.yml`：推荐的独立 Router + HAProxy 拓扑示例。
- `inventory/hosts-ha-reference.yml`：高可用参考拓扑。
- `inventory/hosts.yml`：基础示例拓扑。
- `inventory/group_vars/all-8c32g-optimized.yml`、`inventory/group_vars/all-original-10k-config.yml`：历史快照，不是运行时真相源。

### `playbooks/`

Ansible playbooks。

- `site.yml`：完整部署入口。
- `preflight-ha.yml`：高可用拓扑与关键参数预检查。
- `install-mysql.yml`：安装 MySQL Server。
- `configure-cluster.yml`：配置 InnoDB Cluster。
- `install-router.yml`：安装 MySQL Router。
- `install-haproxy.yml`：安装 HAProxy。
- `install-keepalived.yml`：安装 Keepalived。
- `apply-config.yml`：滚动应用当前主配置。
- `backup.yml`：可选逻辑 / 物理备份。
- `scale-*.yml`、`shrink-*.yml`：扩容和缩容流程。

### `roles/`

Ansible 角色模板。

- `roles/mysql-server/templates/my.cnf.j2`
- `roles/mysql-router/templates/mysqlrouter.service.j2`
- `roles/haproxy/templates/haproxy.cfg.j2`
- `roles/keepalived/templates/keepalived.conf.j2`

### `scripts/`

运维脚本和主入口。

- `deploy_dedicated_routers.sh`：统一部署和运维入口。
- `config_manager.sh`：切换 `mysql_hardware_profile`。
- `optimize_mysql_kernel_stable.sh`：单机内核优化辅助脚本。
- `health-check-ha.sh`：高可用健康检查。
- `backup.sh`：备份辅助脚本。
- `scale-*.sh`、`shrink-*.sh`：扩缩容辅助入口。

### `docs/`

专题文档。

- `docs/BACKUP_AND_RESTORE_GUIDE.md`
- `docs/DEPLOYMENT_HA_BLUEPRINT_ZH.md`
- `docs/MYSQL_KERNEL_BEST_PRACTICES.md`
- `docs/MYSQL80_CLUSTER_CROSS_VALIDATION.md`
- `docs/ROUTER_DEPLOYMENT_COMPLETE.md`
- `docs/AI_MAINTAINER_GUIDE.md`

### `examples/`

示例配置。

- `examples/production-inventory.yml`：生产 inventory 示例。
- `examples/vault-secrets.yml`：Ansible Vault 变量示例，提交前必须加密或替换。
- `examples/hardware_profiles.yml`：硬件配置参考。
- `examples/router-deployment-options.yml`：Router 接入方式参考。

## 推荐工作流

```bash
# 1. 安装依赖
pip install -r requirements.txt
ansible-galaxy collection install -r collections/requirements.yml

# 2. 修改 inventory 和主配置
vim inventory/hosts-with-dedicated-routers.yml
vim inventory/group_vars/all.yml

# 3. 前置检查
./scripts/deploy_dedicated_routers.sh --check-prereq -i inventory/hosts-with-dedicated-routers.yml

# 4. 完整部署
./scripts/deploy_dedicated_routers.sh --production-ready -i inventory/hosts-with-dedicated-routers.yml

# 5. 查看状态
./scripts/deploy_dedicated_routers.sh --status -i inventory/hosts-with-dedicated-routers.yml
```

## 维护原则

- 不新增平行部署主线。
- 不复制新的运行时主配置文件。
- 新配置优先进入 `inventory/group_vars/all.yml` 的结构化变量。
- 行为变更需要同步 README、部署指南和相关 runbook。
- 发布前至少运行 shell 语法、Ansible syntax-check、inventory 校验和 `git diff --check`。
