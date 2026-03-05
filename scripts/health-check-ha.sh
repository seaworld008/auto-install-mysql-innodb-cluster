#!/bin/bash
set -euo pipefail
INV="${1:-inventory/hosts-ha-reference.yml}"

echo "[1/4] 预检查"
ANSIBLE_STDOUT_CALLBACK=default ansible-playbook -i "$INV" playbooks/preflight-ha.yml

echo "[2/4] MySQL Cluster 状态"
ansible mysql_primary -i "$INV" -m shell -a "mysqlsh --uri ${MYSQL_CLUSTER_USER:-clusteradmin}:${MYSQL_CLUSTER_PASSWORD:-Clust3rP@ss!}@127.0.0.1:${MYSQL_PORT:-3306} -e \"var c=dba.getCluster('${MYSQL_CLUSTER_NAME:-prodCluster}'); print(c.status()['defaultReplicaSet']['status'])\"" || true

echo "[3/4] Router 端口检查"
ansible mysql_router -i "$INV" -m shell -a "ss -lntp | egrep ':6446|:6447'" || true

echo "[4/4] HAProxy/Keepalived 检查"
ansible haproxy_lb -i "$INV" -m shell -a "systemctl is-active haproxy keepalived && ip a | grep '${KEEPALIVED_VIP:-192.168.1.100}' || true"
