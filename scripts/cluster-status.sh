#!/bin/bash

# MySQL InnoDB Cluster 辅助状态查询。
# 交互用法: ./scripts/cluster-status.sh <primary_host> [cluster_user] [cluster_name]
# 自动化由受保护的进程环境注入 MYSQL_CLUSTER_PASSWORD。
#
# 完整 HA 验收仍应使用 scripts/deploy_dedicated_routers.sh --status。

set -euo pipefail

PRIMARY_HOST="${1:-${MYSQL_PRIMARY_HOST:-}}"
CLUSTER_USER="${2:-${MYSQL_CLUSTER_USER:-clusteradmin}}"
CLUSTER_NAME="${3:-${MYSQL_CLUSTER_NAME:-prodCluster}}"
MEMBER_HOSTS="${MYSQL_CLUSTER_MEMBERS:-$PRIMARY_HOST}"
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

[[ -n "$PRIMARY_HOST" ]] ||
    fail "必须通过第一个参数或 MYSQL_PRIMARY_HOST 指定连接节点"
validate_host "$PRIMARY_HOST"
validate_identifier "$CLUSTER_USER" "集群用户名"
validate_identifier "$CLUSTER_NAME" "集群名称"
read_password
trap 'unset CLUSTER_PASSWORD' EXIT

echo "=== MySQL InnoDB Cluster 状态检查 ==="
echo "连接节点: $PRIMARY_HOST"
echo "集群名称: $CLUSTER_NAME"
echo "检查时间: $(date)"
echo

echo "1. 集群整体状态:"
run_mysqlsh "$PRIMARY_HOST" \
    "dba.getCluster('${CLUSTER_NAME}').status();"

echo
echo "2. 集群拓扑信息:"
run_mysqlsh "$PRIMARY_HOST" \
    "dba.getCluster('${CLUSTER_NAME}').describe();"

echo
echo "3. 集群健康检查:"
run_mysqlsh "$PRIMARY_HOST" \
    "print('集群状态: ' + dba.getCluster('${CLUSTER_NAME}').status().defaultReplicaSet.status);"

echo
echo "4. 各 inventory 节点连接测试:"
IFS=',' read -r -a CLUSTER_MEMBERS <<<"$MEMBER_HOSTS"
MEMBER_CONNECTION_FAILED=0
for host in "${CLUSTER_MEMBERS[@]}"; do
    validate_host "$host"
    echo -n "测试 $host:3306 ... "
    if run_mysqlsh "$host" "session.runSql('SELECT 1');" >/dev/null 2>&1; then
        echo "连接正常"
    else
        echo "连接失败"
        MEMBER_CONNECTION_FAILED=1
    fi
done

if (( MEMBER_CONNECTION_FAILED != 0 )); then
    fail "至少一个 inventory 节点连接失败"
fi

echo
echo "=== 检查完成 ==="
