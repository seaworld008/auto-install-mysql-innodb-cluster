#!/bin/bash

# MySQL InnoDB Cluster HA inventory 配置向导
# 生成当前主线推荐的 3 MySQL + 2 Router + 2 HAProxy/Keepalived inventory。

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DEFAULT_INVENTORY="inventory/hosts-with-dedicated-routers.yml"
INVENTORY_FILE="${1:-$DEFAULT_INVENTORY}"
BACKUP_FILE="${INVENTORY_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

prompt_host() {
    local prefix="$1"
    local label="$2"
    local default_user="${3:-root}"

    echo -e "${GREEN}=== ${label} ===${NC}"
    read -r -p "请输入 ${label} 的 IP 地址: " "${prefix}_IP"
    read -r -p "请输入 ${label} 的 SSH 用户名 [${default_user}]: " "${prefix}_USER"
    local user_var="${prefix}_USER"
    if [[ -z "${!user_var}" ]]; then
        printf -v "$user_var" "%s" "$default_user"
    fi
    read -r -s -p "请输入 ${label} 的 SSH 密码: " "${prefix}_PASS"
    echo
    echo
}

confirm_not_empty() {
    local var_name="$1"
    local label="$2"
    if [[ -z "${!var_name}" ]]; then
        echo -e "${RED}错误: ${label} 不能为空${NC}" >&2
        exit 1
    fi
}

echo "=========================================="
echo "MySQL InnoDB Cluster HA inventory 配置向导"
echo "=========================================="
echo
echo -e "${YELLOW}当前主线最小 HA 拓扑:${NC}"
echo "- MySQL: 3 节点"
echo "- MySQL Router: 2 节点"
echo "- HAProxy + Keepalived: 2 节点"
echo
echo "输出文件: ${INVENTORY_FILE}"
echo

prompt_host MYSQL1 "MySQL 主节点"
prompt_host MYSQL2 "MySQL 从节点 1"
prompt_host MYSQL3 "MySQL 从节点 2"
prompt_host ROUTER1 "MySQL Router 节点 1"
prompt_host ROUTER2 "MySQL Router 节点 2"
prompt_host HAPROXY1 "HAProxy/Keepalived 节点 1"
prompt_host HAPROXY2 "HAProxy/Keepalived 节点 2"

read -r -p "请输入 Keepalived VIP，例如 192.168.1.100: " KEEPALIVED_VIP
confirm_not_empty KEEPALIVED_VIP "Keepalived VIP"

for var in MYSQL1_IP MYSQL2_IP MYSQL3_IP ROUTER1_IP ROUTER2_IP HAPROXY1_IP HAPROXY2_IP; do
    confirm_not_empty "$var" "$var"
done

echo -e "${YELLOW}请确认拓扑:${NC}"
cat <<EOF
MySQL:
  - mysql-node1: ${MYSQL1_USER}@${MYSQL1_IP}
  - mysql-node2: ${MYSQL2_USER}@${MYSQL2_IP}
  - mysql-node3: ${MYSQL3_USER}@${MYSQL3_IP}
Router:
  - mysql-router-1: ${ROUTER1_USER}@${ROUTER1_IP}
  - mysql-router-2: ${ROUTER2_USER}@${ROUTER2_IP}
HAProxy/Keepalived:
  - haproxy-1: ${HAPROXY1_USER}@${HAPROXY1_IP}
  - haproxy-2: ${HAPROXY2_USER}@${HAPROXY2_IP}
VIP:
  - ${KEEPALIVED_VIP}
EOF
echo

read -r -p "确认写入 inventory? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo -e "${YELLOW}已取消${NC}"
    exit 1
fi

if [[ -f "$INVENTORY_FILE" ]]; then
    cp "$INVENTORY_FILE" "$BACKUP_FILE"
    echo -e "${YELLOW}原 inventory 已备份为: ${BACKUP_FILE}${NC}"
fi

