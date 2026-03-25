#!/bin/bash

# 生产部署入口脚本
# 统一调用当前仓库的 preflight / playbook / 健康检查，避免旧脚本中的硬编码和配置漂移

set -euo pipefail

DEFAULT_INVENTORY="inventory/hosts-with-dedicated-routers.yml"
INVENTORY="${MYSQL_CLUSTER_INVENTORY:-$DEFAULT_INVENTORY}"
SKIP_KERNEL_OPTIMIZATION=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${PURPLE}[STEP]${NC} $1"; }

show_help() {
    cat << EOF
MySQL InnoDB Cluster 生产部署入口

用法:
    $0 [选项] [inventory]

选项:
    --production-ready      完整生产部署（preflight + site + health-check）
    --mysql-only            仅安装 MySQL 并配置 InnoDB Cluster
    --install-routers       仅安装/重配 Router
    --configure-lb          仅安装/重配 HAProxy + Keepalived
    --apply-config          按当前主配置滚动应用到现有节点
    --scale-mysql-add       扩容 MySQL 节点（需配合 --limit）
    --scale-mysql-remove    缩容 MySQL 节点（需配合 --target，可选 --new-primary）
    --shrink-router         缩容 Router 节点（需配合 --limit）
    --shrink-lb             缩容 HAProxy/Keepalived 节点（需配合 --limit）
    --backup                执行一次可选备份（logical / xtrabackup，需先启用 backup_config.enabled=true）
    --full-deploy           部署 Router + HAProxy/Keepalived（假设 MySQL 集群已存在）
    --check-prereq          仅执行前置检查
    --test-connection       仅执行 HA 健康检查
    --status                查看当前 HA 状态
    --rollback              停止入口层服务（不删除数据库数据）
    -i, --inventory <file>  指定 inventory 文件
    --skip-kernel-optimization  跳过内核优化（默认不跳过）
    --limit <group|host>    指定扩容/重配目标
    --target <host>         指定缩容目标主机
    --new-primary <host>    缩容当前主节点前先切换到新主节点
    -h, --help              显示帮助

说明:
    - 推荐应用入口是 HAProxy VIP: 3307(读写) / 3308(只读)
    - 直连 Router 端口为 6446(读写) / 6447(只读)
    - MySQL/Router/HAProxy 的真实配置以 inventory/group_vars/all.yml 和目标 inventory 为准
EOF
}

require_project_root() {
    if [[ ! -f "ansible.cfg" ]]; then
        log_error "请在项目根目录运行此脚本"
        exit 1
    fi
}

require_dependencies() {
    local deps=(ansible ansible-playbook python)
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            log_error "缺少依赖: $dep"
            exit 1
        fi
    done

    if [[ ! -f "$INVENTORY" ]]; then
        log_error "inventory 文件不存在: $INVENTORY"
        exit 1
    fi
}

