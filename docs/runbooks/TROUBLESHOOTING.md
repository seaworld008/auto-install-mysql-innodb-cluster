# MySQL InnoDB Cluster 故障排除指南

## 常见问题和解决方案

### 1. 安装阶段问题

#### 问题：无法下载MySQL YUM仓库
```
错误: 无法连接到 dev.mysql.com
```

**解决方案：**
- 检查网络连接
- 配置代理（如果需要）
- 手动下载RPM包到 `files/mysql-repo/` 目录

#### 问题：架构不匹配
```
错误: 没有可用的包 mysql-community-server
```

**解决方案：**
- 检查系统架构：`uname -m`
- 确认 `inventory/group_vars/all.yml` 中的架构映射正确
- 对于ARM64系统，确保使用正确的仓库

### 2. 集群配置问题

#### 问题：节点无法加入集群
```
错误: Group Replication failed to start
```

**解决方案：**
1. 检查网络连通性：
   ```bash
   # 在每个节点上测试
   telnet <other_node_ip> 33061
   ```

2. 检查防火墙设置：
   ```bash
   firewall-cmd --list-ports
   # 应该包含 3306/tcp, 33061/tcp, 33062/tcp
   ```

3. 检查MySQL配置：
   ```bash
   mysql -u root -p -e "SHOW VARIABLES LIKE 'group_replication%'"
   ```

#### 问题：集群状态显示为 "NO_QUORUM"
```
"status": "NO_QUORUM"
```

**解决方案：**
1. 检查有多少节点在线：
   ```bash
   mysqlsh --uri clusteradmin@primary_host -e "dba.getCluster().status()"
   ```

2. 如果只有一个节点在线，强制重新配置：
   ```bash
   mysqlsh --uri clusteradmin@primary_host -e "dba.getCluster().forceQuorumUsingPartitionOf('primary_host:3306')"
   ```

### 3. 网络和连接问题

#### 问题：SSH连接失败
```
错误: UNREACHABLE! => {"changed": false, "msg": "Failed to connect to the host"}
```

**解决方案：**
1. 检查SSH密钥配置
2. 验证主机IP地址
3. 确认SSH服务运行状态
4. 检查防火墙SSH端口（22）

#### 问题：MySQL连接被拒绝
```
错误: Can't connect to MySQL server on 'host' (111)
```

**解决方案：**
1. 检查MySQL服务状态：
   ```bash
   systemctl status mysqld
   ```

2. 检查MySQL端口监听：
   ```bash
   netstat -tlnp | grep 3306
   ```

3. 检查MySQL错误日志：
   ```bash
   tail -f /var/log/mysql/mysqld.log
   ```

### 4. 性能问题

#### 问题：集群同步延迟高
**解决方案：**
1. 检查网络延迟：
   ```bash
   ping <other_nodes>
   ```

2. 调整InnoDB缓冲池大小：
   ```ini
   innodb_buffer_pool_size = 2G  # 根据内存调整
   ```

3. 检查磁盘I/O性能：
   ```bash
   iostat -x 1
   ```

### 5. MySQL Router问题

#### 问题：Router无法连接到集群
```
错误: Unable to connect to the metadata server
```

**解决方案：**
1. 检查集群状态
2. 重新引导Router：
   ```bash
   mysqlrouter --bootstrap clusteradmin@primary_host --force
   ```

3. 检查Router配置文件：
   ```bash
   cat /var/lib/mysqlrouter/mysqlrouter.conf
   ```

### 6. 日志分析

#### 重要日志文件位置：
- MySQL错误日志：`/var/log/mysql/mysqld.log`
- MySQL慢查询日志：`/var/log/mysql/mysql-slow.log`
- MySQL Router日志：`/var/log/mysqlrouter/mysqlrouter.log`
- Ansible日志：运行时输出

#### 常用调试命令：
```bash
# 检查集群状态
mysqlsh --uri clusteradmin@host -e "dba.getCluster().status()"

# 检查集群拓扑
mysqlsh --uri clusteradmin@host -e "dba.getCluster().describe()"

# 检查实例状态
mysqlsh --uri clusteradmin@host -e "dba.checkInstanceConfiguration('host:3306')"

# 检查Group Replication状态
mysql -u root -p -e "SELECT * FROM performance_schema.replication_group_members"
```

### 7. 恢复操作

#### 重新启动整个集群：
1. 停止所有MySQL服务
2. 在主节点启动MySQL
3. 重新引导集群：
   ```bash
   mysqlsh --uri clusteradmin@primary -e "dba.rebootClusterFromCompleteOutage()"
   ```

#### 重新加入故障节点：
```bash
mysqlsh --uri clusteradmin@primary -e "dba.getCluster().rejoinInstance('failed_node:3306')"
```

### 8. 监控和维护

#### 定期检查项目：
- 集群状态健康检查
- 磁盘空间使用情况
- 内存使用情况
- 网络连接状态
- 备份策略执行

#### 自动化监控脚本：
使用提供的 `scripts/cluster-status.sh` 脚本进行定期检查。

### 9. 联系支持

如果问题仍然存在：
1. 收集相关日志文件
2. 记录错误信息和重现步骤
3. 检查MySQL官方文档
4. 在MySQL社区论坛寻求帮助

### 10. 预防措施

- 定期备份数据
- 监控系统资源使用情况
- 保持MySQL版本更新
- 定期测试故障转移流程
- 文档化所有配置更改 