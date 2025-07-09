# 用户配置更改说明

## 🎯 配置更改概览

根据您的要求，已完成以下配置更改：

1. **完全关闭swap内存** - 设置 `vm.swappiness=0` 并永久禁用
2. **修改MySQL数据目录** - 从 `/var/lib/mysql` 改为 `/data/mysql`

## 📋 已修改的文件

### 1. 内核优化脚本
- **文件**: `scripts/optimize_mysql_kernel_stable.sh`
- **更改**: 
  - `vm.swappiness` 从 `1` 改为 `0`（完全关闭swap）
  - 添加了立即关闭swap分区的命令
  - 自动注释 `/etc/fstab` 中的swap条目
  - 更新验证函数显示swap状态

### 2. MySQL配置文件
- **文件**: `inventory/group_vars/all.yml`
- **文件**: `inventory/group_vars/all-8c32g-optimized.yml` 
- **文件**: `inventory/group_vars/all-original-10k-config.yml`
- **更改**: `mysql_datadir: "/data/mysql"`

### 3. MySQL配置模板
- **文件**: `roles/mysql-server/templates/my.cnf.j2`
- **更改**: 
  - `datadir = /data/mysql`
  - `socket = /data/mysql/mysql.sock`（服务端和客户端）

### 4. MySQL安装playbook
- **文件**: `playbooks/install-mysql.yml`
- **更改**: 添加创建 `/data/mysql` 目录的任务

## 🚀 配置应用方法

### 方法一：使用专用配置脚本（推荐）

```bash
# 完整应用所有配置
sudo ./scripts/apply_user_configs.sh

# 或分别应用：
sudo ./scripts/apply_user_configs.sh --swap-only    # 仅关闭swap
sudo ./scripts/apply_user_configs.sh --datadir-only # 仅修改数据目录

# 验证配置
sudo ./scripts/apply_user_configs.sh --verify-only
```

### 方法二：手动应用（如果脚本不可用）

#### 步骤1：关闭swap
```bash
# 立即关闭swap
sudo swapoff -a

# 永久禁用swap
sudo cp /etc/fstab /etc/fstab.backup
sudo sed -i 's/^[^#].*swap.*/#&/' /etc/fstab

# 设置内核参数
echo 'vm.swappiness = 0' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

#### 步骤2：创建MySQL数据目录
```bash
# 创建数据目录
sudo mkdir -p /data/mysql
sudo chown mysql:mysql /data/mysql
sudo chmod 750 /data/mysql
```

#### 步骤3：迁移现有数据（如果有）
```bash
# 如果已有MySQL数据
sudo systemctl stop mysqld
sudo rsync -av /var/lib/mysql/ /data/mysql/
sudo mv /var/lib/mysql /var/lib/mysql.backup
sudo chown -R mysql:mysql /data/mysql
```

### 方法三：重新部署（推荐用于新环境）

```bash
# 使用更新的配置重新部署
./scripts/deploy_dedicated_routers.sh --production-ready
```

## ✅ 验证配置

### 验证swap状态
```bash
# 检查swap是否关闭
free -h
swapon --show  # 应该没有输出

# 检查内核参数
sysctl vm.swappiness  # 应该显示 0

# 检查fstab
grep swap /etc/fstab  # 所有swap行应该被注释
```

### 验证MySQL数据目录
```bash
# 检查目录是否存在
ls -la /data/mysql

# 检查MySQL配置
grep datadir /etc/my.cnf  # 应该显示 /data/mysql
```

## 📊 配置对比

| 配置项 | 修改前 | 修改后 | 说明 |
|--------|--------|--------|------|
| **Swap设置** | `vm.swappiness = 1` | `vm.swappiness = 0` | 完全关闭swap |
| **Swap状态** | 可能启用 | 完全关闭 | 立即关闭并永久禁用 |
| **MySQL数据目录** | `/var/lib/mysql` | `/data/mysql` | 用户指定路径 |
| **Socket路径** | `/var/lib/mysql/mysql.sock` | `/data/mysql/mysql.sock` | 跟随数据目录 |

## 🔧 配置优势

### 关闭swap的好处
- **性能提升**: 消除swap带来的延迟
- **稳定性增强**: 避免MySQL因swap导致的性能抖动
- **内存利用**: 强制MySQL完全使用物理内存
- **延迟一致**: 保证查询响应时间的一致性

### 自定义数据目录的好处
- **存储灵活性**: 可以使用专用的高性能存储
- **容量规划**: 独立的存储空间管理
- **备份策略**: 便于数据备份和恢复
- **性能优化**: 可以针对数据目录进行存储优化

## ⚠️ 重要注意事项

### 关于Swap
1. **内存充足性**: 确保32GB内存足够支撑4000连接的MySQL负载
2. **监控重要性**: 必须监控内存使用率，避免OOM
3. **紧急恢复**: 如果出现内存不足，可以临时启用swap：
   ```bash
   sudo swapon /path/to/swap/file
   ```

### 关于数据目录
1. **权限安全**: 确保只有mysql用户可以访问数据目录
2. **存储性能**: `/data/mysql` 应该在高性能存储上（SSD推荐）
3. **备份策略**: 新的数据目录路径需要更新备份脚本
4. **磁盘空间**: 确保 `/data` 分区有足够的空间

## 🛠️ 故障排除

### Swap相关问题
```bash
# 如果内存不足出现问题
sudo dmesg | grep -i "out of memory"  # 检查OOM记录

# 临时启用swap（紧急情况）
sudo swapon -a

# 恢复swap配置
sudo sed -i 's/^#.*swap//' /etc/fstab  # 取消注释
```

### 数据目录问题
```bash
# 检查目录权限
ls -la /data/mysql

# 修复权限
sudo chown -R mysql:mysql /data/mysql
sudo chmod -R 750 /data/mysql

# 检查MySQL启动日志
sudo journalctl -u mysqld -f
```

## 📞 技术支持

如果在应用配置过程中遇到问题：

1. **查看日志**: 脚本会自动备份原配置到 `/root/mysql_config_backup_*`
2. **验证配置**: 使用 `sudo ./scripts/apply_user_configs.sh --verify-only`
3. **回滚操作**: 可以从备份目录恢复原配置
4. **重新部署**: 在新环境中直接使用更新的配置部署

---

**配置更改完成！您的MySQL环境现在将使用 `/data/mysql` 作为数据目录，并完全关闭swap以获得最佳性能。** 🚀 