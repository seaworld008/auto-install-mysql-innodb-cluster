#!/bin/bash

# 生产部署入口脚本
# 统一调用当前仓库的 preflight / playbook / 健康检查，避免旧脚本中的硬编码和配置漂移

set -euo pipefail

DEFAULT_INVENTORY="inventory/hosts-with-dedicated-routers.yml"
INVENTORY="${MYSQL_CLUSTER_INVENTORY:-$DEFAULT_INVENTORY}"
SKIP_KERNEL_OPTIMIZATION=false
ANSIBLE_COMMON_ARGS=()
INVENTORY_JSON=""

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

cleanup_sensitive_state() {
    unset INVENTORY_JSON
}

trap cleanup_sensitive_state EXIT

detect_python() {
    if [[ -n "${PYTHON_BIN:-}" ]]; then
        if command -v "$PYTHON_BIN" >/dev/null 2>&1; then
            command -v "$PYTHON_BIN"
            return 0
        fi
        log_error "PYTHON_BIN 指向的命令不可用: $PYTHON_BIN"
        exit 1
    fi
    if command -v python3 >/dev/null 2>&1; then
        command -v python3
        return 0
    fi
    if command -v python >/dev/null 2>&1; then
        command -v python
        return 0
    fi
    log_error "缺少依赖: python3 或 python"
    exit 1
}

require_supported_control_python() {
    local python_bin version
    python_bin="$(detect_python)"
    version="$("$python_bin" -c 'import platform; print(platform.python_version())')"
    if ! "$python_bin" -c 'import sys; raise SystemExit(sys.version_info < (3, 12))'; then
        log_error "控制节点 Python 版本为 $version；ansible-core 2.20/2.21 要求 Python 3.12+"
        exit 1
    fi
}

# 检查范围由入口决定，后置 extra vars 防止本地配置意外关闭完整 HA 门。
PREFLIGHT_FULL="preflight_require_router=true preflight_require_haproxy=true preflight_require_keepalived=true"
HEALTH_FULL="$PREFLIGHT_FULL health_require_router=true health_require_haproxy=true health_require_keepalived=true"

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
    --install-haproxy       仅安装/重配 HAProxy（要求 MySQL + Router 已健康）
    --install-keepalived    仅安装/重配 Keepalived（要求 HAProxy 及上游已健康）
    --apply-config          按当前主配置滚动应用到现有节点
    --kernel-optimize-only  仅执行内核优化（可配合 --limit）
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
    --scope <name>          只读检查范围：full（默认）/ mysql / router / haproxy
    --limit <group|host>    仅用于扩容、入口缩容或内核优化
    --target <host>         指定缩容目标主机
    --new-primary <host>    缩容当前主节点前先切换到新主节点
    -e, --extra-vars <vars>  透传 Ansible extra vars（敏感值请使用 @Vault文件）
    --ask-vault-pass        交互式询问 Ansible Vault 密码
    --vault-password-file <file>
                            从受保护文件读取 Ansible Vault 密码
    -h, --help              显示帮助

说明:
    - 事务型应用优先使用 HAProxy VIP: 3307；3309 自动读写分离需先验证兼容性
    - HAProxy VIP 也保留 3307(强制读写) / 3308(强制只读)
    - 直连 Router 端口为 6450(自动读写分离) / 6446(强制读写) / 6447(强制只读)
    - MySQL/Router/HAProxy 的真实配置以 inventory/group_vars/all.yml 和目标 inventory 为准
    - 多阶段操作会启动多个 Ansible 进程；交互 Vault 可能重复询问，自动化推荐仓库外 0600 的 --vault-password-file
EOF
}

require_project_root() {
    if [[ ! -f "ansible.cfg" ]]; then
        log_error "请在项目根目录运行此脚本"
        exit 1
    fi
}

require_dependencies() {
    local deps=(ansible ansible-playbook ansible-inventory)
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            log_error "缺少依赖: $dep"
            exit 1
        fi
    done
    require_supported_control_python

    if [[ ! -f "$INVENTORY" ]]; then
        log_error "inventory 文件不存在: $INVENTORY"
        exit 1
    fi
}

