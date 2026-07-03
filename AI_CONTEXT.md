# AI Agent Repository Context

这份文件写给所有接手本仓库的 AI agent、自动化助手和未来维护者。目标是让 agent 在修改前快速理解：

- 这个仓库是做什么的
- 哪些文件是单一真相源
- 如何安全修改、验证和更新文档
- 哪些结论不能仅凭静态检查宣称

如果你只能先读一份面向 agent 的上下文，先读本文；如果要执行具体改动，再读 `AGENTS.md` 和相关专题文档。

## 1. Repository Mission

本仓库维护一条统一的 MySQL InnoDB Cluster 自动化部署与运维主线，面向 DBA、SRE、平台工程和后端团队。

核心能力：

- 部署 MySQL Server 和 InnoDB Cluster
- 部署 MySQL Router
- 部署 HAProxy + Keepalived 入口层
- 支持 MySQL 扩容与缩容
- 支持 Router / HAProxy 缩容
- 支持滚动应用当前配置
- 支持可选备份流程
- 提供部署前检查、静态校验、证据留存和演练模板

仓库的维护目标不是堆更多脚本，而是把部署、运维和文档持续收敛到同一条生产候选主线。

## 2. Mental Model

推荐运行链路：

```text
Application
  -> HAProxy VIP
  -> MySQL Router cluster
  -> MySQL InnoDB Cluster
```

默认高可用基线：

- MySQL InnoDB Cluster：3 节点
- MySQL Router：2 节点起，推荐独立部署
- HAProxy + Keepalived：2 节点起，提供 VIP / 四层入口
- MySQL 版本线：默认 `8.4`，兼容 `8.0`

主要入口端口：

- HAProxy VIP 自动读写分离：`3309`
- HAProxy VIP 强制读写：`3307`
- HAProxy VIP 强制只读：`3308`
- Router 自动读写分离：`6450`
- Router 强制读写：`6446`
- Router 强制只读：`6447`

## 3. Single Sources Of Truth

运行时主配置：

- `inventory/group_vars/all.yml`

主操作入口：

- `scripts/deploy_dedicated_routers.sh`

兼容包装入口：

- `deploy.sh`

配置 profile 切换：

- `scripts/config_manager.sh`
- 只应切换 `mysql_hardware_profile`

CI 静态质量门：

- `.github/workflows/ansible-ci.yml`

主用户文档：

- `README.md`
- `README_EN.md`
- `QUICK_START.md`
- `DEPLOYMENT_COMPLETE_GUIDE.md`
- `PRE_DEPLOYMENT_CHECKLIST.md`

不要把以下历史文件当作运行时真相源：

- `inventory/group_vars/all-8c32g-optimized.yml`
- `inventory/group_vars/all-original-10k-config.yml`
- `docs/reports/`

## 4. Repository Map

```text
.
├── AI_CONTEXT.md
├── AGENTS.md
├── README.md
├── QUICK_START.md
├── DEPLOYMENT_COMPLETE_GUIDE.md
├── PRE_DEPLOYMENT_CHECKLIST.md
├── inventory/
│   ├── hosts*.yml
│   └── group_vars/all.yml
├── playbooks/
├── roles/
├── scripts/
├── docs/
│   ├── index.md
│   ├── runbooks/
│   ├── reference/
│   ├── reports/
│   ├── maintainers/
│   ├── templates/
│   └── decisions/
└── .github/workflows/
```

文档分层：

- `docs/runbooks/`：可执行运维流程，例如服务器配置、备份恢复、故障排查
- `docs/reference/`：长期参考，例如 HA 蓝图、变量参考、项目结构、架构证据
- `docs/reports/`：历史分析和容量推导，不是运行时真相源
- `docs/maintainers/`：维护者说明、发布清单、发布草稿
- `docs/templates/`：staging、故障演练、恢复演练记录模板
- `docs/decisions/`：架构决策记录

## 5. Supported Operations

所有主操作都应通过 `scripts/deploy_dedicated_routers.sh`：

```bash
./scripts/deploy_dedicated_routers.sh --production-ready
./scripts/deploy_dedicated_routers.sh --mysql-only
./scripts/deploy_dedicated_routers.sh --apply-config
./scripts/deploy_dedicated_routers.sh --scale-mysql-add
./scripts/deploy_dedicated_routers.sh --scale-mysql-remove
./scripts/deploy_dedicated_routers.sh --shrink-router
./scripts/deploy_dedicated_routers.sh --shrink-lb
./scripts/deploy_dedicated_routers.sh --backup
./scripts/deploy_dedicated_routers.sh --status
```

新增操作时优先扩展这个入口，不要新建并行 top-level workflow。

## 6. Change Rules For Agents

修改行为时，按这个顺序检查：

1. 是否需要改 `inventory/group_vars/all.yml`
2. 是否需要改 playbook、role template 或主脚本
3. 是否需要同步 README、部署指南、变量参考或 runbook
4. 是否保持幂等性
5. 是否避免破坏健康节点
6. 是否有静态验证和 Ansible syntax / inventory 验证

配置规则：

- 不要新增运行时配置副本。
- 新硬件或容量方案应进入 `mysql_config_profiles`。
- 新变量必须真正被模板、playbook、脚本或 bootstrap 命令使用。
- 如果变量只是文档里的愿望，不要把它当成已实现能力。

脚本规则：

