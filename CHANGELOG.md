# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) 的组织方式，并尽量使用语义化版本。

> 说明：当前运行时真相源请以 `inventory/group_vars/all.yml`、`README.md` 和 `DEPLOYMENT_COMPLETE_GUIDE.md` 为准。

## [Unreleased]

### 新增

- 新增英文入口 `README_EN.md`，便于全球开发者检索和评估。
- 新增 GitHub Pages 文档站点入口与发布工作流：`docs/index.md`、`.github/workflows/pages.yml`。
- 新增架构图、端口视图和证据留存指南：`docs/ARCHITECTURE_AND_EVIDENCE.md`。
- 新增变量参考与配置示例：`docs/VARIABLE_REFERENCE.md`。
- 新增 staging 验证、故障演练和隔离恢复演练记录模板。
- 新增可选 Markdown / YAML advisory lint 工作流与配置。
- 新增开源协作文件：`LICENSE`、`CONTRIBUTING.md`、`CODE_OF_CONDUCT.md`、`SECURITY.md`。
- 新增 GitHub Issue Templates 和 Pull Request Template。
- 新增 `.gitignore` 和 `.editorconfig`，减少本地开发噪声和误提交风险。
- 新增下一次文档与仓库展示优化版本的 Release 草案。

### 变更

- 重构 `README.md`，补齐项目定位、Quick Start、配置说明、常用操作、本地检查、FAQ 和英文摘要。
- 更新 `PROJECT_STRUCTURE.md`，使其匹配当前仓库真实结构。
- 将看起来像真实密码的示例值替换为明确的 `CHANGE_ME_*` 或占位值。
- 在 GitHub Actions 中增加 shell 语法检查。
- 将旧的 `setup-servers.sh` 三机向导升级为 3 MySQL + 2 Router + 2 HAProxy 的 HA inventory 向导。
- 将辅助脚本 `apply-config.sh`、`backup.sh`、`scale-mysql.sh`、`shrink-*.sh`、`deploy-ha-stack.sh` 收敛到统一主入口。
- 将 MySQL 用户管理模块从 `community.mysql.mysql_user` 迁移到 `ansible.mysql.mysql_user`，消除新版 collection 弃用警告。
- 明确 `--skip-kernel-optimization` 的执行路径，避免依赖不确定的 tag 跳过行为。

### 安全

- 明确建议生产环境使用 Ansible Vault、SSH key、CI/CD Secret 或专用 Secret Manager。
- 降低从公开示例中复制默认样式凭据的误用风险。
- `cluster-status.sh`、`failover-test.sh` 在未显式提供集群密码时会直接阻断，避免使用占位密码发起连接。

### 修复

- 修复 `deploy_dedicated_routers.sh` 与 `health-check-ha.sh` 中 inventory 变量读取时 `python -` 与管道 stdin 冲突导致的 JSON 解析失败。
- 修复 `validate_deployment.sh` 在 `set -e` 下因后缀自增提前退出的问题。
- 修复 `--full-deploy` 重复执行入口层内核优化的问题。

## [0.2.0] - 2026-03-25

### 新增

- 统一运行时配置模型，以 `inventory/group_vars/all.yml` 作为单一真相源。
- 统一主入口：`scripts/deploy_dedicated_routers.sh`。
- 默认使用 MySQL 8.4 LTS，同时保留 MySQL 8.0 兼容。
- 新增单端口自动读写分离入口：
  - HAProxy VIP: `3309`
  - MySQL Router 直连: `6450`
- 保留显式读写和只读入口：
  - HAProxy VIP: `3307 / 3308`
  - MySQL Router 直连: `6446 / 6447`
- 新增 MySQL 扩容和缩容流程。
- 新增 Router 与 HAProxy 缩容流程。
- 新增滚动应用当前配置流程。
- 新增独立内核优化动作：`--kernel-optimize-only`。
- 新增可选备份流程：
  - MySQL Shell 逻辑备份。
  - Percona XtraBackup 物理备份。
  - 本地目录、NFS、SSH + rsync 远端目录。
- 新增备份与恢复 runbook：`docs/BACKUP_AND_RESTORE_GUIDE.md`。
- 新增 AI 维护说明：
  - `AGENTS.md`
  - `docs/AI_MAINTAINER_GUIDE.md`
- 增强 GitHub Actions 静态质量门，覆盖 Ansible syntax-check 和 inventory 校验。

### 变更

- 将此前分散的脚本能力收敛到当前生产部署主线。
- Router bootstrap 行为更偏保守和幂等。
- 围绕当前主线同步文档。

## [0.1.0] - 2025-07-09

### 新增

- MySQL InnoDB Cluster 自动化仓库首次公开发布。
- 提供 MySQL Server 安装、InnoDB Cluster 配置和 MySQL Router 设置的基础 Ansible 结构。

## 历史记录

### 2024-12-28 - 8C32G + 4C8G 优化配置成为默认设计基线

- 引入 8C32G MySQL + 4C8G Router 容量模型。
- 新增 `scripts/config_manager.sh`，用于切换硬件配置。
- 新增历史硬件配置快照。
- 更新 Router 部署和容量分析相关文档。

### 2024-12-27 - 高并发调优

- 增加 Router 与 MySQL 高并发配置思路。
- 增加系统参数调优说明。
- 增加监控与告警说明。

### 2024-12-26 - 初始内部基线

- 增加初始 MySQL InnoDB Cluster 部署脚本。
- 增加 3 节点 MySQL 集群基础支持。
- 增加 MySQL Router 基础配置。
