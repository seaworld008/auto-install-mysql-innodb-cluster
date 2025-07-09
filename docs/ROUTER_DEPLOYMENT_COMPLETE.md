# MySQL Router 完整部署指南

## 🎯 部署概述

MySQL Router是MySQL InnoDB Cluster的关键组件，负责将客户端连接路由到健康的数据库节点。本指南涵盖了Router的部署策略、配置方法和生产环境最佳实践。

## 📊 部署架构选择

### 部署策略对比

| 部署方式 | 延迟 | 可维护性 | 扩展性 | 资源开销 | 推荐场景 |
|----------|------|----------|--------|----------|----------|
| **应用服务器端** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | 微服务架构 |
| **独立Router集群** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | **企业级集中部署** |
| **数据库服务器端** | ⭐⭐⭐ | ⭐⭐ | ⭐⭐ | ⭐⭐ | 资源受限环境 |

### 🌟 推荐方案：独立Router集群

**适用场景**：
- 企业级生产环境
- 多应用共享数据库
- 需要集中管理和监控
- 高可用性要求

**架构设计**：
```
应用程序层 (前端60K连接)
    ↓
HAProxy VIP (192.168.1.100)
    ↓
Router集群 (192.168.1.20-21) - 2×4核8G
    ↓ (后端12K连接)
MySQL集群 (192.168.1.10-12) - 3×8核32G
```

## 🖥️ 硬件配置

### MySQL Server配置 (3台)
- **CPU**: 8核 (可升级至32核)
- **内存**: 32GB (可升级至64GB)
- **存储**: SSD 500GB+
- **网络**: 千兆内网

### Router Server配置 (2台)
- **CPU**: 4核
- **内存**: 8GB
- **存储**: 100GB SSD
- **网络**: 千兆内网

### 连接规划

| 组件 | 前端连接 | 后端连接 | 连接复用比 |
|------|----------|----------|------------|
| **Router集群** | 60000 (30K/台) | 12000 (6K/台) | 5:1 |
| **MySQL集群** | 12000 (4K/台) | - | - |

## 🚀 快速部署

### 1. 服务器准备

```bash
# 配置服务器清单
vim inventory/hosts-with-dedicated-routers.yml

# 示例配置：
mysql-cluster:
  mysql-node1:
    ansible_host: 192.168.1.10
    server_id: 1
  mysql-node2:
    ansible_host: 192.168.1.11
    server_id: 2
  mysql-node3:
    ansible_host: 192.168.1.12
    server_id: 3

mysql-routers:
  router-node1:
    ansible_host: 192.168.1.20
    router_id: 1
  router-node2:
    ansible_host: 192.168.1.21
    router_id: 2
```

### 2. 一键部署

```bash
# 完整部署（包含内核优化）
./scripts/deploy_dedicated_routers.sh --production-ready

# 或分步骤部署：

# 步骤1：内核优化（行业最佳实践）
sudo ./scripts/optimize_mysql_kernel_stable.sh

# 步骤2：MySQL集群部署
ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/install-mysql.yml

# 步骤3：Router集群部署
ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/install-router.yml

# 步骤4：配置集群
ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/configure-cluster.yml
```

### 3. HAProxy配置（可选）

```bash
# 安装HAProxy
sudo yum install -y haproxy

# 配置文件示例
cat > /etc/haproxy/haproxy.cfg << 'EOF'
global
    log stdout local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    mode tcp
    log global
    option tcplog
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

# MySQL读写端口 (6446)
frontend mysql_read_write
    bind *:6446
    default_backend mysql_read_write_servers

backend mysql_read_write_servers
    balance roundrobin
    server router1 192.168.1.20:6446 check
    server router2 192.168.1.21:6446 check

# MySQL只读端口 (6447)
frontend mysql_readonly
    bind *:6447
    default_backend mysql_readonly_servers

backend mysql_readonly_servers
    balance roundrobin
    server router1 192.168.1.20:6447 check
    server router2 192.168.1.21:6447 check

# 统计页面
listen stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 30s
    stats admin if TRUE
EOF

# 启动HAProxy
sudo systemctl enable haproxy --now
```

## ⚙️ Router配置详解

### 1. 高并发优化配置

