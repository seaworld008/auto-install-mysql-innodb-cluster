---
title: MySQL InnoDB Cluster Automation Docs
---

# MySQL InnoDB Cluster Automation Docs

本页是 GitHub Pages 文档站点入口。仓库仍然以 `README.md`、`DEPLOYMENT_COMPLETE_GUIDE.md`、`QUICK_START.md` 和 `PRE_DEPLOYMENT_CHECKLIST.md` 作为主用户文档；站点用于把专题 runbook、变量参考、演练记录模板和维护说明集中索引。

## 快速入口

| 主题 | 文档 |
| --- | --- |
| 中文主说明 | [README](https://github.com/seaworld008/auto-install-mysql-innodb-cluster/blob/main/README.md) |
| English summary | [README_EN](https://github.com/seaworld008/auto-install-mysql-innodb-cluster/blob/main/README_EN.md) |
| 快速开始 | [QUICK_START](https://github.com/seaworld008/auto-install-mysql-innodb-cluster/blob/main/QUICK_START.md) |
| 部署总览 | [DEPLOYMENT_COMPLETE_GUIDE](https://github.com/seaworld008/auto-install-mysql-innodb-cluster/blob/main/DEPLOYMENT_COMPLETE_GUIDE.md) |
| 部署前检查 | [PRE_DEPLOYMENT_CHECKLIST](https://github.com/seaworld008/auto-install-mysql-innodb-cluster/blob/main/PRE_DEPLOYMENT_CHECKLIST.md) |
| 高可用蓝图 | [DEPLOYMENT_HA_BLUEPRINT_ZH](DEPLOYMENT_HA_BLUEPRINT_ZH.md) |
| 架构图与证据留存 | [ARCHITECTURE_AND_EVIDENCE](ARCHITECTURE_AND_EVIDENCE.md) |
| 变量参考 | [VARIABLE_REFERENCE](VARIABLE_REFERENCE.md) |
| 备份与恢复 | [BACKUP_AND_RESTORE_GUIDE](BACKUP_AND_RESTORE_GUIDE.md) |
| 故障排查 | [TROUBLESHOOTING](https://github.com/seaworld008/auto-install-mysql-innodb-cluster/blob/main/TROUBLESHOOTING.md) |

## 演练记录模板

- [Staging 验证记录模板](templates/staging-validation-record.md)
- [故障演练记录模板](templates/failover-drill-record.md)
- [隔离环境恢复演练模板](templates/restore-drill-record.md)

## 维护者入口

- [AI Maintainer Guide](AI_MAINTAINER_GUIDE.md)
- [Release Checklist](RELEASE_CHECKLIST_ZH.md)
- [项目结构](https://github.com/seaworld008/auto-install-mysql-innodb-cluster/blob/main/PROJECT_STRUCTURE.md)
- [ADR-001: Documentation site and advisory lint](decisions/ADR-001-documentation-site-and-advisory-lint.md)

## 说明

GitHub Pages 需要在仓库 Settings -> Pages 中选择 GitHub Actions 作为发布来源。站点工作流只发布文档，不执行部署、不接触目标主机，也不改变运行时配置。
