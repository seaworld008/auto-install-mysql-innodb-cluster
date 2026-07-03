# v0.2.1 - 仓库展示与开源协作完善

> 草案。请在维护者确认许可证、审阅安全相关配置变更、提交并推送分支后，再基于本文件创建 GitHub Release。

## 版本概览

本次建议版本聚焦仓库专业化、开源协作文件补齐、README 可读性和安全默认值收敛。不新增新的部署主线，也不宣称超出现有 Ansible 自动化能力之外的运行时功能。

## 重点变化

- 重构 README，补齐项目定位、Quick Start、配置说明、常用操作、本地检查、FAQ 和英文摘要。
- 新增开源协作文件：
  - `LICENSE`
  - `CONTRIBUTING.md`
  - `CODE_OF_CONDUCT.md`
  - `SECURITY.md`
- 新增 GitHub Issue Templates 和 Pull Request Template。
- 新增 `.gitignore` 与 `.editorconfig`。
- 更新 `PROJECT_STRUCTURE.md`，使其匹配当前仓库真实结构。
- 将看起来像真实密码的默认值替换为明确占位符，降低公开仓库误用风险。
- 在 GitHub Actions 中增加 shell 语法检查。
- 将 `setup-servers.sh` 升级为 3 MySQL + 2 Router + 2 HAProxy 的 HA inventory 向导。
- 将常用辅助脚本收敛到 `scripts/deploy_dedicated_routers.sh` 主入口。
- 修复 health/status 路径读取 inventory 变量时的 JSON stdin 问题。
- 修复 `validate_deployment.sh` 在 `set -e` 下提前退出的问题。
- 迁移到 `ansible.mysql.mysql_user`，避免新版 collection 弃用警告。
- 明确 `--skip-kernel-optimization` 与 `--full-deploy` 的执行路径，减少重复或不确定行为。

## 使用方式摘要

```bash
git clone https://github.com/seaworld008/auto-install-mysql-innodb-cluster.git
cd auto-install-mysql-innodb-cluster

python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
ansible-galaxy collection install -r collections/requirements.yml

vim inventory/hosts-with-dedicated-routers.yml
vim inventory/group_vars/all.yml

./scripts/deploy_dedicated_routers.sh --check-prereq -i inventory/hosts-with-dedicated-routers.yml
./scripts/deploy_dedicated_routers.sh --production-ready -i inventory/hosts-with-dedicated-routers.yml
```

## 已知限制

- 真实部署、故障转移、备份、恢复和性能表现仍需在目标环境验证。
- 当前文档仍以中文为主。
- MIT License 已按维护者确认补齐。
- 真实部署仍需要替换 `CHANGE_ME_*` 密码和示例 inventory 后执行 preflight。

## 建议版本号

建议使用 `v0.2.1`。理由：这是基于 `v0.2.0` 的文档、仓库治理、安全默认值和 CI 小版本维护更新，没有引入新的运行时功能集。

## 发布前检查

- 确认 `LICENSE` 已随本次变更提交并被 GitHub 正确识别。
- 审阅所有密码占位符变更。
- 运行本地静态检查。
- 提交并推送分支。
- 基于本草案创建 GitHub Release。
