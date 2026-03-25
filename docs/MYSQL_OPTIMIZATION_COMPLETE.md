# MySQL 生产环境完整优化指南

## 🎯 优化概述

本指南涵盖MySQL InnoDB Cluster在生产环境中的完整优化配置，包括高并发优化、硬件配置适配、性能调优等内容。**内核优化请参考 [MYSQL_KERNEL_BEST_PRACTICES.md](MYSQL_KERNEL_BEST_PRACTICES.md)**。

## 📊 配置架构

### 高并发架构设计

```
应用程序层 (前端60K连接)
    ↓
HAProxy VIP (192.168.1.100)
    ↓
Router集群 (192.168.1.20-21) - 2×4核8G
    ↓ (后端12K连接，5:1复用)
MySQL集群 (192.168.1.10-12) - 3×8核32G
```

### 连接数配置策略

| 组件 | 前端连接 | 后端连接 | 连接复用比 | 内存占用/连接 |
|------|----------|----------|------------|---------------|
| **Router** | 30K/台 | 6K/台 | 5:1 | 8-16KB |
| **MySQL** | 4K/台 | - | - | 256KB-2MB |

**设计原理**：
- Router作为轻量级代理，主要处理连接路由，内存占用低
- MySQL处理实际数据操作，内存占用较高，需要合理控制连接数
- 通过连接复用，大幅降低后端数据库压力

## 🔧 硬件配置适配

### 当前推荐配置 (8核32G)

#### MySQL服务器配置
```ini
# /etc/mysql/mysql.conf.d/mysqld.cnf

[mysqld]
# 基础配置
server-id = 1  # 每台服务器不同
gtid_mode = ON
enforce_gtid_consistency = ON
binlog_format = ROW

# 内存配置 - 针对32G内存优化
innodb_buffer_pool_size = 20G          # 60%内存
innodb_buffer_pool_instances = 8       # 每个实例2.5G
innodb_log_buffer_size = 64M
innodb_sort_buffer_size = 2M
read_buffer_size = 1M
read_rnd_buffer_size = 1M
sort_buffer_size = 1M
join_buffer_size = 1M

# 连接配置 - 支持4K连接
max_connections = 4000
max_user_connections = 3800
max_connect_errors = 1000
connect_timeout = 10
wait_timeout = 28800
interactive_timeout = 28800

# 线程配置 - 针对8核CPU
thread_cache_size = 16
thread_stack = 512K
innodb_read_io_threads = 8
innodb_write_io_threads = 8
innodb_purge_threads = 4

# InnoDB配置 - 高并发优化
innodb_io_capacity = 2000
innodb_io_capacity_max = 4000
innodb_flush_method = O_DIRECT
innodb_file_per_table = ON
innodb_flush_log_at_trx_commit = 1
innodb_redo_log_capacity = 4G
# innodb_log_files_in_group 已由 MySQL 8.0.30+ 自动管理

# 查询缓存在 MySQL 8.0 中已移除，无需配置

# 慢查询日志
slow_query_log = ON
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 1

# 二进制日志
log-bin = mysql-bin
binlog_cache_size = 2M
max_binlog_cache_size = 1G
max_binlog_size = 1G
binlog_expire_logs_seconds = 604800

# Group Replication配置
loose-group_replication_group_name = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
loose-group_replication_start_on_boot = OFF
loose-group_replication_bootstrap_group = OFF
loose-group_replication_local_address = "192.168.1.10:33061"
loose-group_replication_group_seeds = "192.168.1.10:33061,192.168.1.11:33061,192.168.1.12:33061"
```