- 不要绕过 `scripts/deploy_dedicated_routers.sh` 新建主流程。
- 兼容入口 `deploy.sh` 不应承载新能力。
- 破坏性操作必须显式，不能隐藏在普通部署流程里。

文档规则：

- 行为变更必须同步主用户文档。
- 专题说明放入对应 `docs/` 子目录。
- 历史分析可以保留在 `docs/reports/`，但要清楚标注不是运行时真相源。

## 7. Idempotency And Safety

必须保留或提升幂等性：

- 重复部署不能摧毁健康节点。
- Router 不应在未明确要求时重新 bootstrap。
- 配置应用应尽量滚动执行。
- 缩容、删除、覆盖数据等动作必须显式。
- 备份默认 opt-in，不能默认开启。
- 恢复流程应要求人工确认，不做一键覆盖生产数据。

高风险文件：

- `inventory/group_vars/all.yml`
- `playbooks/install-mysql.yml`
- `playbooks/configure-cluster.yml`
- `playbooks/install-router.yml`
- `playbooks/backup.yml`
- `roles/mysql-server/templates/my.cnf.j2`
- `roles/mysql-router/templates/mysqlrouter.service.j2`
- `roles/haproxy/templates/haproxy.cfg.j2`
- `roles/keepalived/templates/keepalived.conf.j2`
- `scripts/deploy_dedicated_routers.sh`

改这些文件时通常也要更新文档和验证说明。

## 8. Validation Checklist

声明完成前至少运行：

```bash
git diff --check
bash -n deploy.sh validate_deployment.sh scripts/*.sh
npx --yes markdownlint-cli2
./.venv/bin/yamllint .
./.venv/bin/ansible-playbook -i inventory/hosts.yml playbooks/site.yml --syntax-check
./.venv/bin/ansible-playbook -i inventory/hosts-ha-reference.yml playbooks/site.yml --syntax-check
./.venv/bin/ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/site.yml --syntax-check
./.venv/bin/ansible-inventory -i inventory/hosts.yml --list
./.venv/bin/ansible-inventory -i inventory/hosts-ha-reference.yml --list
./.venv/bin/ansible-inventory -i inventory/hosts-with-dedicated-routers.yml --list
```

如果 `.venv` 不存在，先按 README 安装依赖：

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements.txt
ansible-galaxy collection install -r collections/requirements.yml
```

注意：

- 静态验证通过只能说明语法和 inventory 解析通过。
- 不能据此宣称生产可用、故障切换已验证或备份恢复已验证。

## 9. Common Maintenance Tasks

调整 MySQL 参数：

1. 修改 `inventory/group_vars/all.yml`
2. 确认 `roles/mysql-server/templates/my.cnf.j2` 消费了该变量
3. 如需滚动应用，检查 `playbooks/apply-config.yml`
4. 更新 `docs/reference/VARIABLE_REFERENCE.md`
5. 更新 README 或部署指南中的用户可见说明
6. 跑验证

新增硬件 profile：

1. 在 `mysql_config_profiles` 下新增 profile
2. 确认 `scripts/config_manager.sh` 只切换 `mysql_hardware_profile`
3. 不新增 `all-xxx.yml` 运行配置副本
4. 更新变量参考和容量说明

新增主操作：

1. 优先扩展 `scripts/deploy_dedicated_routers.sh`
2. 新增或复用 playbook
3. 保持 destructive action 显式
4. 更新 README、部署总览、相关 runbook
5. 添加 CI 或本地验证覆盖

更新文档结构：

1. 根目录只保留主入口和项目协作文件
2. 可执行流程放 `docs/runbooks/`
3. 长期参考放 `docs/reference/`
4. 历史报告放 `docs/reports/`
5. 同步 `docs/index.md` 和 `README.md`

## 10. What Not To Claim

不要仅凭本地静态检查声称：

- 已达到完整生产可用
- 已完成真实故障切换验证
- 已完成真实备份恢复验证
- 已完成性能容量验证
- 已验证所有云厂商或所有 Linux 发行版

准确措辞：

- "Static validation passed"
- "Ansible syntax and inventory validation passed"
- "Real environment validation still pending"
- "Backup/restore drill still requires isolated environment execution"

## 11. Recommended Agent Workflow

每次接手任务时：

1. 读 `AI_CONTEXT.md`
2. 读 `AGENTS.md`
3. 如涉及部署、配置或运维入口，读 `docs/runbooks/OPERATOR_GUIDE.md`
4. 如涉及 inventory 或拓扑选择，读 `inventory/README.md`
5. 看 `git status --short --branch`
6. 找到相关单一真相源
7. 小步修改
8. 跑验证
9. 总结改动范围、未触碰内容和剩余风险

提交建议：

- 文档整理：`docs: ...`
- 行为修复：`fix: ...`
- 新能力：`feat: ...`
- 工具或 CI：`chore: ...`

PR 描述应包含：

- Summary
- Validation
- Risk / rollout notes
- Real environment validation status

## 12. Update This File

当仓库主入口、运行时真相源、文档结构、验证命令或支持操作发生变化时，必须同步更新本文。

如果本文与 `AGENTS.md` 冲突，以 `AGENTS.md` 的硬性维护约束为准；如果本文与代码实现冲突，以代码和 `inventory/group_vars/all.yml` 的实际运行行为为准，并修正文档。
