# MySQL InnoDB Cluster 完整部署指南

## 🎯 部署概述

本指南提供MySQL InnoDB Cluster + Router的完整部署流程，从环境准备到生产验证的全流程指导。

## 📋 系统要求

### 硬件配置

#### MySQL服务器 (3台)
- **CPU**: 8核 (推荐，可升级至32核)
- **内存**: 32GB (推荐，可升级至64GB)
- **存储**: SSD 500GB+ (高性能存储)
- **网络**: 千兆内网，低延迟

#### Router服务器 (2台)
- **CPU**: 4核
- **内存**: 8GB
- **存储**: 100GB SSD
- **网络**: 千兆内网

### 软件要求

#### 控制机器 (Windows/Linux)
- **Ansible**: 6.0+
- **Python**: 3.6+
- **PowerShell**: 7.0+ (Windows)
- **Git**: 最新版本

#### 目标服务器 (Linux)
- **操作系统**: CentOS 7.9+/8.x, RHEL 8+, Ubuntu 18.04+
- **架构**: x86_64 或 ARM64
- **网络**: 开放端口 22, 3306, 33061, 33062, 6446, 6447
- **用户**: 具有sudo权限的用户账户

## 🚀 快速开始 (推荐)

### 一键部署命令

```bash
# 完整生产级部署（包含内核优化）
./scripts/deploy_dedicated_routers.sh --production-ready

# 或者使用配置管理器
./scripts/config_manager.sh --switch 8c32g-optimized
./scripts/deploy_dedicated_routers.sh --use-config 8c32g-optimized
```

## 📝 详细部署流程

### 第一阶段：环境准备

#### 1. 克隆项目
```bash
# 在Windows/Linux控制机器上
git clone <repository_url>
cd 09-outo-install-mysql-innodb-cluster

# 安装Python依赖
pip3 install -r requirements.txt

# 验证Ansible安装
ansible --version
```

#### 2. 配置服务器清单

编辑服务器配置文件：
```bash
vim inventory/hosts-with-dedicated-routers.yml
```

**配置示例**：
```yaml
all:
  vars:
    # 全局配置
    mysql_root_password: "YourSecurePassword123!"
    cluster_name: "myCluster"
    
  children:
    mysql-cluster:
      hosts:
        mysql-node1:
          ansible_host: 192.168.1.10
          ansible_ssh_pass: "ServerPassword1"
          server_id: 1
          
        mysql-node2:
          ansible_host: 192.168.1.11
          ansible_ssh_pass: "ServerPassword2"
          server_id: 2
          
        mysql-node3:
          ansible_host: 192.168.1.12
          ansible_ssh_pass: "ServerPassword3"
          server_id: 3
    
    mysql-routers:
      hosts:
        router-node1:
          ansible_host: 192.168.1.20
          ansible_ssh_pass: "RouterPassword1"
          router_id: 1
          
        router-node2:
          ansible_host: 192.168.1.21
          ansible_ssh_pass: "RouterPassword2"
          router_id: 2

# 硬件配置选择（可选）
mysql_hardware_profile: "8c32g_optimized"  # 当前推荐配置
```

#### 3. 连接测试
```bash
# 测试Ansible连接
ansible -i inventory/hosts-with-dedicated-routers.yml all -m ping

# 预期输出（成功）：
# mysql-node1 | SUCCESS => { "ping": "pong" }
# mysql-node2 | SUCCESS => { "ping": "pong" }
# mysql-node3 | SUCCESS => { "ping": "pong" }
# router-node1 | SUCCESS => { "ping": "pong" }
# router-node2 | SUCCESS => { "ping": "pong" }
```

### 第二阶段：内核优化 (推荐)

#### 使用稳定的行业最佳实践优化

```bash
# 方式1：使用脚本批量优化
ansible -i inventory/hosts-with-dedicated-routers.yml all -m script -a "./scripts/optimize_mysql_kernel_stable.sh"

# 方式2：使用Ansible playbook
ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/kernel-optimization-stable.yml

# 方式3：单台服务器优化（如果需要）
sudo ./scripts/optimize_mysql_kernel_stable.sh
```