#### Router服务器配置
```ini
# /etc/mysqlrouter/mysqlrouter.conf

[DEFAULT]
logging_folder = /var/log/mysqlrouter
runtime_folder = /var/run/mysqlrouter
config_folder = /etc/mysqlrouter

# 高并发连接配置
max_connections = 30000
max_connect_errors = 100
client_connect_timeout = 9
server_connect_timeout = 9

# 性能优化
connect_timeout = 5
read_timeout = 30
client_ssl_mode = DISABLED

[logger]
level = INFO
sinks = consolelog,filelog

[metadata_cache:bootstrap]
router_id = 1
bootstrap_server_addresses = 192.168.1.10:3306,192.168.1.11:3306,192.168.1.12:3306
user = mysqlrouter
metadata_cluster = myCluster
ttl = 0.5
auth_cache_ttl = 2
auth_cache_refresh_interval = 2

# 读写分离配置
[routing:bootstrap_rw]
bind_address = 0.0.0.0
bind_port = 6446
destinations = metadata-cache://myCluster/default?role=PRIMARY
routing_strategy = round-robin
protocol = classic
max_connections = 15000

[routing:bootstrap_ro]
bind_address = 0.0.0.0
bind_port = 6447
destinations = metadata-cache://myCluster/default?role=SECONDARY
routing_strategy = round-robin
protocol = classic
max_connections = 15000
```

### 高性能配置 (32核64G) - 升级选项

#### MySQL服务器配置
```ini
[mysqld]
# 内存配置 - 针对64G内存优化
innodb_buffer_pool_size = 48G          # 75%内存
innodb_buffer_pool_instances = 16      # 每个实例3G
innodb_log_buffer_size = 128M

# 连接配置 - 支持10K连接
max_connections = 10000
max_user_connections = 9500

# 线程配置 - 针对32核CPU
thread_cache_size = 64
innodb_read_io_threads = 16
innodb_write_io_threads = 16
innodb_purge_threads = 8

# InnoDB配置 - 高性能优化
innodb_io_capacity = 4000
innodb_io_capacity_max = 8000
innodb_redo_log_capacity = 8G
```

#### Router服务器配置
```ini
[DEFAULT]
# 高性能连接配置
max_connections = 50000

[routing:bootstrap_rw]
max_connections = 25000

[routing:bootstrap_ro]
max_connections = 25000
```

## ⚡ 性能优化策略

### 1. 连接管理优化

#### 连接池配置建议
```python
# 应用端连接池配置示例 (Python)
import mysql.connector.pooling

# 读写连接池
rw_pool = mysql.connector.pooling.MySQLConnectionPool(
    pool_name="rw_pool",
    pool_size=20,              # 单应用实例连接池大小
    host='192.168.1.100',
    port=6446,
    user='app_user',
    password='app_password',
    database='app_db',
    autocommit=True,
    pool_reset_session=True
)

# 只读连接池
ro_pool = mysql.connector.pooling.MySQLConnectionPool(
    pool_name="ro_pool",
    pool_size=10,              # 只读连接较少
    host='192.168.1.100',
    port=6447,
    user='app_user',
    password='app_password',
    database='app_db',
    autocommit=True,
    pool_reset_session=True
)
```

#### 连接数规划
| 应用规模 | 实例数 | 连接池/实例 | 总连接数 | Router利用率 |
|----------|--------|-------------|----------|--------------|
| **小型** | 5 | 20 | 100 | 0.3% |
| **中型** | 50 | 30 | 1500 | 5% |
| **大型** | 200 | 50 | 10000 | 33% |
| **超大型** | 600 | 100 | 60000 | 100% |

### 2. 查询性能优化

#### 索引策略
```sql
-- 高并发查询的索引优化原则

-- 1. 主键优化 - 使用自增ID
CREATE TABLE user_data (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id VARCHAR(32) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- 复合索引 - 覆盖常用查询
    INDEX idx_user_created (user_id, created_at),
    
    -- 唯一索引 - 业务唯一性约束
    UNIQUE KEY uk_user_id (user_id)
) ENGINE=InnoDB;

-- 2. 分区表 - 大数据量优化
CREATE TABLE order_history (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    order_date DATE NOT NULL,
    amount DECIMAL(10,2),
    
    INDEX idx_date (order_date)
) ENGINE=InnoDB
PARTITION BY RANGE (TO_DAYS(order_date)) (
    PARTITION p202301 VALUES LESS THAN (TO_DAYS('2023-02-01')),
    PARTITION p202302 VALUES LESS THAN (TO_DAYS('2023-03-01')),
    PARTITION p202303 VALUES LESS THAN (TO_DAYS('2023-04-01')),
    PARTITION p_future VALUES LESS THAN MAXVALUE
);
```