```ini
# /etc/mysqlrouter/mysqlrouter.conf

[DEFAULT]
logging_folder=/var/log/mysqlrouter
runtime_folder=/var/run/mysqlrouter
config_folder=/etc/mysqlrouter

# 连接池配置 - 支持30K连接
max_connections=30000
max_connect_errors=100
client_connect_timeout=9
server_connect_timeout=9

[logger]
level=INFO
sinks=consolelog,filelog

[metadata_cache:bootstrap]
router_id=1
bootstrap_server_addresses=192.168.1.10:3306,192.168.1.11:3306,192.168.1.12:3306
user=mysqlrouter
metadata_cluster=myCluster
ttl=0.5
auth_cache_ttl=2
auth_cache_refresh_interval=2

# 读写分离配置
[routing:bootstrap_rw]
bind_address=0.0.0.0
bind_port=6446
destinations=metadata-cache://myCluster/default?role=PRIMARY
routing_strategy=round-robin
protocol=classic
max_connections=15000

[routing:bootstrap_ro]
bind_address=0.0.0.0
bind_port=6447
destinations=metadata-cache://myCluster/default?role=SECONDARY
routing_strategy=round-robin
protocol=classic
max_connections=15000
```

### 2. 系统级优化

```bash
# 系统限制配置
cat >> /etc/security/limits.conf << 'EOF'
mysqlrouter soft nofile 65536
mysqlrouter hard nofile 65536
mysqlrouter soft nproc 32768
mysqlrouter hard nproc 32768
EOF

# 内核参数优化（已集成在稳定版内核优化脚本中）
sudo ./scripts/optimize_mysql_kernel_stable.sh
```

## 📊 性能监控

### 1. Router状态监控

```bash
# 检查Router进程状态
sudo systemctl status mysqlrouter

# 查看Router日志
sudo tail -f /var/log/mysqlrouter/mysqlrouter.log

# 检查连接数
ss -tuln | grep -E "(6446|6447)"
netstat -an | grep -E "(6446|6447)" | wc -l
```

### 2. 性能指标

```sql
-- 在MySQL中查看Router连接状态
SELECT 
  SUBSTRING_INDEX(host, ':', 1) as router_ip,
  COUNT(*) as connection_count 
FROM information_schema.processlist 
WHERE host LIKE '192.168.1.2%' 
GROUP BY router_ip;

-- 查看集群状态
SELECT * FROM performance_schema.replication_group_members;
```

### 3. HAProxy监控

访问监控页面：`http://192.168.1.100:8404/stats`

## 🔧 故障排除

### 常见问题

#### 1. Router连接失败
```bash
# 检查MySQL集群状态
mysql -h 192.168.1.10 -u root -p -e "SELECT * FROM performance_schema.replication_group_members;"

# 检查Router配置
sudo mysqlrouter --validate-config

# 重启Router服务
sudo systemctl restart mysqlrouter
```

#### 2. 连接数不足
```bash
# 检查系统限制
ulimit -n

# 检查Router配置中的max_connections
grep max_connections /etc/mysqlrouter/mysqlrouter.conf

# 检查MySQL连接限制
mysql -h 192.168.1.10 -u root -p -e "SHOW VARIABLES LIKE 'max_connections';"
```

#### 3. 性能问题
```bash
# 查看系统资源使用
top -p $(pgrep mysqlrouter)
iostat -x 1

# 查看网络连接
ss -s
netstat -i
```

## 🚀 生产环境检查清单

### 部署前检查
- [ ] 服务器硬件规格确认
- [ ] 网络连通性测试
- [ ] 防火墙端口开放
- [ ] SSH密钥认证配置
- [ ] Ansible连接测试

### 部署后验证
- [ ] MySQL集群状态正常
- [ ] Router服务启动成功
- [ ] 连接路由功能正常
- [ ] 故障转移测试通过
- [ ] 性能基准测试完成
- [ ] 监控系统配置完成

### 日常维护
- [ ] 定期备份配置文件
- [ ] 监控日志文件大小
- [ ] 检查系统资源使用率
- [ ] 验证集群健康状态
- [ ] 测试故障恢复流程

## 📈 扩展升级

### 硬件升级路径

```bash
# 当需要升级到32核64G时
./scripts/config_manager.sh --switch high-performance
./scripts/upgrade_hardware_profile.sh --profile high_performance

# 应用新配置
ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/site.yml
```

### 连接数扩展

| 硬件规格 | Router连接数 | MySQL连接数 | 总前端连接 |
|----------|-------------|-------------|-----------|
| **当前** (8C32G+4C8G) | 30K/台 | 4K/台 | 60K |
| **升级** (32C64G+8C16G) | 50K/台 | 10K/台 | 100K |

现在你的Router集群已经准备就绪，可以支持高并发的生产环境部署！🚀 