**内核优化特性**：
- ✅ 基于Oracle MySQL、Percona、MariaDB官方推荐
- ✅ 动态参数调整（根据系统规格自动适配）
- ✅ 保守且稳定的企业级配置
- ✅ 支持8核32G系统的优化参数

### 第三阶段：MySQL集群部署

#### 1. 安装MySQL
```bash
ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/install-mysql.yml
```

#### 2. 配置InnoDB Cluster
```bash
ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/configure-cluster.yml
```

#### 3. 验证集群状态
```bash
# 登录任一MySQL节点验证
mysql -h 192.168.1.10 -u root -p

# 在MySQL中执行
SELECT * FROM performance_schema.replication_group_members;
```

**预期输出**：
```
+---------------------------+--------------------------------------+-------------+-------------+-----------+
| CHANNEL_NAME              | MEMBER_ID                            | MEMBER_HOST | MEMBER_PORT | MEMBER_STATE |
+---------------------------+--------------------------------------+-------------+-------------+-----------+
| group_replication_applier | xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx | mysql-node1 |        3306 | ONLINE    |
| group_replication_applier | xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx | mysql-node2 |        3306 | ONLINE    |
| group_replication_applier | xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx | mysql-node3 |        3306 | ONLINE    |
+---------------------------+--------------------------------------+-------------+-------------+-----------+
```

### 第四阶段：Router集群部署

#### 1. 安装Router
```bash
ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/install-router.yml
```

#### 2. 验证Router状态
```bash
# 检查Router服务
ansible -i inventory/hosts-with-dedicated-routers.yml mysql-routers -m shell -a "systemctl status mysqlrouter"

# 测试连接
mysql -h 192.168.1.20 -P 6446 -u root -p -e "SELECT @@hostname;"
mysql -h 192.168.1.21 -P 6447 -u root -p -e "SELECT @@hostname;"
```

### 第五阶段：高可用配置 (可选)

#### 配置HAProxy负载均衡

```bash
# 在负载均衡器上安装HAProxy
sudo yum install -y haproxy

# 应用配置
sudo tee /etc/haproxy/haproxy.cfg > /dev/null << 'EOF'
global
    log stdout local0
    stats socket /run/haproxy/admin.sock mode 660 level admin
    user haproxy
    group haproxy
    daemon

defaults
    mode tcp
    log global
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

# MySQL读写端口
frontend mysql_rw
    bind *:6446
    default_backend mysql_rw_servers

backend mysql_rw_servers
    balance roundrobin
    server router1 192.168.1.20:6446 check
    server router2 192.168.1.21:6446 check

# MySQL只读端口
frontend mysql_ro
    bind *:6447
    default_backend mysql_ro_servers

backend mysql_ro_servers
    balance roundrobin
    server router1 192.168.1.20:6447 check
    server router2 192.168.1.21:6447 check

# 监控页面
listen stats
    bind *:8404
    stats enable
    stats uri /stats
EOF

# 启动HAProxy
sudo systemctl enable haproxy --now
```

## 🧪 部署验证与测试

### 基础功能测试

#### 1. 连接测试
```bash
# 测试读写连接 (通过HAProxy VIP)
mysql -h 192.168.1.100 -P 6446 -u root -p -e "CREATE DATABASE test_rw; USE test_rw; CREATE TABLE test(id INT); INSERT INTO test VALUES(1); SELECT * FROM test;"

# 测试只读连接
mysql -h 192.168.1.100 -P 6447 -u root -p -e "USE test_rw; SELECT * FROM test;"

# 清理测试
mysql -h 192.168.1.100 -P 6446 -u root -p -e "DROP DATABASE test_rw;"
```