cat > "$INVENTORY_FILE" <<EOF
all:
  children:
    mysql_cluster:
      children:
        mysql_primary:
          hosts:
            mysql-node1:
              ansible_host: ${MYSQL1_IP}
              ansible_port: 22
              ansible_user: ${MYSQL1_USER}
              ansible_ssh_pass: "${MYSQL1_PASS}"
              mysql_server_id: 1
              mysql_role: primary
        mysql_secondary:
          hosts:
            mysql-node2:
              ansible_host: ${MYSQL2_IP}
              ansible_port: 22
              ansible_user: ${MYSQL2_USER}
              ansible_ssh_pass: "${MYSQL2_PASS}"
              mysql_server_id: 2
              mysql_role: secondary
            mysql-node3:
              ansible_host: ${MYSQL3_IP}
              ansible_port: 22
              ansible_user: ${MYSQL3_USER}
              ansible_ssh_pass: "${MYSQL3_PASS}"
              mysql_server_id: 3
              mysql_role: secondary

    mysql_router:
      hosts:
        mysql-router-1:
          ansible_host: ${ROUTER1_IP}
          ansible_port: 22
          ansible_user: ${ROUTER1_USER}
          ansible_ssh_pass: "${ROUTER1_PASS}"
          router_role: "primary"
          router_priority: 100
          router_cpu_cores: 4
          router_memory_gb: 8
          router_disk_type: "SSD"
        mysql-router-2:
          ansible_host: ${ROUTER2_IP}
          ansible_port: 22
          ansible_user: ${ROUTER2_USER}
          ansible_ssh_pass: "${ROUTER2_PASS}"
          router_role: "secondary"
          router_priority: 90
          router_cpu_cores: 4
          router_memory_gb: 8
          router_disk_type: "SSD"

    haproxy_lb:
      hosts:
        haproxy-1:
          ansible_host: ${HAPROXY1_IP}
          ansible_port: 22
          ansible_user: ${HAPROXY1_USER}
          ansible_ssh_pass: "${HAPROXY1_PASS}"
          keepalived_priority: 150
        haproxy-2:
          ansible_host: ${HAPROXY2_IP}
          ansible_port: 22
          ansible_user: ${HAPROXY2_USER}
          ansible_ssh_pass: "${HAPROXY2_PASS}"
          keepalived_priority: 100

  vars:
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
    ansible_python_interpreter: /usr/bin/python3
    keepalived_vip: "${KEEPALIVED_VIP}"
EOF

echo -e "${GREEN}inventory 已生成: ${INVENTORY_FILE}${NC}"
echo
echo -e "${YELLOW}下一步必须先配置 MySQL 密码:${NC}"
echo "  vim inventory/group_vars/all.yml"
echo
echo "至少替换:"
echo "  - mysql_root_password"
echo "  - mysql_cluster_password"
echo "  - mysql_replication_password"
echo

if command -v ansible >/dev/null 2>&1; then
    read -r -p "是否现在执行 ansible ping 连通性检查? (y/n): " RUN_PING
    if [[ "$RUN_PING" == "y" || "$RUN_PING" == "Y" ]]; then
        ansible all -i "$INVENTORY_FILE" -m ping
    fi
else
    echo -e "${YELLOW}未检测到 ansible，跳过连通性检查。${NC}"
fi

read -r -p "MySQL 密码已配置完成，并立即执行 preflight? (y/n): " RUN_PREFLIGHT
if [[ "$RUN_PREFLIGHT" == "y" || "$RUN_PREFLIGHT" == "Y" ]]; then
    ./scripts/deploy_dedicated_routers.sh --check-prereq -i "$INVENTORY_FILE"
else
    echo "稍后可运行:"
    echo "  ./scripts/deploy_dedicated_routers.sh --check-prereq -i ${INVENTORY_FILE}"
    echo "  ./scripts/deploy_dedicated_routers.sh --production-ready -i ${INVENTORY_FILE}"
fi
