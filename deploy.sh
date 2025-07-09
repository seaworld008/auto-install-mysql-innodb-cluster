#!/bin/bash

# MySQL InnoDB Cluster 一键部署脚本
# 使用方法: ./deploy.sh [action]
# action: install, cluster, router, all, status, clean

set -e

ACTION=${1:-"all"}
INVENTORY_FILE="inventory/hosts.yml"

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

# 检查依赖
check_dependencies() {
    log_info "检查依赖..."
    
    if ! command -v ansible-playbook &> /dev/null; then
        log_error "Ansible未安装，请先安装Ansible"
        exit 1
    fi
    
    if [ ! -f "$INVENTORY_FILE" ]; then
        log_error "Inventory文件不存在: $INVENTORY_FILE"
        exit 1
    fi
    
    log_success "依赖检查通过"
}

# 检查主机连通性
check_connectivity() {
    log_info "检查主机连通性..."
    
    if ansible all -i "$INVENTORY_FILE" -m ping > /dev/null 2>&1; then
        log_success "所有主机连通性正常"
    else
        log_error "主机连通性检查失败，请检查inventory配置和SSH连接"
        exit 1
    fi
}

# 安装MySQL服务器
install_mysql() {
    log_info "开始安装MySQL服务器..."
    
    ansible-playbook -i "$INVENTORY_FILE" playbooks/install-mysql.yml
    
    if [ $? -eq 0 ]; then
        log_success "MySQL服务器安装完成"
    else
        log_error "MySQL服务器安装失败"
        exit 1
    fi
}

# 配置InnoDB Cluster
configure_cluster() {
    log_info "开始配置InnoDB Cluster..."
    
    ansible-playbook -i "$INVENTORY_FILE" playbooks/configure-cluster.yml
    
    if [ $? -eq 0 ]; then
        log_success "InnoDB Cluster配置完成"
    else
        log_error "InnoDB Cluster配置失败"
        exit 1
    fi
}

# 安装MySQL Router
install_router() {
    log_info "开始安装MySQL Router..."
    
    if ansible-playbook -i "$INVENTORY_FILE" playbooks/install-router.yml; then
        log_success "MySQL Router安装完成"
    else
        log_warning "MySQL Router安装失败（可选组件）"
    fi
}

# 检查集群状态
check_status() {
    log_info "检查集群状态..."
    
    # 获取主节点IP
    PRIMARY_HOST=$(ansible-inventory -i "$INVENTORY_FILE" --list | jq -r '.mysql_primary.hosts | keys[0]' 2>/dev/null || echo "mysql-node1")
    PRIMARY_IP=$(ansible-inventory -i "$INVENTORY_FILE" --host "$PRIMARY_HOST" | jq -r '.ansible_host' 2>/dev/null || echo "192.168.1.10")
    
    if [ -f "scripts/cluster-status.sh" ]; then
        chmod +x scripts/cluster-status.sh
        ./scripts/cluster-status.sh "$PRIMARY_IP"
    else
        log_warning "集群状态检查脚本不存在"
    fi
}

# 清理环境
clean_environment() {
    log_warning "开始清理MySQL环境..."
    
    read -p "确定要清理所有MySQL相关服务吗？这将删除所有数据！(y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ansible all -i "$INVENTORY_FILE" -b -m shell -a "systemctl stop mysqld mysqlrouter || true"
        ansible all -i "$INVENTORY_FILE" -b -m shell -a "yum remove -y mysql-* || true"
        ansible all -i "$INVENTORY_FILE" -b -m shell -a "rm -rf /var/lib/mysql /var/log/mysql* /etc/my.cnf /var/lib/mysqlrouter || true"
        log_success "环境清理完成"
    else
        log_info "取消清理操作"
    fi
}

# 显示帮助信息
show_help() {
    echo "MySQL InnoDB Cluster 部署脚本"
    echo
    echo "使用方法: $0 [action]"
    echo
    echo "可用操作:"
    echo "  install  - 仅安装MySQL服务器"
    echo "  cluster  - 仅配置InnoDB Cluster"
    echo "  router   - 仅安装MySQL Router"
    echo "  all      - 完整安装（默认）"
    echo "  status   - 检查集群状态"
    echo "  clean    - 清理环境"
    echo "  help     - 显示此帮助信息"
    echo
    echo "示例:"
    echo "  $0 all      # 完整安装"
    echo "  $0 status   # 检查状态"
    echo "  $0 clean    # 清理环境"
}

# 主函数
main() {
    echo "=== MySQL InnoDB Cluster 部署工具 ==="
    echo "操作: $ACTION"
    echo "时间: $(date)"
    echo
    
    case $ACTION in
        "install")
            check_dependencies
            check_connectivity
            install_mysql
            ;;
        "cluster")
            check_dependencies
            check_connectivity
            configure_cluster
            ;;
        "router")
            check_dependencies
            check_connectivity
            install_router
            ;;
        "all")
            check_dependencies
            check_connectivity
            install_mysql
            configure_cluster
            install_router
            log_success "MySQL InnoDB Cluster 部署完成！"
            echo
            check_status
            ;;
        "status")
            check_status
            ;;
        "clean")
            check_dependencies
            clean_environment
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            log_error "未知操作: $ACTION"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main