---
title: MySQL InnoDB Cluster 文档
---

# MySQL InnoDB Cluster 文档

使用 Ansible 部署并管理 MySQL、Router 和高可用入口，从第一套集群开始，逐步建立可重复的运维流程。

## 开始使用

| 目标 | 文档 |
| --- | --- |
| 了解项目 | [中文首页](https://github.com/seaworld008/auto-install-mysql-innodb-cluster/blob/main/README.md) · [English](https://github.com/seaworld008/auto-install-mysql-innodb-cluster/blob/main/README_EN.md) |
| 创建第一套集群 | [快速开始](https://github.com/seaworld008/auto-install-mysql-innodb-cluster/blob/main/QUICK_START.md) |
| 规划部署 | [完整指南](https://github.com/seaworld008/auto-install-mysql-innodb-cluster/blob/main/DEPLOYMENT_COMPLETE_GUIDE.md) · [部署前检查](https://github.com/seaworld008/auto-install-mysql-innodb-cluster/blob/main/PRE_DEPLOYMENT_CHECKLIST.md) |
| 接入应用 | [连接、事务与 TLS](runbooks/APPLICATION_CONNECTIONS.md) |

## 部署与运维

- [服务器配置](runbooks/SERVER_CONFIGURATION.md)
- [配置变更与扩缩容](runbooks/OPERATOR_GUIDE.md)
- [备份与隔离恢复](runbooks/BACKUP_AND_RESTORE_GUIDE.md)
- [故障排查](runbooks/TROUBLESHOOTING.md)
- [本地模拟环境](runbooks/LOCAL_SIMULATION.md)

## 技术参考

- [高可用架构](reference/DEPLOYMENT_HA_BLUEPRINT_ZH.md)
- [变量参考](reference/VARIABLE_REFERENCE.md)
- [内核配置](reference/MYSQL_KERNEL_BEST_PRACTICES.md)
- [版本兼容参考](reference/MYSQL80_CLUSTER_CROSS_VALIDATION.md)
- [项目结构](reference/PROJECT_STRUCTURE.md)

## 贡献与维护

开发检查、演练模板、历史分析和发布流程集中在 [维护者指南](maintainers/AI_MAINTAINER_GUIDE.md)。
项目更新见 [Changelog](https://github.com/seaworld008/auto-install-mysql-innodb-cluster/blob/main/CHANGELOG.md)，
下载见 [最新 Release](https://github.com/seaworld008/auto-install-mysql-innodb-cluster/releases/latest)。