#### 2. 故障转移测试
```bash
# 模拟主节点故障
ansible -i inventory/hosts-with-dedicated-routers.yml mysql-node1 -m shell -a "systemctl stop mysql"

# 检查集群状态 (应该自动故障转移)
mysql -h 192.168.1.100 -P 6446 -u root -p -e "SELECT * FROM performance_schema.replication_group_members;"

# 恢复主节点
ansible -i inventory/hosts-with-dedicated-routers.yml mysql-node1 -m shell -a "systemctl start mysql"
```

#### 3. 负载测试
```bash
# 使用sysbench进行基准测试
sysbench --db-driver=mysql --mysql-host=192.168.1.100 --mysql-port=6446 --mysql-user=root --mysql-password=YourPassword --mysql-db=test --tables=10 --table-size=100000 oltp_read_write prepare

sysbench --db-driver=mysql --mysql-host=192.168.1.100 --mysql-port=6446 --mysql-user=root --mysql-password=YourPassword --mysql-db=test --tables=10 --table-size=100000 --threads=50 --time=60 oltp_read_write run
```

### 性能验证

#### 1. 连接能力测试
```bash
# 检查当前连接数
mysql -h 192.168.1.100 -P 6446 -u root -p -e "SHOW STATUS LIKE 'Threads_connected';"

# 检查最大连接数配置
mysql -h 192.168.1.100 -P 6446 -u root -p -e "SHOW VARIABLES LIKE 'max_connections';"
```

#### 2. 内核优化效果验证
```bash
# 验证关键内核参数
sysctl net.core.somaxconn vm.swappiness fs.file-max

# 检查透明大页状态
cat /sys/kernel/mm/transparent_hugepage/enabled  # 应该显示 [never]

# 检查系统限制
ulimit -n  # 应该显示较大的文件描述符限制
```

## ✅ 生产环境检查清单

### 部署前检查清单

#### 硬件环境
- [ ] **服务器规格确认**: MySQL 3×8C32G + Router 2×4C8G
- [ ] **网络环境**: 内网千兆网络，延迟<1ms
- [ ] **存储性能**: SSD存储，IOPS>1000
- [ ] **电源冗余**: UPS保护，双电源供应

#### 网络配置
- [ ] **防火墙规则**: 开放3306, 33061, 33062, 6446, 6447端口
- [ ] **DNS解析**: 内网主机名解析正常
- [ ] **时间同步**: NTP服务配置，时间同步
- [ ] **网络连通性**: 所有节点互相ping通

#### 用户权限
- [ ] **SSH访问**: 密钥或密码认证配置
- [ ] **sudo权限**: 目标用户具有sudo权限
- [ ] **Ansible连接**: ansible ping测试通过
- [ ] **防火墙例外**: 管理端口访问权限

### 部署后验证清单

#### MySQL集群验证
- [ ] **集群状态**: 所有节点状态为ONLINE
- [ ] **主从复制**: 数据同步正常
- [ ] **用户权限**: root和应用用户权限正确
- [ ] **基准测试**: sysbench性能测试通过

#### Router集群验证
- [ ] **服务状态**: mysqlrouter服务运行正常
- [ ] **读写分离**: 6446端口路由到主节点
- [ ] **只读路由**: 6447端口路由到从节点
- [ ] **连接池**: 最大连接数配置正确

#### 高可用验证
- [ ] **故障转移**: 主节点故障自动切换
- [ ] **服务恢复**: 故障节点恢复后自动加入
- [ ] **Router故障**: Router故障时连接自动转移
- [ ] **负载均衡**: HAProxy健康检查正常

#### 监控配置
- [ ] **系统监控**: CPU、内存、磁盘监控
- [ ] **数据库监控**: MySQL性能指标监控
- [ ] **应用监控**: 连接数、QPS监控
- [ ] **日志收集**: 错误日志集中收集

### 性能基准检查

#### 连接能力验证
- [ ] **前端连接**: Router支持30K连接/台
- [ ] **后端连接**: MySQL支持4K连接/台
- [ ] **连接复用**: 5:1复用比例正常
- [ ] **连接延迟**: 连接建立时间<5ms

