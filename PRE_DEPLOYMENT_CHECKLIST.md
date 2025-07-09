# MySQL InnoDB Cluster 部署前检查清单

## 🚀 快速部署检查 (5分钟)

### ✅ 必检项目

**环境准备**
- [ ] 控制节点已安装 Python3 (3.6+)
- [ ] 控制节点已安装 Ansible (6.0+)
- [ ] 已安装项目依赖: `pip install -r requirements.txt`

**网络配置**
- [ ] 已修改 `inventory/hosts.yml` 中的实际IP地址
- [ ] 已修改 `inventory/hosts.yml` 中的实际SSH密码
- [ ] SSH可以连接到所有目标服务器
- [ ] 目标服务器之间网络互通

**目标服务器**
- [ ] 操作系统: CentOS 7/8 或 Rocky Linux 8+
- [ ] 硬件配置: 最低4核8G内存，推荐8核32G
- [ ] 防火墙已开放MySQL端口 (3306, 33061, 33062)
- [ ] 服务器时间已同步

### 🔍 验证命令

```bash
# 1. 运行项目验证脚本
./validate_deployment.ps1    # Windows
# 或
bash validate_deployment.sh  # Linux

# 2. 测试Ansible连通性
ansible all -i inventory/hosts.yml -m ping

# 3. 检查目标服务器硬件
ansible all -i inventory/hosts.yml -m setup -a "filter=ansible_processor*,ansible_memtotal_mb"
```

### 📋 部署架构选择

选择一个inventory文件：

- [ ] **基础架构** (`inventory/hosts.yml`)
  - 3个MySQL节点 + Router与MySQL共存
  - 适合: 小型生产环境

- [ ] **推荐架构** (`inventory/hosts-recommended-router.yml`) ⭐
  - 3个MySQL节点 + 2个独立Router节点  
  - 适合: 中型生产环境 (推荐)

- [ ] **高可用架构** (`inventory/hosts-with-dedicated-routers.yml`)
  - 3个MySQL节点 + 专用Router集群
  - 适合: 大型生产环境

## 🎯 一键部署

```bash
# 完整自动部署
./deploy.sh all

# 检查部署状态
./deploy.sh status
```

## ⚠️ 常见问题快速修复

**问题1**: Ansible连接失败
```bash
# 解决方案: 检查SSH配置
ssh -o StrictHostKeyChecking=no root@目标IP
```

**问题2**: Python模块缺失
```bash
# 解决方案: 安装必要模块
pip install PyMySQL mysql-connector-python
```

**问题3**: 防火墙阻塞
```bash
# 解决方案: 开放端口
firewall-cmd --permanent --add-port=3306/tcp
firewall-cmd --permanent --add-port=33061/tcp  
firewall-cmd --permanent --add-port=33062/tcp
firewall-cmd --reload
```

## 📞 部署支持

- 📖 详细文档: `DEPLOYMENT_COMPLETE_GUIDE.md`
- 🔧 故障排除: `TROUBLESHOOTING.md`  
- 📋 验证报告: `DEPLOYMENT_VALIDATION_REPORT.md`

---

**✅ 所有检查项目完成后，即可安全部署！** 