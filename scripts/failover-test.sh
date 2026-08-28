#!/bin/bash

# MySQL InnoDB Cluster 隔离环境故障转移演练辅助脚本。
# 交互用法: ALLOW_FAILOVER_DRILL=1 MYSQL_CLUSTER_MEMBERS='db2,db3' \
#   ./scripts/failover-test.sh <connection_host> [cluster_user] [cluster_name]
# 自动化由受保护的进程环境注入 MYSQL_CLUSTER_PASSWORD。

set -euo pipefail

CONNECTION_HOST="${1:-${MYSQL_PRIMARY_HOST:-}}"
CLUSTER_USER="${2:-${MYSQL_CLUSTER_USER:-clusteradmin}}"
CLUSTER_NAME="${3:-${MYSQL_CLUSTER_NAME:-prodCluster}}"
MEMBER_HOSTS="${MYSQL_CLUSTER_MEMBERS:-}"
CLUSTER_PASSWORD="${MYSQL_CLUSTER_PASSWORD:-}"

fail() {
    echo "错误: $1" >&2
    exit 1
}

validate_identifier() {
    local value="$1"
    local label="$2"
    [[ "$value" =~ ^[A-Za-z0-9_.-]+$ ]] ||
        fail "$label 只能包含字母、数字、点、下划线或连字符"
}

validate_host() {
    local value="$1"
    [[ "$value" =~ ^[A-Za-z0-9.-]+$ ]] ||
        fail "主机地址包含不支持的字符: $value"
}

validate_endpoint() {
    local value="$1"
    local endpoint_port="${value##*:}"
    local endpoint_host="${value%:*}"
    local endpoint_port_number
    [[ "$value" == *:* && "$endpoint_port" =~ ^[0-9]{1,5}$ ]] ||
        fail "集群返回了不合法的成员地址: $value"
    validate_host "$endpoint_host"
    endpoint_port_number=$((10#$endpoint_port))
    (( endpoint_port_number >= 1 && endpoint_port_number <= 65535 )) ||
        fail "集群返回了不合法的成员端口: $endpoint_port"
}

read_password() {
    if [[ -n "$CLUSTER_PASSWORD" ]]; then
        return
    fi
    [[ -t 0 ]] || fail "非交互执行必须通过受保护的 MYSQL_CLUSTER_PASSWORD 环境变量提供密码"
    IFS= read -r -s -p "请输入 MySQL 集群密码: " CLUSTER_PASSWORD
    echo
    [[ -n "$CLUSTER_PASSWORD" ]] || fail "MySQL 集群密码不能为空"
}

run_mysqlsh() {
    local host="$1"
    local javascript="$2"
    printf '%s\n' "$CLUSTER_PASSWORD" |
        mysqlsh \
            --no-wizard \
            --quiet-start=2 \
            --passwords-from-stdin \
            --uri "${CLUSTER_USER}@${host}:3306" \
            --js \
            -e "$javascript"
}

[[ "${ALLOW_FAILOVER_DRILL:-0}" == "1" ]] ||
    fail "仅允许在隔离/staging 演练中运行；确认后设置 ALLOW_FAILOVER_DRILL=1"
[[ -n "$CONNECTION_HOST" ]] ||
    fail "必须通过第一个参数或 MYSQL_PRIMARY_HOST 指定连接节点"
[[ -n "$MEMBER_HOSTS" ]] ||
    fail "必须通过 MYSQL_CLUSTER_MEMBERS 提供逗号分隔的候选连接节点"
validate_host "$CONNECTION_HOST"
validate_identifier "$CLUSTER_USER" "集群用户名"
validate_identifier "$CLUSTER_NAME" "集群名称"
read_password
trap 'unset CLUSTER_PASSWORD' EXIT

IFS=',' read -r -a CLUSTER_MEMBERS <<<"$MEMBER_HOSTS"
for host in "${CLUSTER_MEMBERS[@]}"; do
    validate_host "$host"
done

echo "=== MySQL InnoDB Cluster 故障转移演练 ==="
echo "连接节点: $CONNECTION_HOST"
echo "集群名称: $CLUSTER_NAME"
echo "演练时间: $(date)"
echo

echo "1. 获取当前 primary:"
CURRENT_PRIMARY="$(
    run_mysqlsh "$CONNECTION_HOST" \
        "var s=dba.getCluster('${CLUSTER_NAME}').status().defaultReplicaSet.topology; for (var i in s) { if (s[i].mode === 'R/W') { print(i); break; } }"
)"
[[ -n "$CURRENT_PRIMARY" ]] || fail "无法识别当前 primary"
validate_endpoint "$CURRENT_PRIMARY"
echo "当前 primary: $CURRENT_PRIMARY"

echo
echo "2. 故障前集群状态:"
run_mysqlsh "$CONNECTION_HOST" \
    "print('集群状态: ' + dba.getCluster('${CLUSTER_NAME}').status().defaultReplicaSet.status);"

echo
echo "3. 请在隔离环境的另一个终端人工停止当前 primary:"
echo "ssh root@${CURRENT_PRIMARY%:*} 'systemctl stop mysqld'"
IFS= read -r -p "仅在完成变更审批和回滚准备后输入 FAILOVER 继续: " CONFIRM
[[ "$CONFIRM" == "FAILOVER" ]] || fail "演练已取消"

echo
echo "4. 等待故障检测与自动切换（30 秒）..."
sleep 30

echo
echo "5. 查找可连接的剩余节点:"
CONNECTED_HOST=""
for host in "${CLUSTER_MEMBERS[@]}"; do
    echo "尝试连接节点 $host..."
    if run_mysqlsh "$host" \
        "dba.getCluster('${CLUSTER_NAME}').status();" >/dev/null 2>&1; then
        CONNECTED_HOST="$host"
        echo "成功连接到 $host"
        break
    fi
done
[[ -n "$CONNECTED_HOST" ]] || fail "没有候选节点可连接，立即执行人工恢复"

echo
echo "6. 获取切换后的 primary:"
NEW_PRIMARY="$(
    run_mysqlsh "$CONNECTED_HOST" \
        "var s=dba.getCluster('${CLUSTER_NAME}').status().defaultReplicaSet.topology; for (var i in s) { if (s[i].mode === 'R/W') { print(i); break; } }"
)"
[[ -n "$NEW_PRIMARY" ]] || fail "无法识别切换后的 primary"
validate_endpoint "$NEW_PRIMARY"
echo "原 primary: $CURRENT_PRIMARY"
echo "新 primary: $NEW_PRIMARY"

echo
echo "7. 人工恢复步骤:"
echo "1) ssh root@${CURRENT_PRIMARY%:*} 'systemctl start mysqld'"
echo "2) 在 MySQL Shell 交互式密码提示下执行："
echo "   mysqlsh --uri ${CLUSTER_USER}@${NEW_PRIMARY%:*}:3306 --js -e \"dba.getCluster('${CLUSTER_NAME}').rejoinInstance('${CURRENT_PRIMARY}')\""
echo "3) 使用主入口 --status 验证 Cluster、Router、HAProxy、Keepalived 和 VIP。"
echo
echo "=== 演练辅助流程完成；仍需保存演练记录 ==="
