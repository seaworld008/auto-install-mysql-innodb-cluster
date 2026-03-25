#!/bin/bash
set -euo pipefail
INV="${1:-inventory/hosts-ha-reference.yml}"

read_var_from_inventory() {
    local var_name="$1"
    if command -v ansible-inventory >/dev/null 2>&1; then
        ansible-inventory -i "$INV" --list 2>/dev/null | python - "$var_name" << 'PY'
import sys, json
var_name = sys.argv[1]
data = json.load(sys.stdin)
value = data.get("all", {}).get("vars", {}).get(var_name, "")
print(value if value is not None else "")
PY
    else
        python - "$var_name" << 'PY'
import sys, yaml, pathlib
var_name = sys.argv[1]
data = yaml.safe_load(pathlib.Path("inventory/group_vars/all.yml").read_text(encoding="utf-8"))
value = data.get(var_name, "")
print(value if value is not None else "")
PY
    fi
}

MYSQL_CLUSTER_USER="${MYSQL_CLUSTER_USER:-clusteradmin}"
MYSQL_CLUSTER_PASSWORD="${MYSQL_CLUSTER_PASSWORD:-Clust3rP@ss!}"
MYSQL_CLUSTER_NAME="${MYSQL_CLUSTER_NAME:-prodCluster}"
MYSQL_PORT="${MYSQL_PORT:-$(read_var_from_inventory mysql_port)}"
MYSQL_ROUTER_PORT="${MYSQL_ROUTER_PORT:-$(read_var_from_inventory mysql_router_port)}"
MYSQL_ROUTER_RO_PORT="${MYSQL_ROUTER_RO_PORT:-$(read_var_from_inventory mysql_router_ro_port)}"
HAPROXY_RW_PORT="${HAPROXY_RW_PORT:-$(read_var_from_inventory haproxy_mysql_rw_port)}"
HAPROXY_RO_PORT="${HAPROXY_RO_PORT:-$(read_var_from_inventory haproxy_mysql_ro_port)}"
HAPROXY_RWSPLIT_PORT="${HAPROXY_RWSPLIT_PORT:-$(read_var_from_inventory haproxy_mysql_rwsplit_port)}"
MYSQL_ROUTER_RWSPLIT_PORT="${MYSQL_ROUTER_RWSPLIT_PORT:-$(read_var_from_inventory mysql_router_rwsplit_port)}"
KEEPALIVED_VIP="${KEEPALIVED_VIP:-$(read_var_from_inventory keepalived_vip)}"

echo "[1/4] 预检查"
ANSIBLE_STDOUT_CALLBACK=default ansible-playbook -i "$INV" playbooks/preflight-ha.yml

echo "[2/4] MySQL Cluster 状态"
ansible mysql_primary -i "$INV" -m shell -a "mysqlsh --uri ${MYSQL_CLUSTER_USER}:${MYSQL_CLUSTER_PASSWORD}@127.0.0.1:${MYSQL_PORT} -e \"var c=dba.getCluster('${MYSQL_CLUSTER_NAME}'); print(c.status()['defaultReplicaSet']['status'])\"" || true

echo "[3/4] Router 端口检查"
ansible mysql_router -i "$INV" -m shell -a "ss -lntp | egrep ':${MYSQL_ROUTER_PORT}|:${MYSQL_ROUTER_RO_PORT}|:${MYSQL_ROUTER_RWSPLIT_PORT}'" || true

echo "[4/4] HAProxy/Keepalived 检查"
ansible haproxy_lb -i "$INV" -m shell -a "systemctl is-active haproxy keepalived && ss -lntp | egrep ':${HAPROXY_RW_PORT}|:${HAPROXY_RO_PORT}|:${HAPROXY_RWSPLIT_PORT}' && ip a | grep '${KEEPALIVED_VIP}' || true"
