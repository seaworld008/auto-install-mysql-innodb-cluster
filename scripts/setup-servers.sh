#!/bin/bash

# MySQL InnoDB Cluster HA inventory 配置向导
# 生成当前主线推荐的 3 MySQL + 2 Router + 2 HAProxy/Keepalived 本地 inventory。

set -euo pipefail
umask 077

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DEFAULT_INVENTORY="inventory/hosts.local.yml"
INVENTORY_FILE="${1:-$DEFAULT_INVENTORY}"
INVENTORY_DISPLAY="$INVENTORY_FILE"
TEMP_FILE=""
SSH_PRIVATE_KEY_PATH=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"

cleanup() {
    if [[ -n "$TEMP_FILE" && -f "$TEMP_FILE" ]]; then
        rm -f "$TEMP_FILE"
    fi
    unset MYSQL1_PASS MYSQL2_PASS MYSQL3_PASS
    unset ROUTER1_PASS ROUTER2_PASS HAPROXY1_PASS HAPROXY2_PASS
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM

fail() {
    echo -e "${RED}错误: $1${NC}" >&2
    exit 1
}

yaml_quote() {
    local value="$1"
    printf "'"
    printf "%s" "$value" | sed "s/'/''/g"
    printf "'"
}

confirm_not_empty() {
    local var_name="$1"
    local label="$2"
    if [[ -z "${!var_name}" ]]; then
        fail "${label} 不能为空"
    fi
}

reject_control_characters() {
    local value="$1"
    local label="$2"
    if [[ "$value" =~ [[:cntrl:]] ]]; then
        fail "${label} 不能包含控制字符"
    fi
}

validate_host() {
    local value="$1"
    local label="$2"
    if [[ ! "$value" =~ ^[A-Za-z0-9._:-]+$ ]]; then
        fail "${label} 只能包含字母、数字、点、下划线、连字符或冒号"
    fi
}

validate_user() {
    local value="$1"
    local label="$2"
    if [[ ! "$value" =~ ^[A-Za-z0-9._@-]+$ ]]; then
        fail "${label} 只能包含字母、数字、点、下划线、@ 或连字符"
    fi
}

validate_ipv4() {
    local value="$1"
    local python_bin=""
    if command -v python3 >/dev/null 2>&1; then
        python_bin="$(command -v python3)"
    elif command -v python >/dev/null 2>&1; then
        python_bin="$(command -v python)"
    else
        fail "验证 Keepalived VIP 需要 python3 或 python"
    fi
    "$python_bin" -c '
import ipaddress
import sys

try:
    address = ipaddress.ip_address(sys.argv[1])
except ValueError:
    raise SystemExit(1)
raise SystemExit(
    address.version != 4
    or address.is_unspecified
    or address.is_loopback
    or address.is_multicast
    or address.is_reserved
)
' "$value" || fail "Keepalived VIP 必须是合法 IPv4 地址"
}

generate_cluster_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen | tr '[:upper:]' '[:lower:]'
        return
    fi
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import uuid; print(uuid.uuid4())'
        return
    fi
    if command -v python >/dev/null 2>&1; then
        python -c 'import uuid; print(uuid.uuid4())'
        return
    fi
    fail "无法生成 Group Replication UUID；需要 uuidgen、python3 或 python"
}

