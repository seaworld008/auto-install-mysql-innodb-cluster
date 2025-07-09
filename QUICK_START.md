# 🚀 MySQL InnoDB Cluster 快速开始

## 一键部署命令（推荐）

```bash
# 1. 克隆项目
git clone <this-repo>
cd 09-outo-install-mysql-innodb-cluster

# 2. 配置服务器IP（修改为您的实际IP）
vim inventory/hosts-with-dedicated-routers.yml

# 3. 一键部署（包含用户配置：关闭swap + /data/mysql）
./scripts/deploy_dedicated_routers.sh --production-ready
```

## 📋 您的配置特性

✅ **Swap完全关闭** (vm.swappiness=0)  
✅ **数据目录自定义** (/data/mysql)  
✅ **内核优化** (行业最佳实践)  
✅ **60K前端连接能力**  
✅ **12K后端连接支持**  

## 🎯 连接信息

- **读写**: `mysql://user:password@192.168.1.100:6446/database`
- **只读**: `mysql://user:password@192.168.1.100:6447/database`  
- **监控**: `http://192.168.1.100:8404/stats`

## 📞 快速验证

```bash
# 验证swap状态
free -h && sysctl vm.swappiness

# 验证数据目录
ls -la /data/mysql

# 测试MySQL连接
mysql -h 192.168.1.100 -P 6446 -u root -p -e "SELECT @@hostname;"
```

🎉 **部署完成！开始使用您的高性能MySQL集群吧！**

---
*详细文档请参考: [FINAL_DEPLOYMENT_GUIDE.md](FINAL_DEPLOYMENT_GUIDE.md)* 