read_var_from_inventory() {
    local var_name="$1"
    if command -v ansible-inventory >/dev/null 2>&1; then
        ansible-inventory -i "$INVENTORY" --list 2>/dev/null | python - "$var_name" << 'PY'
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

show_connection_summary() {
    local vip rw_port ro_port router_rw router_ro
    vip="$(read_var_from_inventory keepalived_vip)"
    rw_port="$(read_var_from_inventory haproxy_mysql_rw_port)"
    ro_port="$(read_var_from_inventory haproxy_mysql_ro_port)"
    router_rw="$(read_var_from_inventory mysql_router_port)"
    router_ro="$(read_var_from_inventory mysql_router_ro_port)"

    echo
    echo "连接信息:"
    echo "  HAProxy VIP（推荐）: ${vip}:${rw_port} (RW) / ${vip}:${ro_port} (RO)"
    echo "  Router 直连: router-ip:${router_rw} (RW) / router-ip:${router_ro} (RO)"
}

check_prerequisites() {
    log_step "执行前置检查"
    ansible-playbook -i "$INVENTORY" playbooks/preflight-ha.yml
}

deploy_mysql_cluster() {
    apply_kernel_optimization "mysql_cluster"
    log_step "部署 MySQL Server"
    ansible-playbook -i "$INVENTORY" playbooks/install-mysql.yml

    log_step "配置 InnoDB Cluster"
    ansible-playbook -i "$INVENTORY" playbooks/configure-cluster.yml
}

deploy_routers() {
    apply_kernel_optimization "mysql_router"
    log_step "部署 MySQL Router"
    ansible-playbook -i "$INVENTORY" playbooks/install-router.yml
}

deploy_load_balancers() {
    apply_kernel_optimization "haproxy_lb"
    log_step "部署 HAProxy"
    ansible-playbook -i "$INVENTORY" playbooks/install-haproxy.yml

    log_step "部署 Keepalived"
    ansible-playbook -i "$INVENTORY" playbooks/install-keepalived.yml
}

apply_config() {
    check_prerequisites
    apply_kernel_optimization "mysql_cluster:mysql_router:haproxy_lb"
    log_step "滚动应用当前主配置"
    ansible-playbook -i "$INVENTORY" playbooks/apply-config.yml
    health_check
}

scale_mysql_add() {
    local limit="$1"
    if [[ -z "$limit" ]]; then
        log_error "--scale-mysql-add 需要配合 --limit <new-host>"
        exit 1
    fi
    check_prerequisites
    apply_kernel_optimization "$limit"
    log_step "扩容 MySQL 节点: $limit"
    ansible-playbook -i "$INVENTORY" playbooks/scale-mysql.yml --limit "$limit"
    health_check
}

scale_mysql_remove() {
    local target="$1"
    local new_primary="$2"
    local extra_vars=("mysql_shrink_target=$target")
    if [[ -z "$target" ]]; then
        log_error "--scale-mysql-remove 需要配合 --target <host>"
        exit 1
    fi
    if [[ -n "$new_primary" ]]; then
        extra_vars+=("mysql_shrink_new_primary=$new_primary")
    fi
    check_prerequisites
    log_step "缩容 MySQL 节点: $target"
    ansible-playbook -i "$INVENTORY" playbooks/shrink-mysql.yml --extra-vars "${extra_vars[*]}"
    health_check
}

shrink_router() {
    local limit="$1"
    if [[ -z "$limit" ]]; then
        log_error "--shrink-router 需要配合 --limit <router-host>"
        exit 1
    fi
    check_prerequisites
    log_step "缩容 Router 节点: $limit"
    ansible-playbook -i "$INVENTORY" playbooks/shrink-router.yml --limit "$limit"
}

shrink_lb() {
    local limit="$1"
    if [[ -z "$limit" ]]; then
        log_error "--shrink-lb 需要配合 --limit <haproxy-host>"
        exit 1
    fi
    check_prerequisites
    log_step "缩容 HAProxy/Keepalived 节点: $limit"
    ansible-playbook -i "$INVENTORY" playbooks/shrink-haproxy.yml --limit "$limit"
}

run_backup() {
    log_step "执行逻辑备份"
    ansible-playbook -i "$INVENTORY" playbooks/backup.yml
}

apply_kernel_optimization() {
    local limit="$1"
    if [[ "$SKIP_KERNEL_OPTIMIZATION" == "true" ]]; then
        log_warning "已显式跳过内核优化"
        return 0
    fi
    log_step "执行内核优化: $limit"
    ansible-playbook -i "$INVENTORY" playbooks/kernel-optimization-stable.yml --limit "$limit"
}

health_check() {
    log_step "执行 HA 健康检查"
    ./scripts/health-check-ha.sh "$INVENTORY"
}

rollback_entry_tier() {
    log_warning "仅停止 Router / HAProxy / Keepalived，不删除 MySQL 数据"
    ansible mysql_router -i "$INVENTORY" -b -m systemd -a "name=mysqlrouter state=stopped enabled=no" || true
    ansible haproxy_lb -i "$INVENTORY" -b -m systemd -a "name=haproxy state=stopped enabled=no" || true
    ansible haproxy_lb -i "$INVENTORY" -b -m systemd -a "name=keepalived state=stopped enabled=no" || true
}

show_status() {
    health_check
    show_connection_summary
}

production_ready_deploy() {
    check_prerequisites

    log_step "执行全量部署"
    ansible-playbook -i "$INVENTORY" playbooks/site.yml

    health_check
    show_connection_summary
    log_success "生产部署流程执行完成"
}

full_deploy() {
    check_prerequisites
    deploy_routers
    deploy_load_balancers
    health_check
    show_connection_summary
    log_success "入口层部署完成"
}

main() {
    require_project_root

    local action=""
    local limit=""
    local target=""
    local new_primary=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --production-ready|--mysql-only|--install-routers|--configure-lb|--apply-config|--scale-mysql-add|--scale-mysql-remove|--shrink-router|--shrink-lb|--backup|--full-deploy|--check-prereq|--test-connection|--status|--rollback)
                action="$1"
                shift
                ;;
            -i|--inventory)
                INVENTORY="$2"
                shift 2
                ;;
            --skip-kernel-optimization)
                SKIP_KERNEL_OPTIMIZATION=true
                shift
                ;;
            --limit)
                limit="$2"
                shift 2
                ;;
            --target)
                target="$2"
                shift 2
                ;;
            --new-primary)
                new_primary="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                if [[ -z "$action" && -f "$1" ]]; then
                    INVENTORY="$1"
                    shift
                else
                    log_error "未知参数: $1"
                    show_help
                    exit 1
                fi
                ;;
        esac
    done

    if [[ -z "$action" ]]; then
        log_error "请指定操作参数"
        show_help
        exit 1
    fi

    require_dependencies

    case "$action" in
        --production-ready)
            if [[ "$SKIP_KERNEL_OPTIMIZATION" == "true" ]]; then
                check_prerequisites
                log_step "执行全量部署"
                ansible-playbook -i "$INVENTORY" playbooks/site.yml --skip-tags kernel_optimization
                health_check
                show_connection_summary
                log_success "生产部署流程执行完成"
            else
            production_ready_deploy
            fi
            ;;
        --mysql-only)
            check_prerequisites
            deploy_mysql_cluster
            ;;
        --install-routers)
            check_prerequisites
            deploy_routers
            ;;
        --configure-lb)
            check_prerequisites
            deploy_load_balancers
            ;;
        --apply-config)
            apply_config
            ;;
        --scale-mysql-add)
            scale_mysql_add "$limit"
            ;;
        --scale-mysql-remove)
            scale_mysql_remove "$target" "$new_primary"
            ;;
        --shrink-router)
            shrink_router "$limit"
            ;;
        --shrink-lb)
            shrink_lb "$limit"
            ;;
        --backup)
            run_backup
            ;;
        --full-deploy)
            apply_kernel_optimization "mysql_router:haproxy_lb"
            full_deploy
            ;;
        --check-prereq)
            check_prerequisites
            ;;
        --test-connection)
            health_check
            ;;
        --status)
            show_status
            ;;
        --rollback)
            rollback_entry_tier
            ;;
    esac
}

main "$@"
