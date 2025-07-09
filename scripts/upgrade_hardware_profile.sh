#!/bin/bash

# MySQL Hardware Profile Upgrade Script
# 用于生产环境中安全升级MySQL硬件配置的脚本

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示帮助信息
show_help() {
    cat << EOF
MySQL Hardware Profile Upgrade Script

用法:
    $0 [选项] <目标节点>

选项:
    -p, --profile PROFILE    目标硬件配置 (standard|high_performance)
    -c, --check             只检查当前状态，不执行升级
    -f, --force             强制执行，跳过确认
    -h, --help              显示此帮助信息

示例:
    # 检查当前状态
    $0 --check mysql-node1
    
    # 升级单个节点到高性能配置
    $0 --profile high_performance mysql-node1
    
    # 批量升级所有节点
    $0 --profile high_performance all

支持的硬件配置:
    standard         - 8核32G配置 (默认)
    high_performance - 32核64G配置

注意: 升级过程中会重启MySQL服务，请确保在维护窗口期间执行。
EOF
}

# 检查MySQL集群状态
check_cluster_status() {
    local node=$1
    log_info "检查MySQL集群状态..."
    
    # 使用ansible检查集群状态
    ansible $node -m shell -a "mysql -u root -p'{{ mysql_root_password }}' -e 'SELECT MEMBER_HOST, MEMBER_PORT, MEMBER_STATE FROM performance_schema.replication_group_members;'" 2>/dev/null || {
        log_warning "无法连接到MySQL或集群未配置"
        return 1
    }
}

# 检查节点是否为主节点
check_if_primary() {
    local node=$1
    log_info "检查节点 $node 是否为主节点..."
    
    local is_primary=$(ansible $node -m shell -a "mysql -u root -p'{{ mysql_root_password }}' -e 'SELECT IF(@@read_only=0 AND @@super_read_only=0, \"PRIMARY\", \"SECONDARY\") as ROLE;'" --one-line 2>/dev/null | grep -o "PRIMARY\|SECONDARY" || echo "UNKNOWN")
    
    echo $is_primary
}

# 安全移除节点
remove_node_from_cluster() {
    local node=$1
    log_info "从集群中安全移除节点 $node..."
    
    # 停止Group Replication
    ansible $node -m shell -a "mysql -u root -p'{{ mysql_root_password }}' -e 'STOP GROUP_REPLICATION;'"
    
    log_success "节点 $node 已从集群中移除"
}

# 重新加入集群
rejoin_cluster() {
    local node=$1
    log_info "将节点 $node 重新加入集群..."
    
    # 启动Group Replication
    ansible $node -m shell -a "mysql -u root -p'{{ mysql_root_password }}' -e 'START GROUP_REPLICATION;'"
    
    # 等待节点状态变为ONLINE
    local max_wait=60
    local wait_time=0
    while [ $wait_time -lt $max_wait ]; do
        local status=$(ansible $node -m shell -a "mysql -u root -p'{{ mysql_root_password }}' -e 'SELECT MEMBER_STATE FROM performance_schema.replication_group_members WHERE MEMBER_HOST=\"{{ ansible_default_ipv4.address }}\";'" --one-line 2>/dev/null | grep -o "ONLINE\|RECOVERING\|ERROR" || echo "UNKNOWN")
        
        if [ "$status" = "ONLINE" ]; then
            log_success "节点 $node 已成功重新加入集群"
            return 0
        fi
        
        log_info "等待节点状态变为ONLINE... (当前状态: $status)"
        sleep 5
        wait_time=$((wait_time + 5))
    done
    
    log_error "节点 $node 重新加入集群超时"
    return 1
}

# 升级单个节点
upgrade_single_node() {
    local node=$1
    local target_profile=$2
    local force=$3
    
    log_info "开始升级节点 $node 到配置 $target_profile"
    
    # 检查当前配置
    local current_profile=$(ansible $node -m debug -a "var=mysql_hardware_profile" --one-line 2>/dev/null | grep -o "standard\|high_performance" || echo "unknown")
    log_info "当前配置: $current_profile"
    
    if [ "$current_profile" = "$target_profile" ]; then
        log_warning "节点 $node 已经是 $target_profile 配置，跳过升级"
        return 0
    fi
    
    # 检查是否为主节点
    local node_role=$(check_if_primary $node)
    if [ "$node_role" = "PRIMARY" ] && [ "$force" != "true" ]; then
        log_warning "节点 $node 是主节点，升级可能影响写入操作"
        read -p "是否继续? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "用户取消操作"
            return 1
        fi
    fi
    
    # 从集群中移除节点
    remove_node_from_cluster $node
    
    # 更新配置并重新部署
    log_info "更新节点配置..."
    ansible-playbook -i inventory/hosts.yml playbooks/deploy.yml \
        --limit $node \
        --extra-vars "mysql_hardware_profile=$target_profile" \
        --tags "mysql-config"
    
    if [ $? -eq 0 ]; then
        log_success "配置更新成功"
    else
        log_error "配置更新失败"
        return 1
    fi
    
    # 重新加入集群
    rejoin_cluster $node
    
    log_success "节点 $node 升级完成"
}

# 主函数
main() {
    local target_profile="standard"
    local check_only=false
    local force=false
    local target_node=""
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--profile)
                target_profile="$2"
                shift 2
                ;;
            -c|--check)
                check_only=true
                shift
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
            *)
                target_node="$1"
                shift
                ;;
        esac
    done
    
    # 验证参数
    if [ -z "$target_node" ]; then
        log_error "请指定目标节点"
        show_help
        exit 1
    fi
    
    if [[ ! "$target_profile" =~ ^(standard|high_performance)$ ]]; then
        log_error "无效的硬件配置: $target_profile"
        show_help
        exit 1
    fi
    
    # 检查Ansible连接
    log_info "检查Ansible连接..."
    if ! ansible $target_node -m ping >/dev/null 2>&1; then
        log_error "无法连接到目标节点: $target_node"
        exit 1
    fi
    
    # 如果只是检查状态
    if [ "$check_only" = true ]; then
        log_info "检查节点状态..."
        check_cluster_status $target_node
        local current_profile=$(ansible $target_node -m debug -a "var=mysql_hardware_profile" --one-line 2>/dev/null | grep -o "standard\|high_performance" || echo "unknown")
        local node_role=$(check_if_primary $target_node)
        
        echo "节点: $target_node"
        echo "当前配置: $current_profile"
        echo "节点角色: $node_role"
        exit 0
    fi
    
    # 执行升级
    if [ "$target_node" = "all" ]; then
        log_info "升级所有节点到配置 $target_profile"
        
        # 获取所有MySQL节点
        local nodes=$(ansible-inventory -i inventory/hosts.yml --list | jq -r '.mysql_cluster.children.mysql_primary.hosts + .mysql_cluster.children.mysql_secondary.hosts | .[]' 2>/dev/null || echo "mysql-node1 mysql-node2 mysql-node3")
        
        for node in $nodes; do
            log_info "升级节点: $node"
            upgrade_single_node $node $target_profile $force
            
            if [ $? -eq 0 ]; then
                log_success "节点 $node 升级成功"
            else
                log_error "节点 $node 升级失败"
                exit 1
            fi
            
            # 等待一段时间再升级下一个节点
            if [ "$node" != "${nodes##* }" ]; then
                log_info "等待30秒后升级下一个节点..."
                sleep 30
            fi
        done
        
        log_success "所有节点升级完成"
    else
        upgrade_single_node $target_node $target_profile $force
    fi
}

# 执行主函数
main "$@" 