# MySQL InnoDB Cluster 自动化部署

**从主机准备到集群运维，让 MySQL 高可用部署有章可循。**

[![CI](https://github.com/seaworld008/auto-install-mysql-innodb-cluster/actions/workflows/ansible-ci.yml/badge.svg?branch=main)](https://github.com/seaworld008/auto-install-mysql-innodb-cluster/actions/workflows/ansible-ci.yml)
[![Release](https://img.shields.io/github/v/release/seaworld008/auto-install-mysql-innodb-cluster)](https://github.com/seaworld008/auto-install-mysql-innodb-cluster/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[English](README_EN.md) · [快速开始](QUICK_START.md) · [完整部署指南](DEPLOYMENT_COMPLETE_GUIDE.md) · [文档中心](docs/index.md)

基于 Ansible 的 MySQL InnoDB Cluster 部署与运维工具，面向 DBA、SRE、平台工程和后端团队。
统一编排 **MySQL Server、MySQL Router、HAProxy 与 Keepalived**，从首次安装到节点扩缩容、滚动配置和备份，复用同一套配置与操作入口。

## 你可以用它做什么

| 能力 | 说明 |
| --- | --- |
| 集群部署 | 安装 MySQL，创建 InnoDB Cluster，逐台加入成员 |
| 高可用接入 | 独立 Router 层连接集群，双 HAProxy + Keepalived 提供 VIP |
| 读写接入 | 提供明确的读写、只读端口，以及可选自动读写分离端口 |
| 生命周期管理 | MySQL 扩缩容、Router/LB 缩容与配置滚动应用 |
| 状态检查 | 检查成员 ONLINE、集群身份、入口服务、监听端口及 VIP 唯一归属 |
| 备份与恢复 | 可选 MySQL Shell 逻辑备份、Percona XtraBackup 物理备份，配套隔离恢复指南 |
| 本地模拟 | 用独立 Linux VM 和 systemd 容器准备模拟主机，复用正式 Ansible 部署流程 |

运行配置集中在 [`inventory/group_vars/all.yml`](inventory/group_vars/all.yml)，所有日常操作通过
[`scripts/deploy_dedicated_routers.sh`](scripts/deploy_dedicated_routers.sh) 执行。

## 架构

```mermaid
flowchart LR
    App[应用] --> VIP[Keepalived VIP]
    VIP --> HA[HAProxy × 2]
    HA --> Router[MySQL Router × 2]
    Router --> Primary[MySQL Primary]
    Router --> Secondary[MySQL Secondary × 2]
    Primary <--> Secondary
```

| 层级 | 默认拓扑 | 职责 |
| --- | --- | --- |
| 数据库 | 3 台 MySQL | Group Replication 与单主写入 |
| 路由 | 2 台独立 Router | 根据集群元数据选择后端 |
| 入口 | 2 台 HAProxy + Keepalived | VIP 与四层转发 |

HAProxy 后端指向 Router；主节点切换后，由 Router 跟随集群拓扑选择写入节点。
节点规格、网络规划与接入方式见 [部署蓝图](docs/reference/DEPLOYMENT_HA_BLUEPRINT_ZH.md)。

## 快速开始

准备可通过 SSH 管理的 Linux 主机。控制节点使用 **Python 3.12+**，目标节点预装 **Python 3.9+**。
MySQL 默认使用 **8.4 LTS**，也可选择 8.0；目标发行版清单见 [部署前检查](PRE_DEPLOYMENT_CHECKLIST.md)。

```bash
git clone https://github.com/seaworld008/auto-install-mysql-innodb-cluster.git
cd auto-install-mysql-innodb-cluster

python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
ansible-galaxy collection install -r collections/requirements.yml

# 生成本地 inventory，再创建加密凭据文件
./scripts/setup-servers.sh
ansible-vault create inventory/vault.local.yml
```

向导生成的本地 inventory 和 Vault 文件均被 Git 忽略。按 [快速开始](QUICK_START.md)
填写数据库密码、VRRP 口令、VIP 与主机信息，并通过可信渠道核验 SSH 主机指纹后执行：

```bash
./scripts/deploy_dedicated_routers.sh --check-prereq \
  -i inventory/hosts.local.yml --ask-vault-pass -e @inventory/vault.local.yml

./scripts/deploy_dedicated_routers.sh --production-ready \
  -i inventory/hosts.local.yml --ask-vault-pass -e @inventory/vault.local.yml

./scripts/deploy_dedicated_routers.sh --status \
  -i inventory/hosts.local.yml --ask-vault-pass -e @inventory/vault.local.yml
```

第一次使用？从 [快速开始](QUICK_START.md) 完成逐项配置；暂时没有 Linux 主机，可使用
[本地模拟环境](docs/runbooks/LOCAL_SIMULATION.md) 熟悉流程。

## 应用连接

| 用途 | VIP 端口 | Router 直连端口 |
| --- | --- | --- |
| 写入、事务与读后写一致性访问 | `3307` | `6446` |
| 允许副本延迟的只读访问 | `3308` | `6447` |
| 可选自动读写分离 | `3309` | `6450` |

事务型应用优先使用明确的读写入口；自动分离需按驱动、连接池与事务行为完成兼容性验证。
证书、连接重试和路由选择见 [应用接入指南](docs/runbooks/APPLICATION_CONNECTIONS.md)。

## 常用操作

在上述部署命令中替换操作参数，继续使用同一份本地 inventory 和 Vault：

| 操作 | 参数 |
| --- | --- |
| 只部署数据库集群 | `--mysql-only` |
| 部署 Router | `--install-routers` |
| 部署入口层 | `--configure-lb` |
| 滚动应用配置 | `--apply-config` |
| 增加 MySQL 节点 | `--scale-mysql-add --limit mysql-node4` |
| 移除 MySQL 节点 | `--scale-mysql-remove --target mysql-node3` |
| 移除 Router / LB | `--shrink-router --target router-node3` / `--shrink-lb --target lb-node3` |
| 执行备份 | `--backup` |
| 检查状态 | `--status` |

扩容前先更新 inventory；移除当前 primary 时还需指定 `--new-primary`。
备份默认关闭，支持 local、NFS、rsync 目标。完整步骤见 [运维指南](docs/runbooks/OPERATOR_GUIDE.md)。

## 使用原则

- 真实地址和凭据放在受保护的本地 inventory、Ansible Vault 或外部 Secret 中。
- 重复部署保留已有 Router 身份与 keyring；配置变更按节点滚动执行，安排维护窗口。
- 每个集群使用独立组 UUID；已有集群以实际身份为准，配置不一致时停止操作并提示核对。
- 上线前根据自己的拓扑完成证书配置、容量评估、故障切换和隔离恢复演练。

## 文档与参与

| 我想要…… | 从这里开始 |
| --- | --- |
| 部署第一个集群 | [快速开始](QUICK_START.md) · [检查清单](PRE_DEPLOYMENT_CHECKLIST.md) |
| 规划和维护环境 | [部署指南](DEPLOYMENT_COMPLETE_GUIDE.md) · [变量参考](docs/reference/VARIABLE_REFERENCE.md) |
| 接入应用与排障 | [应用接入](docs/runbooks/APPLICATION_CONNECTIONS.md) · [故障排查](docs/runbooks/TROUBLESHOOTING.md) |
| 配置备份与演练恢复 | [备份恢复指南](docs/runbooks/BACKUP_AND_RESTORE_GUIDE.md) |
| 本地开发与贡献 | [模拟环境](docs/runbooks/LOCAL_SIMULATION.md) · [贡献指南](CONTRIBUTING.md) |
| 了解项目更新 | [Changelog](CHANGELOG.md) · [Release](https://github.com/seaworld008/auto-install-mysql-innodb-cluster/releases/latest) |

欢迎提交可复现的问题、改进建议和 Pull Request。安全问题请按 [安全政策](SECURITY.md) 私下报告。

本项目采用 [MIT License](LICENSE)。