#### 查询优化
```sql
-- 高效查询模式

-- 使用LIMIT避免全表扫描
SELECT * FROM large_table WHERE condition LIMIT 1000;

-- 使用索引提示
SELECT * FROM user_data USE INDEX (idx_user_created) 
WHERE user_id = 'xxx' AND created_at > '2023-01-01';

-- 避免SELECT *，明确指定字段
SELECT id, name, email FROM users WHERE active = 1;

-- 使用JOIN优化子查询
SELECT u.name, p.title 
FROM users u 
JOIN posts p ON u.id = p.user_id 
WHERE u.active = 1;
```

### 3. 事务优化

#### 事务最佳实践
```sql
-- 短事务原则 - 快速提交
START TRANSACTION;
UPDATE inventory SET quantity = quantity - 1 WHERE product_id = 123;
INSERT INTO order_items (order_id, product_id, quantity) VALUES (456, 123, 1);
COMMIT;

-- 避免长事务
-- 错误方式：
-- START TRANSACTION;
-- SELECT ... FOR UPDATE;  -- 长时间锁定
-- /* 复杂业务逻辑处理 */
-- UPDATE ...;
-- COMMIT;

-- 正确方式：分离查询和更新
SELECT current_value FROM table WHERE id = 123;
-- 应用层处理
START TRANSACTION;
UPDATE table SET value = new_value WHERE id = 123 AND current_value = old_value;
COMMIT;
```

### 4. 读写分离优化

#### 应用层读写分离
```python
class DatabaseManager:
    def __init__(self):
        self.rw_pool = create_rw_pool()
        self.ro_pool = create_ro_pool()
    
    def execute_query(self, sql, readonly=False):
        pool = self.ro_pool if readonly else self.rw_pool
        with pool.get_connection() as conn:
            return conn.execute(sql)
    
    def get_user(self, user_id):
        # 读操作使用只读连接
        sql = "SELECT * FROM users WHERE id = %s"
        return self.execute_query(sql, readonly=True)
    
    def update_user(self, user_id, data):
        # 写操作使用读写连接
        sql = "UPDATE users SET name = %s WHERE id = %s"
        return self.execute_query(sql, readonly=False)
```

## 📊 监控与性能分析

### 1. 关键性能指标

#### MySQL性能监控
```sql
-- 连接数监控
SHOW STATUS LIKE 'Threads_connected';
SHOW STATUS LIKE 'Max_used_connections';

-- QPS监控
SHOW STATUS LIKE 'Questions';
SHOW STATUS LIKE 'Queries';

-- 缓存命中率
SHOW STATUS LIKE 'Innodb_buffer_pool_read_requests';
SHOW STATUS LIKE 'Innodb_buffer_pool_reads';

-- 锁等待监控
SHOW STATUS LIKE 'Innodb_row_lock_waits';
SHOW STATUS LIKE 'Innodb_row_lock_time_avg';

-- 慢查询监控
SHOW STATUS LIKE 'Slow_queries';
```

#### Router性能监控
```bash
# Router连接数
netstat -an | grep -E "(6446|6447)" | wc -l

# Router进程资源使用
top -p $(pgrep mysqlrouter)

# Router日志监控
tail -f /var/log/mysqlrouter/mysqlrouter.log | grep -E "(ERROR|WARNING)"
```

### 2. 性能基准测试

#### sysbench基准测试
```bash
# 准备测试数据
sysbench --db-driver=mysql \
         --mysql-host=192.168.1.100 \
         --mysql-port=6446 \
         --mysql-user=root \
         --mysql-password=password \
         --mysql-db=test \
         --tables=10 \
         --table-size=1000000 \
         oltp_read_write prepare

# 混合读写测试
sysbench --db-driver=mysql \
         --mysql-host=192.168.1.100 \
         --mysql-port=6446 \
         --mysql-user=root \
         --mysql-password=password \
         --mysql-db=test \
         --tables=10 \
         --table-size=1000000 \
         --threads=100 \
         --time=300 \
         --report-interval=10 \
         oltp_read_write run

# 只读测试
sysbench --db-driver=mysql \
         --mysql-host=192.168.1.100 \
         --mysql-port=6447 \
         --mysql-user=root \
         --mysql-password=password \
         --mysql-db=test \
         --tables=10 \
         --table-size=1000000 \
         --threads=200 \
         --time=300 \
         oltp_read_only run
```