prepare_inventory_target() {
    local output_dir
    local output_name
    local repo_root
    local relative_path

    if [[ "$INVENTORY_FILE" != /* ]]; then
        INVENTORY_FILE="${PROJECT_ROOT}/${INVENTORY_FILE}"
    fi
    output_dir="$(dirname -- "$INVENTORY_FILE")"
    output_name="$(basename -- "$INVENTORY_FILE")"
    mkdir -p "$output_dir"
    output_dir="$(cd "$output_dir" && pwd -P)"
    INVENTORY_FILE="${output_dir}/${output_name}"

    if [[ -L "$INVENTORY_FILE" ]]; then
        fail "拒绝写入符号链接: ${INVENTORY_DISPLAY}"
    fi
    if [[ -e "$INVENTORY_FILE" && ! -f "$INVENTORY_FILE" ]]; then
        fail "目标不是普通文件: ${INVENTORY_DISPLAY}"
    fi

    if repo_root="$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel 2>/dev/null)"; then
        repo_root="$(cd "$repo_root" && pwd -P)"
        if [[ "$INVENTORY_FILE" == "$repo_root/"* ]]; then
            relative_path="${INVENTORY_FILE#"$repo_root"/}"
            if git -C "$repo_root" ls-files --error-unmatch -- "$relative_path" >/dev/null 2>&1; then
                fail "拒绝覆盖 Git 已跟踪的 inventory: ${relative_path}"
            fi
            if ! git -C "$repo_root" check-ignore -q -- "$relative_path"; then
                fail "仓库内输出必须匹配 .gitignore；请使用 inventory/*.local.yml"
            fi
        fi
    fi
}

prompt_private_key() {
    local key_path
    local key_dir
    local key_name

    echo -e "${BLUE}SSH 认证方式${NC}"
    IFS= read -r -p "请输入所有节点共用的 SSH 私钥路径（推荐；留空才逐主机收集密码）: " key_path
    if [[ -z "$key_path" ]]; then
        echo -e "${YELLOW}未提供私钥，将逐主机收集 SSH 密码并仅写入权限 0600 的本地 inventory。${NC}"
        echo
        return
    fi

    reject_control_characters "$key_path" "SSH 私钥路径"
    if [[ "$key_path" == "~/"* ]]; then
        key_path="${HOME}/${key_path:2}"
    elif [[ "$key_path" != /* ]]; then
        key_path="${PWD}/${key_path}"
    fi

    key_dir="$(dirname -- "$key_path")"
    key_name="$(basename -- "$key_path")"
    [[ -d "$key_dir" ]] || fail "SSH 私钥目录不存在: ${key_dir}"
    key_dir="$(cd "$key_dir" && pwd -P)"
    SSH_PRIVATE_KEY_PATH="${key_dir}/${key_name}"

    [[ -f "$SSH_PRIVATE_KEY_PATH" ]] || fail "SSH 私钥不存在: ${SSH_PRIVATE_KEY_PATH}"
    [[ -r "$SSH_PRIVATE_KEY_PATH" ]] || fail "SSH 私钥不可读: ${SSH_PRIVATE_KEY_PATH}"
    echo -e "${GREEN}将使用统一 SSH 私钥，不会收集逐主机密码。${NC}"
    echo
}

prompt_host() {
    local prefix="$1"
    local label="$2"
    local default_user="${3:-root}"
    local ip_var="${prefix}_IP"
    local user_var="${prefix}_USER"
    local pass_var="${prefix}_PASS"

    echo -e "${GREEN}=== ${label} ===${NC}"
    IFS= read -r -p "请输入 ${label} 的 IP 地址或可解析主机名: " "$ip_var"
    confirm_not_empty "$ip_var" "${label} 地址"
    validate_host "${!ip_var}" "${label} 地址"

    IFS= read -r -p "请输入 ${label} 的 SSH 用户名 [${default_user}]: " "$user_var"
    if [[ -z "${!user_var}" ]]; then
        printf -v "$user_var" "%s" "$default_user"
    fi
    validate_user "${!user_var}" "${label} SSH 用户名"

    printf -v "$pass_var" "%s" ""
    if [[ -z "$SSH_PRIVATE_KEY_PATH" ]]; then
        IFS= read -r -s -p "请输入 ${label} 的 SSH 密码: " "$pass_var"
        echo
        confirm_not_empty "$pass_var" "${label} SSH 密码"
        reject_control_characters "${!pass_var}" "${label} SSH 密码"
    fi
    echo
}

render_password_field() {
    local indentation="$1"
    local var_name="$2"
    if [[ -z "$SSH_PRIVATE_KEY_PATH" ]]; then
        printf "%sansible_ssh_pass: !unsafe %s" \
            "$indentation" \
            "$(yaml_quote "${!var_name}")"
    fi
}

render_private_key_field() {
    if [[ -n "$SSH_PRIVATE_KEY_PATH" ]]; then
        printf "    ansible_ssh_private_key_file: !unsafe %s" \
            "$(yaml_quote "$SSH_PRIVATE_KEY_PATH")"
    fi
}

show_host_key_guidance() {
    echo
    echo -e "${YELLOW}SSH host key 校验默认启用，连接前必须先核验 fingerprint。${NC}"
    echo "请对以下每个地址重复执行核验，不能只信任 ssh-keyscan 的输出："
    printf "  - %s\n" \
        "$MYSQL1_IP" "$MYSQL2_IP" "$MYSQL3_IP" \
        "$ROUTER1_IP" "$ROUTER2_IP" \
        "$HAPROXY1_IP" "$HAPROXY2_IP"
    echo
    cat <<'EOF'
示例流程：
  HOST='<节点 IP 或主机名>'
  HOST_KEY_FILE="$(mktemp)"
  ssh-keyscan -H -t ed25519 "$HOST" >"$HOST_KEY_FILE"
  ssh-keygen -lf "$HOST_KEY_FILE"

先通过云控制台、机房控制台或管理员提供的可信渠道逐一比对 fingerprint。
确认一致后才写入 known_hosts：
  install -d -m 0700 "$HOME/.ssh"
  cat "$HOST_KEY_FILE" >>"$HOME/.ssh/known_hosts"
  chmod 0600 "$HOME/.ssh/known_hosts"
  rm -f "$HOST_KEY_FILE"
EOF
    echo
}

prepare_inventory_target
MYSQL_GROUP_REPLICATION_UUID="$(generate_cluster_uuid)"
if [[ ! "$MYSQL_GROUP_REPLICATION_UUID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    fail "生成的 Group Replication UUID 格式无效"
fi

echo "=========================================="
echo "MySQL InnoDB Cluster HA inventory 配置向导"
echo "=========================================="
echo
echo -e "${YELLOW}当前主线最小 HA 拓扑:${NC}"
echo "- MySQL: 3 节点"
echo "- MySQL Router: 2 节点"
echo "- HAProxy + Keepalived: 2 节点"
echo
echo "输出文件: ${INVENTORY_DISPLAY}"
echo "文件权限: 0600"
echo

prompt_private_key
prompt_host MYSQL1 "MySQL 主节点"
prompt_host MYSQL2 "MySQL 从节点 1"
prompt_host MYSQL3 "MySQL 从节点 2"
prompt_host ROUTER1 "MySQL Router 节点 1"
prompt_host ROUTER2 "MySQL Router 节点 2"
prompt_host HAPROXY1 "HAProxy/Keepalived 节点 1"
prompt_host HAPROXY2 "HAProxy/Keepalived 节点 2"

IFS= read -r -p "请输入 Keepalived VIP，例如 10.20.30.100: " KEEPALIVED_VIP
confirm_not_empty KEEPALIVED_VIP "Keepalived VIP"
validate_ipv4 "$KEEPALIVED_VIP"
if [[ "$KEEPALIVED_VIP" == 192.0.2.* ||
      "$KEEPALIVED_VIP" == 198.51.100.* ||
      "$KEEPALIVED_VIP" == 203.0.113.* ]]; then
    fail "Keepalived VIP 不能使用仓库默认值或文档示例网段"
fi

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
Group Replication UUID:
  - ${MYSQL_GROUP_REPLICATION_UUID}
EOF
echo

IFS= read -r -p "确认写入本地 inventory? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo -e "${YELLOW}已取消${NC}"
    exit 1
fi

if [[ -f "$INVENTORY_FILE" ]]; then
    BACKUP_FILE="$(
        mktemp "${INVENTORY_FILE}.backup.$(date +%Y%m%d_%H%M%S).XXXXXX"
    )"
    cp "$INVENTORY_FILE" "$BACKUP_FILE"
    chmod 0600 "$BACKUP_FILE"
    echo -e "${YELLOW}原 inventory 已备份为: ${BACKUP_FILE}${NC}"
fi

TEMP_FILE="$(mktemp "${INVENTORY_FILE}.tmp.XXXXXX")"
chmod 0600 "$TEMP_FILE"

cat > "$TEMP_FILE" <<EOF
all:
  children:
    mysql_cluster:
      children:
        mysql_primary:
          hosts:
            mysql-node1:
              ansible_host: $(yaml_quote "$MYSQL1_IP")
              ansible_port: 22
              ansible_user: $(yaml_quote "$MYSQL1_USER")
$(render_password_field "              " MYSQL1_PASS)
              mysql_server_id: 1
              mysql_role: 'primary'
        mysql_secondary:
          hosts:
            mysql-node2:
              ansible_host: $(yaml_quote "$MYSQL2_IP")
              ansible_port: 22
              ansible_user: $(yaml_quote "$MYSQL2_USER")
$(render_password_field "              " MYSQL2_PASS)
              mysql_server_id: 2
              mysql_role: 'secondary'
            mysql-node3:
              ansible_host: $(yaml_quote "$MYSQL3_IP")
              ansible_port: 22
              ansible_user: $(yaml_quote "$MYSQL3_USER")
$(render_password_field "              " MYSQL3_PASS)
              mysql_server_id: 3
              mysql_role: 'secondary'

    mysql_router:
      hosts:
        mysql-router-1:
          ansible_host: $(yaml_quote "$ROUTER1_IP")
          ansible_port: 22
          ansible_user: $(yaml_quote "$ROUTER1_USER")
$(render_password_field "          " ROUTER1_PASS)
          router_role: 'primary'
          router_priority: 100
          router_cpu_cores: 4
          router_memory_gb: 8
          router_disk_type: 'SSD'
        mysql-router-2:
          ansible_host: $(yaml_quote "$ROUTER2_IP")
          ansible_port: 22
          ansible_user: $(yaml_quote "$ROUTER2_USER")
$(render_password_field "          " ROUTER2_PASS)
          router_role: 'secondary'
          router_priority: 90
          router_cpu_cores: 4
          router_memory_gb: 8
          router_disk_type: 'SSD'

    haproxy_lb:
      hosts:
        haproxy-1:
          ansible_host: $(yaml_quote "$HAPROXY1_IP")
          ansible_port: 22
          ansible_user: $(yaml_quote "$HAPROXY1_USER")
$(render_password_field "          " HAPROXY1_PASS)
          keepalived_priority: 150
        haproxy-2:
          ansible_host: $(yaml_quote "$HAPROXY2_IP")
          ansible_port: 22
          ansible_user: $(yaml_quote "$HAPROXY2_USER")
$(render_password_field "          " HAPROXY2_PASS)
          keepalived_priority: 100

  vars:
    ansible_ssh_common_args: '-o StrictHostKeyChecking=yes'
$(render_private_key_field)
    ansible_python_interpreter: auto_silent
    keepalived_vip: $(yaml_quote "$KEEPALIVED_VIP")
    mysql_group_replication_group_name_override: $(yaml_quote "$MYSQL_GROUP_REPLICATION_UUID")
EOF

mv "$TEMP_FILE" "$INVENTORY_FILE"
TEMP_FILE=""
chmod 0600 "$INVENTORY_FILE"

echo -e "${GREEN}inventory 已生成: ${INVENTORY_DISPLAY}（权限 0600）${NC}"
show_host_key_guidance

if command -v ansible >/dev/null 2>&1; then
    IFS= read -r -p "已通过可信渠道核验所有 fingerprint 并写入 known_hosts，是否执行 ansible ping? (y/n): " RUN_PING
    if [[ "$RUN_PING" == "y" || "$RUN_PING" == "Y" ]]; then
        ansible all -i "$INVENTORY_FILE" -m ping
    else
        echo -e "${YELLOW}未确认 host key，已跳过连通性检查。${NC}"
    fi
else
    echo -e "${YELLOW}未检测到 ansible，跳过连通性检查。${NC}"
fi

cat <<EOF

下一步：
  1. 使用 Ansible Vault 或外部 Secret 提供 MySQL 密码，禁止向 tracked 文件写入明文真实密码。
  2. 例如创建未跟踪的加密变量文件：
       ansible-vault create inventory/vault.local.yml
  3. 完成 host key 核验后，通过主入口执行：
       ./scripts/deploy_dedicated_routers.sh --check-prereq -i ${INVENTORY_DISPLAY} --ask-vault-pass -e @inventory/vault.local.yml
       ./scripts/deploy_dedicated_routers.sh --production-ready -i ${INVENTORY_DISPLAY} --ask-vault-pass -e @inventory/vault.local.yml
EOF
