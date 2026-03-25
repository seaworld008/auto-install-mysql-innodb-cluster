#!/bin/bash

# 兼容旧入口的部署包装脚本
# 保留历史 action 接口，但内部统一转发到新的生产部署入口

set -euo pipefail

ACTION="${1:-all}"
INVENTORY_FILE="${MYSQL_CLUSTER_INVENTORY:-inventory/hosts.yml}"

show_help() {
    cat << EOF
MySQL InnoDB Cluster 部署脚本

使用方法:
  $0 [action] [inventory]

可用操作:
  install   - 仅安装 MySQL 并配置集群
  cluster   - 仅配置 InnoDB Cluster
  router    - 仅安装/重配 MySQL Router
  all       - 完整安装（MySQL + Router + HAProxy + Keepalived）
  status    - 检查当前状态
  clean     - 停止入口层服务（不删除数据库数据）
  help      - 显示此帮助信息

说明:
  - 当前推荐入口脚本是 scripts/deploy_dedicated_routers.sh
  - 如果需要指定 inventory，可作为第二个参数传入
EOF
}

if [[ $# -ge 2 && -f "$2" ]]; then
    INVENTORY_FILE="$2"
fi

case "$ACTION" in
    install)
        exec ./scripts/deploy_dedicated_routers.sh --mysql-only -i "$INVENTORY_FILE"
        ;;
    cluster)
        exec ansible-playbook -i "$INVENTORY_FILE" playbooks/configure-cluster.yml
        ;;
    router)
        exec ./scripts/deploy_dedicated_routers.sh --install-routers -i "$INVENTORY_FILE"
        ;;
    all)
        exec ./scripts/deploy_dedicated_routers.sh --production-ready -i "$INVENTORY_FILE"
        ;;
    status)
        exec ./scripts/deploy_dedicated_routers.sh --status -i "$INVENTORY_FILE"
        ;;
    clean)
        exec ./scripts/deploy_dedicated_routers.sh --rollback -i "$INVENTORY_FILE"
        ;;
    help|-h|--help)
        show_help
        ;;
    *)
        echo "未知操作: $ACTION" >&2
        show_help
        exit 1
        ;;
esac
