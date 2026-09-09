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
- 支持可选 MySQL Shell 逻辑备份与 Percona XtraBackup 物理备份
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

HAProxy 后端只允许指向 Router。不要恢复“HAProxy 直接连接静态 MySQL
primary”的路径；该路径会在主从切换后把写流量继续送往旧主节点。

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

`keepalived_vip` 的仓库默认值是 RFC 5737 文档地址 `192.0.2.100`，会被
preflight 主动阻断。部署时必须覆盖为目标环境已确认的合法 IPv4；例如真实私网中
可使用未冲突的 `192.168.1.100`。

## 3. Single Sources Of Truth

运行时主配置：

- `inventory/group_vars/all.yml`

主操作入口：

- `scripts/deploy_dedicated_routers.sh`

组合验证入口：

- `playbooks/validate-ha.yml`
- 顺序导入 `preflight-ha.yml` 和 `health-check-ha.yml`
- `scripts/health-check-ha.sh`、`--status` 与 `--test-connection` 使用该组合门

兼容包装入口：

- `deploy.sh`

配置 profile 切换：

- `scripts/config_manager.sh`
- 只应切换 `mysql_hardware_profile`

CI 与依赖治理：

- `.github/workflows/ansible-ci.yml`
- `.github/workflows/docs-quality.yml`
- `.github/workflows/codeql.yml`
- `.github/dependabot.yml`

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
├── tests/
├── .github/dependabot.yml
├── docs/
│   ├── index.md
│   ├── runbooks/
│   ├── reference/
│   ├── reports/
│   ├── maintainers/
│   ├── templates/
│   └── decisions/
└── .github/workflows/
    ├── ansible-ci.yml
    ├── codeql.yml
    ├── docs-quality.yml
    └── pages.yml
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
- Ansible Vault 参数必须由主入口通过 `-e`、`--ask-vault-pass` 或
  `--vault-password-file` 透传，不要创建绕过主入口的秘密加载脚本。
- 真实 inventory、Vault 文件、私钥和主机指纹文件只能放在 Git 忽略的本地文件中；
  tracked inventory 只保留脱敏示例。

文档规则：

- 行为变更必须同步主用户文档。
- 专题说明放入对应 `docs/` 子目录。
- 历史分析可以保留在 `docs/reports/`，但要清楚标注不是运行时真相源。

## 7. Idempotency And Safety

必须保留或提升幂等性：

- 重复部署不能摧毁健康节点。
- Router 不应在未明确要求时重新 bootstrap。
- InnoDB Cluster 重复执行时应识别已有成员；只有 standalone 节点才运行
  `checkInstanceConfiguration` 并加入集群，已有成员不得重复运行
  `configureInstance`，最终必须确认预期成员全部 `ONLINE`。
- 配置应用应尽量滚动执行。
- MySQL 缩容必须唯一识别目标成员和当前 primary；移除当前 primary 前必须显式切主，
  缩容后必须再次确认集群为 `OK` 且剩余成员全部 `ONLINE`。
- Router / HAProxy 缩容必须精确匹配一台主机，并满足缩容后的最小节点数。
- 缩容、删除、覆盖数据等动作必须显式。
- 备份默认 opt-in，不能默认开启。
- 恢复流程应要求人工确认，不做一键覆盖生产数据。
- 自定义 datadir 迁移必须保留中断标记和可重入 rsync；Debian / Ubuntu 同步
  AppArmor，启用 SELinux 的 RedHat 节点持久设置文件上下文并执行 `restorecon`。
- RedHat root 初始化重跑时应先用 0600 临时 option file 探测目标密码；目标密码
  已生效时跳过临时密码重置，无法探测且找不到首次临时密码时 fail closed。
- Keepalived 配置含 VRRP 口令，模板目标权限必须保持 `0600`，渲染任务保持
  `no_log: true`。
- SSH 必须严格校验主机密钥；不得加入
  `StrictHostKeyChecking=no` 或 `UserKnownHostsFile=/dev/null`。
- rsync 备份的 `known_hosts` 必须是 root 所有、不可被 group/other 写入的普通
  文件；可选私钥必须是 root 所有且权限为 `0400` 或 `0600`。
- 压缩 XtraBackup 在同一任务要求 prepare 时必须先执行 `--decompress`，再执行
  `--prepare`。
- `cluster-status.sh` 与 `failover-test.sh` 等辅助脚本不得把 MySQL 密码放入
  argv；交互时隐藏读取，自动化使用受保护环境变量，并通过 stdin 交给 mysqlsh。
- 每个独立集群必须通过 `mysql_group_replication_group_name_override`
  提供唯一 UUID，不能使用仓库占位 UUID。

高风险文件：

- `inventory/group_vars/all.yml`
- `playbooks/install-mysql.yml`
- `playbooks/configure-cluster.yml`
- `playbooks/install-router.yml`
- `playbooks/validate-ha.yml`
- `playbooks/health-check-ha.yml`
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
for script in deploy.sh validate_deployment.sh scripts/*.sh; do
  bash -n "$script" || exit 1
done
npx --yes markdownlint-cli2@0.23.2
./.venv/bin/yamllint .
./.venv/bin/python -m unittest discover tests
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
python -m pip install --requirement requirements.txt
ansible-galaxy collection install --requirements-file collections/requirements.yml
```

注意：

- 控制节点要求 Python 3.12+，且 `requirements.txt` 只安装 `ansible-core`；
  collections 由 `collections/requirements.yml` 安装。目标节点在首次 Ansible
  模块连接前必须预装 Python 3.9+，目标 PyMySQL 由可信系统仓库安装。
- 静态验证通过只能说明语法和 inventory 解析通过。
- 不能据此宣称生产可用、故障切换已验证或备份恢复已验证。
- `--status` / `--test-connection` 通过 `validate-ha.yml` 先执行 preflight，
  再执行 fail-closed 运行时健康门：每个 inventory MySQL 节点必须 `ONLINE`，
  Cluster 为 `OK` 且成员数一致，启用的 Router、HAProxy、Keepalived 及端口必须
  可用，VIP 必须恰好出现在一个 `haproxy_lb` 节点上。
- CI 使用固定 SHA 的 Actions、Python 3.12/3.13 矩阵、仓库契约测试、全部
  playbook syntax-check、PowerShell parser、三个主 inventory 解析、阻断式
  文档 lint 和 GitHub Actions CodeQL；Dependabot 每周检查 pip 与 Actions
  依赖。

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

## 文档维护原则

README 是面向使用者的功能、架构、快速使用与导航入口，不追加版本修复清单或测试日志。
版本历史进入 CHANGELOG；兼容性要求写入对应 runbook；测试过程和证据留在维护者资料。
不得通过移除首页的过程描述来宣称未执行的生产验收或隐瞒会影响使用的限制。
本地模拟入口为 `tests/lab/lab.py`，方案见 `docs/runbooks/LOCAL_SIMULATION.md`。
新建组 UUID 由 AdminAPI groupName 设置，已存在成员必须匹配配置，禁止自动热改组身份。
