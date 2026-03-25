#!/bin/bash

# 硬件/容量配置升级入口
# 统一走 config_manager + apply-config，不再维护独立的旧升级流程

set -euo pipefail

PROFILE=""
INVENTORY="inventory/hosts-with-dedicated-routers.yml"
APPLY=false

show_help() {
    cat << EOF
MySQL 硬件配置升级脚本

用法:
  $0 --profile <8c32g-optimized|original-10k> [--inventory <file>] [--apply]

说明:
  - 只切换 inventory/group_vars/all.yml 中的 mysql_hardware_profile
  - 加上 --apply 后，会自动滚动应用新配置
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--profile)
            PROFILE="$2"
            shift 2
            ;;
        -i|--inventory)
            INVENTORY="$2"
            shift 2
            ;;
        --apply)
            APPLY=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "未知参数: $1" >&2
            show_help
            exit 1
            ;;
    esac
done

if [[ -z "$PROFILE" ]]; then
    echo "必须指定 --profile" >&2
    show_help
    exit 1
fi

./scripts/config_manager.sh --switch "$PROFILE"

if [[ "$APPLY" == "true" ]]; then
    ./scripts/deploy_dedicated_routers.sh --apply-config -i "$INVENTORY"
fi