#### 预期性能指标

| 测试类型 | 8核32G配置 | 32核64G配置 | 备注 |
|----------|------------|-------------|------|
| **读QPS** | 15K-20K | 40K-50K | 单节点 |
| **写QPS** | 3K-5K | 8K-12K | 单节点 |
| **混合TPS** | 2K-3K | 5K-8K | 集群总计 |
| **连接延迟** | <5ms | <3ms | 95百分位 |

### 3. 故障排除

#### 常见性能问题

**1. 连接数耗尽**
```bash
# 检查当前连接数
mysql -e "SHOW PROCESSLIST;" | wc -l

# 检查连接来源
mysql -e "SELECT SUBSTRING_INDEX(host, ':', 1) as client_ip, COUNT(*) as connections 
FROM information_schema.processlist 
GROUP BY client_ip ORDER BY connections DESC;"

# 解决方案：
# - 优化应用连接池配置
# - 增加max_connections
# - 检查连接泄漏
```

**2. 慢查询过多**
```sql
-- 查看慢查询统计
SHOW STATUS LIKE 'Slow_queries';

-- 分析慢查询日志
-- tail -100 /var/log/mysql/slow.log

-- 优化建议：
-- 1. 添加合适索引
-- 2. 重写查询语句
-- 3. 分表分库
```

**3. 锁等待严重**
```sql
-- 查看锁等待情况
SELECT * FROM information_schema.INNODB_LOCKS;
SELECT * FROM information_schema.INNODB_LOCK_WAITS;

-- 优化建议：
-- 1. 缩短事务时间
-- 2. 避免大事务
-- 3. 优化查询顺序
```

## 🚀 配置管理与部署

### 自动化配置切换

```bash
# 使用配置管理器
./scripts/config_manager.sh --list                    # 查看可用配置
./scripts/config_manager.sh --current                 # 查看当前配置
./scripts/config_manager.sh --switch original-10k # 切换到历史高连接配置

# 硬件升级
./scripts/upgrade_hardware_profile.sh --profile original-10k --apply

# 应用配置
ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/site.yml
```

### 分环境配置

#### 开发环境配置
```yaml
# inventory/dev.yml
mysql_hardware_profile: "development"
mysql_max_connections: 200
router_max_connections: 1000
```

#### 测试环境配置
```yaml
# inventory/test.yml
mysql_hardware_profile: "standard"
mysql_max_connections: 1000
router_max_connections: 5000
```

#### 生产环境配置
```yaml
# inventory/prod.yml
mysql_hardware_profile: "8c32g_optimized"
mysql_max_connections: 4000
router_max_connections: 30000
```

## 📈 扩展规划

### 垂直扩展路径

| 阶段 | CPU | 内存 | 连接数 | 适用场景 |
|------|-----|------|--------|----------|
| **当前** | 8C | 32G | 4K/节点 | 中等规模 |
| **升级1** | 16C | 64G | 8K/节点 | 大规模 |
| **升级2** | 32C | 128G | 15K/节点 | 超大规模 |

### 水平扩展策略

#### 分片架构
```
应用程序
    ↓
分片代理 (ShardingSphere/Vitess)
    ↓
多个InnoDB Cluster (按业务/数据分片)
```

#### 读写分离扩展
```
应用程序
    ↓
读写分离中间件
    ↓
写入：InnoDB Cluster (主)
读取：InnoDB Cluster (从) + 只读实例
```

现在你拥有了完整的MySQL高并发优化配置方案！结合 **[内核优化最佳实践](MYSQL_KERNEL_BEST_PRACTICES.md)** 文档，可以实现完整的生产级优化部署。🚀
