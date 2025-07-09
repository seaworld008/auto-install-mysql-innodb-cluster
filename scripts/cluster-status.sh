#!/bin/bash

# MySQL InnoDB Cluster 状态检查脚本
# 使用方法: ./cluster-status.sh [primary_host] [cluster_user] [cluster_password]

PRIMARY_HOST=${1:-"192.168.1.10"}
CLUSTER_USER=${2:-"clusteradmin"}
CLUSTER_PASSWORD=${3:-"Clust3rP@ss!"}
CLUSTER_NAME=${4:-"prodCluster"}

echo "=== MySQL InnoDB Cluster 状态检查 ==="
echo "主节点: $PRIMARY_HOST"
echo "集群名称: $CLUSTER_NAME"
echo "检查时间: $(date)"
echo

# 检查集群整体状态
echo "1. 集群整体状态:"
mysqlsh --uri ${CLUSTER_USER}:${CLUSTER_PASSWORD}@${PRIMARY_HOST}:3306 \
  -e "var cluster = dba.getCluster('${CLUSTER_NAME}'); cluster.status()" 2>/dev/null

echo
echo "2. 集群拓扑信息:"
mysqlsh --uri ${CLUSTER_USER}:${CLUSTER_PASSWORD}@${PRIMARY_HOST}:3306 \
  -e "var cluster = dba.getCluster('${CLUSTER_NAME}'); cluster.describe()" 2>/dev/null

echo
echo "3. 集群健康检查:"
mysqlsh --uri ${CLUSTER_USER}:${CLUSTER_PASSWORD}@${PRIMARY_HOST}:3306 \
  -e "var cluster = dba.getCluster('${CLUSTER_NAME}'); print('集群状态: ' + cluster.status()['defaultReplicaSet']['status'])" 2>/dev/null

echo
echo "4. 各节点连接测试:"
for host in 192.168.1.10 192.168.1.11 192.168.1.12; do
    echo -n "测试 $host:3306 ... "
    if mysql -h $host -P 3306 -u ${CLUSTER_USER} -p${CLUSTER_PASSWORD} -e "SELECT 1" >/dev/null 2>&1; then
        echo "连接正常"
    else
        echo "连接失败"
    fi
done

echo
echo "=== 检查完成 ===" 