#### 吞吐量验证
- [ ] **读QPS**: 单节点>10K QPS
- [ ] **写QPS**: 集群>5K QPS
- [ ] **事务TPS**: 集群>2K TPS
- [ ] **响应时间**: 平均响应时间<10ms

#### 稳定性验证
- [ ] **长期稳定**: 7天连续运行无异常
- [ ] **内存使用**: 内存使用率<80%
- [ ] **CPU使用**: CPU使用率<70%
- [ ] **磁盘I/O**: 磁盘利用率<80%

## 🛠️ 日常运维

### 监控命令

#### 集群状态监控
```bash
# 检查集群状态
./scripts/cluster-status.sh

# 查看详细状态
mysql -h 192.168.1.100 -P 6446 -u root -p -e "SELECT * FROM performance_schema.replication_group_members;"

# HAProxy状态页面
curl http://192.168.1.100:8404/stats
```

#### 性能监控
```bash
# 查看连接数
mysql -h 192.168.1.100 -P 6446 -u root -p -e "SHOW STATUS LIKE 'Threads_connected';"

# 查看QPS
mysqladmin -h 192.168.1.100 -P 6446 -u root -p extended-status | grep Questions

# 查看慢查询
mysql -h 192.168.1.100 -P 6446 -u root -p -e "SHOW STATUS LIKE 'Slow_queries';"
```

### 故障处理

#### 常见故障排除
```bash
# MySQL节点故障
./scripts/failover-test.sh

# Router故障
sudo systemctl restart mysqlrouter

# 内核参数验证
sudo ./scripts/optimize_mysql_kernel_stable.sh --verify-only

# 配置回滚
./scripts/config_manager.sh --rollback
```

### 硬件升级

#### 升级到高性能配置
```bash
# 切换到32C64G配置
./scripts/config_manager.sh --switch high-performance

# 应用新配置
./scripts/upgrade_hardware_profile.sh --profile high_performance

# 验证升级效果
./scripts/config_manager.sh --current
```

## 🚀 部署完成

### 连接信息

部署成功后，应用程序可以使用以下连接信息：

#### 通过HAProxy VIP (推荐)
- **读写连接**: `192.168.1.100:6446`
- **只读连接**: `192.168.1.100:6447`
- **监控页面**: `http://192.168.1.100:8404/stats`

#### 直接连接Router
- **Router 1**: `192.168.1.20:6446/6447`
- **Router 2**: `192.168.1.21:6446/6447`

#### 应用程序连接示例
```python
# Python连接示例
import mysql.connector

# 读写连接
rw_conn = mysql.connector.connect(
    host='192.168.1.100',
    port=6446,
    user='your_app_user',
    password='your_app_password',
    database='your_database'
)

# 只读连接
ro_conn = mysql.connector.connect(
    host='192.168.1.100',
    port=6447,
    user='your_app_user',
    password='your_app_password',
    database='your_database'
)
```

### 架构总览

```
应用程序 (60K连接)
    ↓
HAProxy VIP (192.168.1.100)
    ↓
Router集群 (192.168.1.20-21)
    ↓ (12K连接)
MySQL集群 (192.168.1.10-12)
```

### 性能指标

| 组件 | 连接数 | QPS | 响应时间 |
|------|--------|-----|----------|
| **Router集群** | 60K (30K/台) | 200K+ | <5ms |
| **MySQL集群** | 12K (4K/台) | 50K+ | <10ms |

**恭喜！你现在拥有了一个企业级的高可用MySQL InnoDB Cluster环境！** 🎉

### 下一步建议

1. **配置应用连接池** - 使用连接池优化应用性能
2. **设置监控告警** - 配置Prometheus+Grafana监控
3. **制定备份策略** - 定期数据备份和恢复测试
4. **性能调优** - 根据实际负载进行参数微调
5. **安全加固** - 配置SSL连接和用户权限管理 