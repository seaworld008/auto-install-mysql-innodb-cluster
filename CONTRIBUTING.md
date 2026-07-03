# Contributing

感谢你愿意参与改进这个项目。本仓库面向 MySQL InnoDB Cluster 自动化部署与运维，变更应尽量保持可审计、可回滚、可验证。

## 提交 Issue

提交问题前请尽量确认：

- 使用的分支或 Release 版本。
- 目标系统版本，例如 Ubuntu、Rocky、AlmaLinux、RHEL。
- MySQL 版本线，例如 `8.0` 或 `8.4`。
- 使用的 inventory 文件和主入口命令。
- 失败日志、Ansible 报错、目标主机状态。
- 是否修改过 `inventory/group_vars/all.yml`。

涉及密码、IP 白名单、内网域名、业务表名或其他敏感信息时，请先脱敏。

## 提交 PR

推荐流程：

```bash
git checkout -b docs/improve-readme
# 修改文件
git diff --check
bash -n deploy.sh validate_deployment.sh scripts/*.sh
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --syntax-check
ansible-playbook -i inventory/hosts-ha-reference.yml playbooks/site.yml --syntax-check
ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/site.yml --syntax-check
```

如果只修改文档，请至少运行：

```bash
git diff --check
```

## 分支命名建议

- `docs/<topic>`
- `fix/<topic>`
- `feat/<topic>`
- `chore/<topic>`
- `ci/<topic>`

## Commit Message

建议使用简洁的 Conventional Commits 风格：

- `docs: update quick start`
- `fix: correct inventory validation`
- `feat: add backup option`
- `ci: strengthen ansible validation`
- `chore: refresh examples`

## Code Style

- Shell 脚本使用 `set -euo pipefail`，除非有明确原因。
- 新增破坏性操作必须显式确认，不要默认删除数据。
- 新增配置优先进入 `inventory/group_vars/all.yml` 的结构化变量。
- 不新增平行部署主线，优先扩展 `scripts/deploy_dedicated_routers.sh`。
- 文档中的命令必须能从仓库真实文件推导，不写无法验证的入口。

## 测试要求

变更类型不同，检查强度也不同：

- 文档变更：`git diff --check`。
- Shell 变更：`bash -n deploy.sh validate_deployment.sh scripts/*.sh`。
- Ansible 变更：至少运行主要 inventory 的 `--syntax-check`。
- 配置或 playbook 行为变更：同步 README、部署指南、相关 runbook。
- 备份、缩容、回滚类变更：请说明是否做过隔离环境验证。

## 安全

不要在 Issue、PR、commit 或示例文件中提交真实密码、密钥、Token、私有域名或可识别的生产环境信息。安全问题请先参考 [SECURITY.md](SECURITY.md)。
