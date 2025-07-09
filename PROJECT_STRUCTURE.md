# MySQL InnoDB Cluster 项目结构总览

## 📁 项目结构（已清理优化）

```
09-outo-install-mysql-innodb-cluster/
├── 📄 README.md                          # 项目主文档 - 推荐稳定配置
├── 📄 QUICKSTART.md                       # 快速开始指南
├── 📄 README_ROUTER_DEPLOYMENT.md         # Router部署指南
│
├── 📂 scripts/                           # 核心脚本（已优化清理）
│   ├── 🔧 optimize_mysql_kernel_stable.sh  # 🌟 内核优化 - 行业最佳实践
│   ├── 🚀 deploy_dedicated_routers.sh      # 主部署脚本
│   ├── ⚙️ config_manager.sh               # 配置管理工具
│   ├── 📈 upgrade_hardware_profile.sh     # 硬件升级脚本
│   ├── 🔧 setup-servers.sh               # 服务器初始化
│   ├── 🧪 failover-test.sh              # 故障转移测试
│   └── 📊 cluster-status.sh              # 集群状态检查
│
├── 📂 playbooks/                         # Ansible脚本（已优化清理）
│   ├── 🌟 kernel-optimization-stable.yml   # 内核优化 - 行业最佳实践
│   ├── 🗄️ install-mysql.yml              # MySQL安装
│   ├── 🔀 install-router.yml             # Router安装
│   ├── ⚙️ configure-cluster.yml          # 集群配置
│   └── 📋 site.yml                       # 主playbook
│
├── 📂 docs/                              # 文档（已清理优化）
│   ├── 🌟 MYSQL_KERNEL_BEST_PRACTICES.md   # 🎯 内核优化最佳实践对比
│   ├── 📊 HARDWARE_CAPACITY_ANALYSIS.md    # 硬件容量分析
│   ├── ⚡ HIGH_CONCURRENCY_OPTIMIZATION.md  # 高并发优化
│   ├── 🔧 ROUTER_DEPLOYMENT_GUIDE.md       # Router部署详细指南
│   ├── 📖 PRODUCTION_OPTIMIZATION.md       # 生产优化最佳实践
│   └── 🔧 SERVER_CONFIGURATION.md          # 服务器配置
│
├── 📂 inventory/                         # Ansible清单
├── 📂 roles/                            # Ansible角色
├── 📂 files/                            # 配置文件
├── 📂 examples/                         # 示例配置
│
├── 📄 ansible.cfg                       # Ansible配置
├── 📄 requirements.txt                  # Python依赖
├── 📄 deploy.sh                         # 快速部署脚本
├── 📄 DEPLOYMENT_GUIDE.md               # 部署指南
├── 📄 TROUBLESHOOTING.md                # 故障排除
├── 📄 CHECKLIST.md                      # 部署检查清单
└── 📄 CHANGELOG.md                      # 变更日志
```

## 🎯 核心组件说明

### 🌟 内核优化（已升级为行业最佳实践）

**主要工具**：
- `scripts/optimize_mysql_kernel_stable.sh` - **推荐使用**
  - 基于Oracle MySQL、Percona、MariaDB官方推荐
  - 动态参数调整（根据系统规格自动适配）
  - 保守且稳定的企业级配置
  - 完整的备份和回滚支持

**文档参考**：
- `docs/MYSQL_KERNEL_BEST_PRACTICES.md` - **重要参考**
  - 详细的配置对比分析
  - 权威来源说明
  - 稳定性保证
  - 生产环境验证记录

### 🚀 部署脚本

**主要工具**：
- `scripts/deploy_dedicated_routers.sh` - 专用Router部署
- `scripts/config_manager.sh` - 配置管理和切换
- `playbooks/kernel-optimization-stable.yml` - Ansible批量内核优化

### 📚 文档体系

**核心文档**：
- `README.md` - 项目总览（推荐稳定配置）
- `QUICKSTART.md` - 快速上手
- `docs/MYSQL_KERNEL_BEST_PRACTICES.md` - 内核优化最佳实践

## 🧹 清理说明

**已删除的冗余文件**：
- ❌ `scripts/optimize_mysql_kernel.sh` - 激进配置，已被稳定版替代
- ❌ `playbooks/kernel-optimization.yml` - 激进配置，已被稳定版替代  
- ❌ `docs/MYSQL_KERNEL_OPTIMIZATION.md` - 激进配置文档，已被最佳实践文档替代
- ❌ `templates/` 目录 - 模板文件已集成到稳定版本中

**清理原则**：
- 保留稳定且基于行业最佳实践的配置
- 删除激进和实验性的配置
- 合并重复功能的文件
- 简化项目结构，提升可维护性

## 🎯 推荐使用方式

```bash
# 1. 内核优化（行业最佳实践）
sudo ./scripts/optimize_mysql_kernel_stable.sh

# 2. 完整部署
./scripts/deploy_dedicated_routers.sh --production-ready

# 3. Ansible批量优化
ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/kernel-optimization-stable.yml
```

现在项目结构更加清晰，专注于稳定可靠的生产级配置！🚀 