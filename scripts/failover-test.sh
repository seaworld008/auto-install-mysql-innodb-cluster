#!/bin/bash

# MySQL InnoDB Cluster 故障转移测试脚本
# 使用方法: ./failover-test.sh [primary_host] [cluster_user] [cluster_password]

PRIMARY_HOST=${1:-"192.168.1.10"}
CLUSTER_USER=${2:-"clusteradmin"}
CLUSTER_PASSWORD=${3:-"Clust3rP@ss!"}
CLUSTER_NAME=${4:-"prodCluster"}

echo "=== MySQL InnoDB Cluster 故障转移测试 ==="
echo "主节点: $PRIMARY_HOST"
echo "集群名称: $CLUSTER_NAME"
echo "测试时间: $(date)"
echo

# 获取当前主节点
echo "1. 获取当前主节点信息:"
CURRENT_PRIMARY=$(mysqlsh --uri ${CLUSTER_USER}:${CLUSTER_PASSWORD}@${PRIMARY_HOST}:3306 \
  -e "var cluster = dba.getCluster('${CLUSTER_NAME}'); var status = cluster.status(); for (var instance in status.defaultReplicaSet.topology) { if (status.defaultReplicaSet.topology[instance].mode == 'R/W') { print(instance); break; } }" 2>/dev/null)

echo "当前主节点: $CURRENT_PRIMARY"

# 检查集群状态
echo
echo "2. 故障转移前集群状态:"
mysqlsh --uri ${CLUSTER_USER}:${CLUSTER_PASSWORD}@${PRIMARY_HOST}:3306 \
  -e "var cluster = dba.getCluster('${CLUSTER_NAME}'); print('集群状态: ' + cluster.status()['defaultReplicaSet']['status'])" 2>/dev/null

# 模拟主节点故障（停止MySQL服务）
echo
echo "3. 模拟主节点故障（需要手动在主节点执行: systemctl stop mysqld）"
echo "请在另一个终端执行以下命令来模拟故障:"
echo "ssh root@${CURRENT_PRIMARY%:*} 'systemctl stop mysqld'"
echo
read -p "故障模拟完成后，按回车键继续..."

# 等待故障检测
echo
echo "4. 等待集群检测故障并进行自动故障转移..."
sleep 30

# 检查故障转移后的状态
echo
echo "5. 故障转移后集群状态:"
# 尝试连接其他节点
for host in 192.168.1.11 192.168.1.12; do
    echo "尝试连接节点 $host..."
    if mysqlsh --uri ${CLUSTER_USER}:${CLUSTER_PASSWORD}@${host}:3306 \
      -e "var cluster = dba.getCluster('${CLUSTER_NAME}'); cluster.status()" 2>/dev/null; then
        echo "成功连接到 $host"
        break
    fi
done

# 获取新的主节点
echo
echo "6. 获取新的主节点信息:"
NEW_PRIMARY=$(mysqlsh --uri ${CLUSTER_USER}:${CLUSTER_PASSWORD}@${host}:3306 \
  -e "var cluster = dba.getCluster('${CLUSTER_NAME}'); var status = cluster.status(); for (var instance in status.defaultReplicaSet.topology) { if (status.defaultReplicaSet.topology[instance].mode == 'R/W') { print(instance); break; } }" 2>/dev/null)

echo "新的主节点: $NEW_PRIMARY"

echo
echo "7. 故障转移测试完成"
echo "原主节点: $CURRENT_PRIMARY"
echo "新主节点: $NEW_PRIMARY"
echo
echo "恢复原主节点的步骤:"
echo "1. 启动原主节点MySQL服务: ssh root@${CURRENT_PRIMARY%:*} 'systemctl start mysqld'"
echo "2. 将原主节点重新加入集群:"
echo "   mysqlsh --uri ${CLUSTER_USER}:${CLUSTER_PASSWORD}@${NEW_PRIMARY%:*}:3306 -e \"var cluster = dba.getCluster('${CLUSTER_NAME}'); cluster.rejoinInstance('${CURRENT_PRIMARY}')\""

echo
echo "=== 测试完成 ===" 