run_playbook() {
    local command=(ansible-playbook -i "$INVENTORY")
    if (( ${#ANSIBLE_COMMON_ARGS[@]} > 0 )); then
        command+=("${ANSIBLE_COMMON_ARGS[@]}")
    fi
    command+=("$@")
    "${command[@]}"
}

run_ansible() {
    local command=(ansible)
    command+=("$@" -i "$INVENTORY")
    if (( ${#ANSIBLE_COMMON_ARGS[@]} > 0 )); then
        command+=("${ANSIBLE_COMMON_ARGS[@]}")
    fi
    "${command[@]}"
}

load_inventory_json() {
    if [[ -z "$INVENTORY_JSON" ]]; then
        local inventory_command=(ansible-inventory -i "$INVENTORY")
        if (( ${#ANSIBLE_COMMON_ARGS[@]} > 0 )); then
            inventory_command+=("${ANSIBLE_COMMON_ARGS[@]}")
        fi
        inventory_command+=(--list)
        INVENTORY_JSON="$("${inventory_command[@]}")"
    fi
}

read_var_from_inventory() {
    local var_name="$1"
    local python_bin
    python_bin="$(detect_python)"
    load_inventory_json
    printf '%s\n' "$INVENTORY_JSON" | "$python_bin" -c '
import json
import sys

var_name = sys.argv[1]
data = json.load(sys.stdin)
missing = object()
value = data.get("all", {}).get("vars", {}).get(var_name, missing)

if value is missing:
    hostvars = data.get("_meta", {}).get("hostvars", {})
    values = [
        hostvars[host][var_name]
        for host in sorted(hostvars)
        if var_name in hostvars[host]
    ]
    if not values:
        print(f"inventory 中未解析到变量: {var_name}", file=sys.stderr)
        raise SystemExit(2)

    canonical = {
        json.dumps(item, ensure_ascii=False, sort_keys=True)
        for item in values
    }
    if len(canonical) != 1:
        print(f"inventory 中变量值不一致: {var_name}", file=sys.stderr)
        raise SystemExit(3)
    value = values[0]

if isinstance(value, (dict, list)):
    print(json.dumps(value, ensure_ascii=False, sort_keys=True))
elif isinstance(value, bool):
    print(str(value).lower())
elif value is None:
    print("")
else:
    print(value)
' "$var_name"
}

show_connection_summary() {
    local profile="${1:-full}"
    if [[ "$profile" == "mysql" ]]; then
        echo "MySQL 层检查通过；直连 inventory 中数据库节点，不输出尚未启用的入口。"
        return 0
    fi
    local vip rw_port ro_port rwsplit_port router_rw router_ro router_rwsplit
    load_inventory_json
    vip="$(read_var_from_inventory keepalived_vip)"
    rw_port="$(read_var_from_inventory haproxy_mysql_rw_port)"
    ro_port="$(read_var_from_inventory haproxy_mysql_ro_port)"
    rwsplit_port="$(read_var_from_inventory haproxy_mysql_rwsplit_port)"
    router_rw="$(read_var_from_inventory mysql_router_port)"
    router_ro="$(read_var_from_inventory mysql_router_ro_port)"
    router_rwsplit="$(read_var_from_inventory mysql_router_rwsplit_port)"

    echo
    echo "连接信息:"
    if [[ "$profile" == "full" ]]; then
        echo "  HAProxy VIP（事务优先）: ${vip}:${rw_port} (RW)"
        echo "  HAProxy VIP: ${vip}:${ro_port} (RO) / ${vip}:${rwsplit_port} (R/W Split，先验证兼容性)"
    elif [[ "$profile" == "haproxy" ]]; then
        echo "  HAProxy 主机地址: RW ${rw_port} / RO ${ro_port} / Split ${rwsplit_port}；本次未检查 VIP。"
    fi
    echo "  Router 直连: router-ip:${router_rwsplit} (R/W Split) / ${router_rw} (RW) / ${router_ro} (RO)"
}

check_prerequisites() {
    local profile="${1:-full}"
    local credential_scope="${2:-}"
    if [[ -z "$credential_scope" ]]; then
        case "$profile" in
            router|haproxy) credential_scope=cluster ;;
            *) credential_scope=install ;;
        esac
    fi
    local profile_args=()
    case "$profile" in
        full)
            profile_args+=("--extra-vars" "$PREFLIGHT_FULL")
            ;;
        mysql)
            profile_args+=(
                "--extra-vars"
                "preflight_require_router=false preflight_require_haproxy=false preflight_require_keepalived=false"
            )
            ;;
        router)
            profile_args+=(
                "--extra-vars"
                "preflight_require_router=true preflight_require_haproxy=false preflight_require_keepalived=false"
            )
            ;;
        haproxy)
            profile_args+=("--extra-vars" "preflight_require_router=true preflight_require_haproxy=true preflight_require_keepalived=false")
            ;;
        *)
            log_error "未知 preflight profile: $profile"
            exit 1
            ;;
    esac
    profile_args+=("--extra-vars" "preflight_credential_scope=$credential_scope preflight_read_only=false")
    log_step "执行前置检查"
    if (( ${#profile_args[@]} > 0 )); then
        run_playbook "${profile_args[@]}" playbooks/preflight-ha.yml
    else
        run_playbook playbooks/preflight-ha.yml
    fi
}

deploy_mysql_cluster() {
    apply_kernel_optimization "mysql_cluster"
    log_step "部署 MySQL Server"
    run_playbook playbooks/install-mysql.yml

    log_step "配置 InnoDB Cluster"
    run_playbook playbooks/configure-cluster.yml
}

deploy_routers() {
    apply_kernel_optimization "mysql_router"
    log_step "部署 MySQL Router"
    run_playbook playbooks/install-router.yml
}

deploy_load_balancers() {
    apply_kernel_optimization "haproxy_lb"
    log_step "部署 HAProxy"
    run_playbook playbooks/install-haproxy.yml

    log_step "部署 Keepalived"
    run_playbook playbooks/install-keepalived.yml
}

apply_config() {
    check_prerequisites
    apply_kernel_optimization "mysql_cluster:mysql_router:haproxy_lb"
    log_step "滚动应用当前主配置"
    run_playbook playbooks/apply-config.yml
    health_check
}

kernel_optimize_only() {
    local limit="$1"
    if [[ -z "$limit" ]]; then
        limit="all"
    fi
    log_step "仅执行内核优化: $limit"
    run_playbook playbooks/kernel-optimization-stable.yml --limit "$limit"
}

validate_single_host_limit() {
    local group="$1"
    local limit="$2"
    local min_nodes_var="$3"
    local matched_output group_output matched_count group_count min_nodes

    matched_output="$(run_ansible "$group" --list-hosts --limit "$limit")"
    matched_count="$(
        printf '%s\n' "$matched_output" |
            awk 'NR > 1 && NF { count += 1 } END { print count + 0 }'
    )"
    if [[ "$matched_count" -ne 1 ]]; then
        log_error "--limit 必须在 $group 中精确匹配一台主机，当前匹配 $matched_count 台"
        exit 1
    fi

    group_output="$(run_ansible "$group" --list-hosts)"
    group_count="$(
        printf '%s\n' "$group_output" |
            awk 'NR > 1 && NF { count += 1 } END { print count + 0 }'
    )"
    min_nodes="$(read_var_from_inventory "$min_nodes_var")"
    if (( group_count - 1 < min_nodes )); then
        log_error "缩容后 $group 仅剩 $((group_count - 1)) 台，低于最小要求 $min_nodes"
        exit 1
    fi
}

scale_mysql_add() {
    local limit="$1"
    if [[ -z "$limit" ]]; then
        log_error "--scale-mysql-add 需要配合 --limit <new-host>"
        exit 1
    fi
    validate_single_host_limit "mysql_cluster" "$limit" "mysql_ha_min_nodes"
    check_prerequisites "mysql"
    apply_kernel_optimization "$limit"
    log_step "扩容 MySQL 节点: $limit"
    run_playbook playbooks/scale-mysql.yml --limit "$limit"
    health_check "mysql"
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
    check_prerequisites mysql cluster
    log_step "缩容 MySQL 节点: $target"
    run_playbook playbooks/shrink-mysql.yml --extra-vars "${extra_vars[*]}"
    log_success "剩余 MySQL 成员已通过缩容 playbook 的完整健康复核"
    log_warning "请从 inventory 移除 $target 后再执行 --status 全栈检查"
}

shrink_router() {
    local limit="$1"
    if [[ -z "$limit" ]]; then
        log_error "--shrink-router 需要配合 --limit <router-host>"
        exit 1
    fi
    validate_single_host_limit "mysql_router" "$limit" "router_ha_min_nodes"
    check_prerequisites "router"
    log_step "缩容 Router 节点: $limit"
    run_playbook playbooks/shrink-router.yml --limit "$limit"
}

shrink_lb() {
    local limit="$1"
    if [[ -z "$limit" ]]; then
        log_error "--shrink-lb 需要配合 --limit <haproxy-host>"
        exit 1
    fi
    validate_single_host_limit "haproxy_lb" "$limit" "haproxy_ha_min_nodes"
    check_prerequisites full cluster
    log_step "缩容 HAProxy/Keepalived 节点: $limit"
    run_playbook playbooks/shrink-haproxy.yml --limit "$limit"
}

run_backup() {
    check_prerequisites mysql backup
    log_step "执行备份"
    run_playbook playbooks/backup.yml
}

apply_kernel_optimization() {
    local limit="$1"
    if [[ "$SKIP_KERNEL_OPTIMIZATION" == "true" ]]; then
        log_warning "已显式跳过内核优化"
        return 0
    fi
    log_step "执行内核优化: $limit"
    run_playbook playbooks/kernel-optimization-stable.yml --limit "$limit"
}

health_check() {
    local profile="${1:-full}"
    log_step "执行 HA 健康检查"
    local command=(./scripts/health-check-ha.sh "$INVENTORY")
    if (( ${#ANSIBLE_COMMON_ARGS[@]} > 0 )); then
        command+=("${ANSIBLE_COMMON_ARGS[@]}")
    fi
    case "$profile" in
        full)
            command+=("--extra-vars" "$HEALTH_FULL")
            ;;
        mysql)
            command+=(
                "--extra-vars"
                "preflight_require_router=false preflight_require_haproxy=false preflight_require_keepalived=false health_require_router=false health_require_haproxy=false health_require_keepalived=false"
            )
            ;;
        router)
            command+=(
                "--extra-vars"
                "preflight_require_router=true preflight_require_haproxy=false preflight_require_keepalived=false health_require_router=true health_require_haproxy=false health_require_keepalived=false"
            )
            ;;
        haproxy)
            command+=("--extra-vars" "preflight_require_router=true preflight_require_haproxy=true preflight_require_keepalived=false health_require_router=true health_require_haproxy=true health_require_keepalived=false")
            ;;
        *)
            log_error "未知 health profile: $profile"
            return 1
            ;;
    esac
    command+=("--extra-vars" "preflight_credential_scope=cluster preflight_read_only=true")
    "${command[@]}"
}

rollback_entry_tier() {
    local rollback_failed=0
    log_warning "仅停止 Router / HAProxy / Keepalived，不删除 MySQL 数据"
    if ! run_ansible haproxy_lb -b -m systemd \
        -a "name=keepalived state=stopped enabled=no"; then
        log_error "停止 Keepalived 失败；已继续尝试停止其余入口服务"
        rollback_failed=1
    fi
    if ! run_ansible haproxy_lb -b -m systemd \
        -a "name=haproxy state=stopped enabled=no"; then
        log_error "停止 HAProxy 失败；已继续尝试停止 Router"
        rollback_failed=1
    fi
    if ! run_ansible mysql_router -b -m systemd \
        -a "name=mysqlrouter state=stopped enabled=no"; then
        log_error "停止 MySQL Router 失败"
        rollback_failed=1
    fi
    if (( rollback_failed != 0 )); then
        log_error "入口层回滚未完整执行，请人工核对 VIP 和服务状态"
        return 1
    fi
    log_success "入口层服务已按 Keepalived → HAProxy → Router 顺序停止"
}

show_status() {
    local profile="${1:-full}"
    health_check "$profile"
    show_connection_summary "$profile"
}

production_ready_deploy() {
    if [[ "$SKIP_KERNEL_OPTIMIZATION" == "true" ]]; then
        check_prerequisites
        log_step "执行全量部署（跳过内核优化）"
        run_playbook playbooks/install-mysql.yml
        run_playbook playbooks/configure-cluster.yml
        run_playbook playbooks/install-router.yml
        run_playbook playbooks/install-haproxy.yml
        run_playbook playbooks/install-keepalived.yml
    else
        log_step "执行全量部署"
        run_playbook playbooks/site.yml --extra-vars "$PREFLIGHT_FULL preflight_credential_scope=install preflight_read_only=false"
    fi

    health_check
    show_connection_summary
    log_success "生产部署流程执行完成"
}

full_deploy() {
    check_prerequisites full cluster
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
    local scope=""
    local target=""
    local new_primary=""
    local positional_inventory_seen=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --production-ready|--mysql-only|--install-routers|--configure-lb|--install-haproxy|--install-keepalived|--apply-config|--kernel-optimize-only|--scale-mysql-add|--scale-mysql-remove|--shrink-router|--shrink-lb|--backup|--full-deploy|--check-prereq|--test-connection|--status|--rollback)
                if [[ -n "$action" ]]; then
                    log_error "一次只能指定一个操作: $action 与 $1"
                    exit 1
                fi
                action="$1"
                shift
                ;;
            -i|--inventory)
                if [[ $# -lt 2 ]]; then
                    log_error "$1 需要一个 inventory 文件路径"
                    exit 1
                fi
                INVENTORY="$2"
                shift 2
                ;;
            --skip-kernel-optimization)
                SKIP_KERNEL_OPTIMIZATION=true
                shift
                ;;
            --scope)
                if [[ $# -lt 2 || -z "$2" ]]; then log_error "--scope 需要非空检查范围"; exit 1; fi
                if [[ -n "$scope" ]]; then log_error "--scope 不能重复指定"; exit 1; fi
                scope="$2"
                shift 2
                ;;
            --limit)
                if [[ $# -lt 2 ]]; then
                    log_error "--limit 需要一个 group 或 host"
                    exit 1
                fi
                limit="$2"
                shift 2
                ;;
            --target)
                if [[ $# -lt 2 ]]; then
                    log_error "--target 需要一个 host"
                    exit 1
                fi
                target="$2"
                shift 2
                ;;
            --new-primary)
                if [[ $# -lt 2 ]]; then
                    log_error "--new-primary 需要一个 host"
                    exit 1
                fi
                new_primary="$2"
                shift 2
                ;;
            -e|--extra-vars)
                if [[ $# -lt 2 ]]; then
                    log_error "$1 需要变量表达式或 @文件"
                    exit 1
                fi
                ANSIBLE_COMMON_ARGS+=("--extra-vars" "$2")
                shift 2
                ;;
            --ask-vault-pass)
                ANSIBLE_COMMON_ARGS+=("--ask-vault-pass")
                shift
                ;;
            --vault-password-file)
                if [[ $# -lt 2 ]]; then
                    log_error "--vault-password-file 需要一个文件路径"
                    exit 1
                fi
                ANSIBLE_COMMON_ARGS+=("--vault-password-file" "$2")
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                if [[ "$positional_inventory_seen" == "false" && -f "$1" ]]; then
                    INVENTORY="$1"
                    positional_inventory_seen=true
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

    if [[ -n "$scope" ]]; then
        case "$action" in
            --check-prereq|--status|--test-connection) ;;
            *) log_error "--scope 仅用于只读检查；操作已中止"; exit 1 ;;
        esac
        case "$scope" in
            full|mysql|router|haproxy) ;;
            *) log_error "未知检查范围: $scope"; exit 1 ;;
        esac
    fi

    if [[ "$action" == "--kernel-optimize-only" && "$SKIP_KERNEL_OPTIMIZATION" == "true" ]]; then
        log_error "内核专项操作不能同时要求跳过内核优化"
        exit 1
    fi

    # 不得静默忽略作用域参数，否则操作者可能意外修改整组节点。
    if [[ -n "$limit" ]]; then
        case "$action" in
            --scale-mysql-add|--shrink-router|--shrink-lb|--kernel-optimize-only) ;;
            *) log_error "$action 不支持 --limit；操作已中止"; exit 1 ;;
        esac
    fi
    if [[ -n "$target$new_primary" && "$action" != "--scale-mysql-remove" ]]; then
        log_error "--target / --new-primary 仅用于 --scale-mysql-remove"
        exit 1
    fi
    for host in "$target" "$new_primary"; do
        if [[ -n "$host" && ! "$host" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]]; then
            log_error "缩容目标必须是单个 inventory 主机名，不能包含表达式或变量"
            exit 1
        fi
    done

    require_dependencies

    case "$action" in
        --production-ready)
            production_ready_deploy
            ;;
        --mysql-only)
            check_prerequisites "mysql"
            deploy_mysql_cluster
            health_check "mysql"
            ;;
        --install-routers)
            check_prerequisites "router"
            deploy_routers
            health_check "router"
            ;;
        --install-haproxy)
            check_prerequisites haproxy
            health_check router
            run_playbook playbooks/install-haproxy.yml
            health_check haproxy
            ;;
        --install-keepalived)
            check_prerequisites full cluster
            health_check haproxy
            run_playbook playbooks/install-keepalived.yml
            health_check full
            ;;
        --configure-lb)
            check_prerequisites full cluster
            deploy_load_balancers
            health_check
            ;;
        --apply-config)
            apply_config
            ;;
        --kernel-optimize-only)
            kernel_optimize_only "$limit"
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
            full_deploy
            ;;
        --check-prereq)
            check_prerequisites "${scope:-full}"
            ;;
        --test-connection)
            health_check "${scope:-full}"
            ;;
        --status)
            show_status "${scope:-full}"
            ;;
        --rollback)
            rollback_entry_tier
            ;;
    esac
}

main "$@"
