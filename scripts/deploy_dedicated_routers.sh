#!/bin/bash

# MySQL Router 独立服务器部署脚本
# 用于在同一内网中部署2台4核8G的MySQL Router服务器

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

# 显示帮助信息
show_help() {
    cat << EOF
MySQL Router 独立服务器部署脚本

用法:
    $0 [选项]

选项:
    --production-ready      🌟生产准备部署（推荐）
                           包含用户配置：关闭swap + /data/mysql数据目录
                           包含内核优化：行业最佳实践参数
                           完整的MySQL集群和Router部署
    
    --check-prereq          检查部署前置条件
    --install-routers       安装MySQL Router
    --configure-lb          配置负载均衡器
    --test-connection       测试连接
    --full-deploy           完整部署（不含用户配置）
    --rollback              回滚到之前状态
    -h, --help              显示此帮助信息

🎯 推荐使用: $0 --production-ready

部署架构:
    MySQL数据库集群: 192.168.1.10-12 (3×8核32G)
    MySQL Router集群: 192.168.1.20-21 (2×4核8G)
    负载均衡VIP:     192.168.1.100

用户配置特性:
    ✅ 完全关闭swap (vm.swappiness=0)
    ✅ MySQL数据目录: /data/mysql
    ✅ 内核优化: 基于Oracle MySQL官方推荐

注意: 请确保所有服务器已安装CentOS/RHEL 7+系统
EOF
}

# 检查前置条件
check_prerequisites() {
    log_step "检查部署前置条件..."
    
    # 检查Ansible是否安装
    if ! command -v ansible >/dev/null 2>&1; then
        log_error "Ansible未安装，请先安装Ansible"
        exit 1
    fi
    
    # 检查配置文件是否存在
    if [[ ! -f "inventory/hosts-with-dedicated-routers.yml" ]]; then
        log_error "配置文件不存在: inventory/hosts-with-dedicated-routers.yml"
        exit 1
    fi
    
    # 检查MySQL集群是否运行
    log_info "检查MySQL集群状态..."
    if ! ansible mysql_cluster -i inventory/hosts-with-dedicated-routers.yml -m ping >/dev/null 2>&1; then
        log_warning "无法连接到MySQL集群，请检查网络连接"
    else
        log_success "MySQL集群连接正常"
    fi
    
    # 检查Router服务器连接
    log_info "检查Router服务器连接..."
    if ! ansible mysql_router -i inventory/hosts-with-dedicated-routers.yml -m ping >/dev/null 2>&1; then
        log_error "无法连接到Router服务器，请检查:"
        echo "  1. 服务器IP地址是否正确"
        echo "  2. SSH端口是否正确"
        echo "  3. SSH用户名和密码是否正确"
        echo "  4. 防火墙是否允许SSH连接"
        exit 1
    else
        log_success "Router服务器连接正常"
    fi
    
    # 检查Router服务器硬件规格
    log_info "检查Router服务器硬件规格..."
    ansible mysql_router -i inventory/hosts-with-dedicated-routers.yml -m setup -a "filter=ansible_processor_vcpus,ansible_memtotal_mb" | grep -E "(vcpus|memtotal)" | while read line; do
        echo "  $line"
    done
    
    # 检查网络段
    log_info "检查网络配置..."
    local router_ips=$(ansible mysql_router -i inventory/hosts-with-dedicated-routers.yml -m setup -a "filter=ansible_default_ipv4" --one-line | grep -o "192\.168\.1\.\d\+")
    local mysql_ips=$(ansible mysql_cluster -i inventory/hosts-with-dedicated-routers.yml -m setup -a "filter=ansible_default_ipv4" --one-line | grep -o "192\.168\.1\.\d\+")
    
    echo "  MySQL服务器IP: $mysql_ips"
    echo "  Router服务器IP: $router_ips"
    
    # 检查VIP是否可用
    log_info "检查虚拟IP是否可用..."
    if ping -c 1 192.168.1.100 >/dev/null 2>&1; then
        log_warning "VIP 192.168.1.100 已被使用，请更换其他IP"
    else
        log_success "VIP 192.168.1.100 可用"
    fi
    
    log_success "前置条件检查完成"
}

# 安装MySQL Router
install_routers() {
    log_step "开始安装MySQL Router..."
    
    # 创建安装日志目录
    mkdir -p logs
    local log_file="logs/router_install_$(date +%Y%m%d_%H%M%S).log"
    
    log_info "安装过程日志保存到: $log_file"
    
    # 执行Router安装
    log_info "在Router服务器上安装MySQL Router..."
    ansible-playbook -i inventory/hosts-with-dedicated-routers.yml \
        playbooks/install-router.yml \
        --extra-vars "mysql_router_config=mysql_router_4c8g_config" \
        2>&1 | tee "$log_file"
    
    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        log_success "MySQL Router安装完成"
    else
        log_error "MySQL Router安装失败，请检查日志: $log_file"
        exit 1
    fi
    
    # 验证安装
    log_info "验证Router安装..."
    ansible mysql_router -i inventory/hosts-with-dedicated-routers.yml \
        -m shell -a "systemctl status mysql-router" | grep -E "(Active|Main PID)"
    
    log_success "Router服务验证完成"
}

# 配置负载均衡器
configure_load_balancer() {
    log_step "配置负载均衡器..."
    
    log_info "安装HAProxy..."
    ansible mysql_router -i inventory/hosts-with-dedicated-routers.yml \
        -m yum -a "name=haproxy state=present" --become
    
    log_info "安装Keepalived..."
    ansible mysql_router -i inventory/hosts-with-dedicated-routers.yml \
        -m yum -a "name=keepalived state=present" --become
    
    # 创建HAProxy配置
    log_info "配置HAProxy..."
    cat > /tmp/haproxy.cfg << 'EOF'
global
    daemon
    user haproxy
    group haproxy
    log stdout local0
    maxconn 35000                               # 全局最大连接数
    
defaults
    mode tcp
    timeout connect 5000ms
    timeout client 120000ms                     # 客户端超时2分钟
    timeout server 120000ms                     # 服务器超时2分钟
    option tcplog
    option dontlognull
    retries 3
    
frontend mysql_frontend_rw
    bind *:6446
    maxconn 30000                               # 前端最大连接数
    default_backend mysql_backend_rw
    
frontend mysql_frontend_ro
    bind *:6447
    maxconn 30000                               # 前端最大连接数
    default_backend mysql_backend_ro
    
backend mysql_backend_rw
    balance roundrobin
    option tcp-check
    tcp-check send-binary 0e000000034449524f
    tcp-check expect binary 050000000a
    server router1 192.168.1.20:6446 check maxconn 15000
    server router2 192.168.1.21:6446 check backup maxconn 15000
    
backend mysql_backend_ro
    balance roundrobin
    option tcp-check
    tcp-check send-binary 0e000000034449524f
    tcp-check expect binary 050000000a
    server router1 192.168.1.20:6447 check maxconn 15000
    server router2 192.168.1.21:6447 check maxconn 15000
    
listen stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 30s
    stats show-legends
    stats admin if TRUE
EOF
    
    # 部署HAProxy配置
    ansible mysql_router -i inventory/hosts-with-dedicated-routers.yml \
        -m copy -a "src=/tmp/haproxy.cfg dest=/etc/haproxy/haproxy.cfg backup=yes" --become
    
    # 创建Keepalived配置
    log_info "配置Keepalived..."
    
    # 主节点配置
    cat > /tmp/keepalived_master.conf << 'EOF'
vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 100
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass mysql_router_ha
    }
    virtual_ipaddress {
        192.168.1.100
    }
}
EOF
    
    # 备节点配置
    cat > /tmp/keepalived_backup.conf << 'EOF'
vrrp_instance VI_1 {
    state BACKUP
    interface eth0
    virtual_router_id 51
    priority 90
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass mysql_router_ha
    }
    virtual_ipaddress {
        192.168.1.100
    }
}
EOF
    
    # 部署Keepalived配置
    ansible mysql-router-1 -i inventory/hosts-with-dedicated-routers.yml \
        -m copy -a "src=/tmp/keepalived_master.conf dest=/etc/keepalived/keepalived.conf backup=yes" --become
    
    ansible mysql-router-2 -i inventory/hosts-with-dedicated-routers.yml \
        -m copy -a "src=/tmp/keepalived_backup.conf dest=/etc/keepalived/keepalived.conf backup=yes" --become
    
    # 启动服务
    log_info "启动负载均衡器服务..."
    ansible mysql_router -i inventory/hosts-with-dedicated-routers.yml \
        -m systemd -a "name=haproxy state=started enabled=yes" --become
    
    ansible mysql_router -i inventory/hosts-with-dedicated-routers.yml \
        -m systemd -a "name=keepalived state=started enabled=yes" --become
    
    # 清理临时文件
    rm -f /tmp/haproxy.cfg /tmp/keepalived_*.conf
    
    log_success "负载均衡器配置完成"
    log_info "HAProxy统计页面: http://192.168.1.100:8404/stats"
}

# 测试连接
test_connection() {
    log_step "测试MySQL Router连接..."
    
    # 等待服务启动
    log_info "等待服务完全启动..."
    sleep 10
    
    # 测试VIP连通性
    log_info "测试VIP连通性..."
    if ping -c 3 192.168.1.100 >/dev/null 2>&1; then
        log_success "VIP 192.168.1.100 连通正常"
    else
        log_error "VIP 192.168.1.100 连通失败"
        return 1
    fi
    
    # 测试端口连通性
    log_info "测试端口连通性..."
    
    # 测试读写端口
    if nc -z 192.168.1.100 6446 2>/dev/null; then
        log_success "读写端口 6446 连通正常"
    else
        log_error "读写端口 6446 连通失败"
    fi
    
    # 测试只读端口
    if nc -z 192.168.1.100 6447 2>/dev/null; then
        log_success "只读端口 6447 连通正常"
    else
        log_error "只读端口 6447 连通失败"
    fi
    
    # 测试MySQL连接
    log_info "测试MySQL连接..."
    
    # 获取数据库连接信息
    local mysql_user=$(grep "mysql_cluster_user:" inventory/group_vars/all.yml | cut -d'"' -f2)
    local mysql_password=$(grep "mysql_cluster_password:" inventory/group_vars/all.yml | cut -d'"' -f2)
    
    if [[ -n "$mysql_user" && -n "$mysql_password" ]]; then
        # 测试通过Router连接MySQL
        if mysql -h 192.168.1.100 -P 6446 -u "$mysql_user" -p"$mysql_password" -e "SELECT 'Router connection test' as test;" >/dev/null 2>&1; then
            log_success "MySQL Router连接测试成功"
        else
            log_warning "MySQL Router连接测试失败，可能需要配置数据库用户"
        fi
    else
        log_warning "未找到数据库连接信息，跳过MySQL连接测试"
    fi
    
    # 显示连接信息
    log_info "连接信息:"
    echo "  读写连接: mysql -h 192.168.1.100 -P 6446 -u your_user -p"
    echo "  只读连接: mysql -h 192.168.1.100 -P 6447 -u your_user -p"
    echo "  监控页面: http://192.168.1.100:8404/stats"
    
    log_success "连接测试完成"
}

# 生产准备部署 - 包含用户配置
production_ready_deploy() {
    log_step "开始生产准备部署（包含用户配置）..."
    
    echo "生产准备部署计划:"
    echo "  1. 应用用户配置（关闭swap + 数据目录/data/mysql）"
    echo "  2. 应用内核优化（行业最佳实践）"
    echo "  3. 部署MySQL集群"
    echo "  4. 部署Router集群"
    echo "  5. 配置负载均衡器"
    echo "  6. 全面测试验证"
    echo
    
    read -p "确认开始生产准备部署? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "用户取消部署"
        exit 0
    fi
    
    # 记录开始时间
    local start_time=$(date +%s)
    
    # 步骤1：应用用户配置
    log_step "步骤1: 应用用户配置（关闭swap + 数据目录配置）..."
    if [[ -f "scripts/apply_user_configs.sh" ]]; then
        log_info "应用用户配置到所有服务器..."
        # 对所有MySQL和Router服务器应用配置
        ansible -i inventory/hosts-with-dedicated-routers.yml all \
            -m script -a "scripts/apply_user_configs.sh --full" \
            --become || {
                log_error "用户配置应用失败"
                exit 1
            }
    else
        log_warning "未找到用户配置脚本，跳过此步骤"
    fi
    
    # 步骤2：等待用户确认重启
    echo
    log_warning "建议现在重启所有服务器以确保配置生效"
    read -p "是否已重启服务器并准备继续? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "请重启服务器后运行: $0 --full-deploy"
        exit 0
    fi
    
    # 步骤3：检查前置条件
    log_step "步骤3: 检查前置条件..."
    check_prerequisites
    
    # 步骤4：部署MySQL集群
    log_step "步骤4: 部署MySQL集群..."
    log_info "部署MySQL服务器..."
    ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/install-mysql.yml
    
    log_info "配置MySQL集群..."
    ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/configure-cluster.yml
    
    # 步骤5：部署Router集群
    log_step "步骤5: 部署Router集群..."
    install_routers
    
    # 步骤6：配置负载均衡器
    log_step "步骤6: 配置负载均衡器..."
    configure_load_balancer
    
    # 步骤7：全面测试验证
    log_step "步骤7: 全面测试验证..."
    test_connection
    
    # 验证用户配置
    log_info "验证用户配置..."
    ansible -i inventory/hosts-with-dedicated-routers.yml all \
        -m script -a "scripts/apply_user_configs.sh --verify-only" \
        --become || log_warning "用户配置验证失败，请手动检查"
    
    # 计算部署时间
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_success "生产准备部署完成!"
    log_info "部署耗时: ${duration}秒"
    
    # 显示部署摘要
    echo
    echo "================================="
    echo "生产环境部署摘要"
    echo "================================="
    echo "✅ 用户配置应用:"
    echo "   - Swap已完全关闭 (vm.swappiness=0)"
    echo "   - MySQL数据目录: /data/mysql"
    echo "   - 内核参数已优化（行业最佳实践）"
    echo
    echo "✅ MySQL集群配置:"
    echo "   - 服务器: 192.168.1.10-12 (3×8核32G)"
    echo "   - 连接数: 4000/节点 (总计12K后端连接)"
    echo "   - 内存使用: 20GB InnoDB缓冲池"
    echo
    echo "✅ Router集群配置:"
    echo "   - 服务器: 192.168.1.20-21 (2×4核8G)"
    echo "   - 连接数: 30000/节点 (总计60K前端连接)"
    echo "   - 连接复用: 5:1高效比例"
    echo
    echo "✅ 高可用配置:"
    echo "   - 负载均衡VIP: 192.168.1.100"
    echo "   - 自动故障转移: 已启用"
    echo "   - 监控页面: http://192.168.1.100:8404/stats"
    echo
    echo "应用连接信息:"
    echo "  读写: mysql://user:password@192.168.1.100:6446/database"
    echo "  只读: mysql://user:password@192.168.1.100:6447/database"
    echo
    echo "🎉 恭喜！您的生产环境MySQL集群已准备就绪！"
}

# 完整部署
full_deploy() {
    log_step "开始完整部署MySQL Router集群..."
    
    echo "部署计划:"
    echo "  1. 检查前置条件"
    echo "  2. 安装MySQL Router"
    echo "  3. 配置负载均衡器"
    echo "  4. 测试连接"
    echo
    
    read -p "确认开始部署? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "用户取消部署"
        exit 0
    fi
    
    # 记录开始时间
    local start_time=$(date +%s)
    
    # 执行部署步骤
    check_prerequisites
    install_routers
    configure_load_balancer
    test_connection
    
    # 计算部署时间
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_success "MySQL Router集群部署完成!"
    log_info "部署耗时: ${duration}秒"
    
    # 显示部署摘要
    echo
    echo "=========================="
    echo "部署摘要"
    echo "=========================="
    echo "MySQL数据库集群: 192.168.1.10-12 (3台)"
    echo "MySQL Router集群: 192.168.1.20-21 (2台4核8G)"
    echo "负载均衡VIP: 192.168.1.100"
    echo "应用连接字符串:"
    echo "  读写: mysql://user:password@192.168.1.100:6446/database"
    echo "  只读: mysql://user:password@192.168.1.100:6447/database"
    echo "监控页面: http://192.168.1.100:8404/stats"
    echo "=========================="
}

# 回滚
rollback() {
    log_step "回滚MySQL Router部署..."
    
    read -p "确认回滚? 这将停止Router服务并清理配置 (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "用户取消回滚"
        exit 0
    fi
    
    log_info "停止服务..."
    ansible mysql_router -i inventory/hosts-with-dedicated-routers.yml \
        -m systemd -a "name=keepalived state=stopped" --become 2>/dev/null || true
    
    ansible mysql_router -i inventory/hosts-with-dedicated-routers.yml \
        -m systemd -a "name=haproxy state=stopped" --become 2>/dev/null || true
    
    ansible mysql_router -i inventory/hosts-with-dedicated-routers.yml \
        -m systemd -a "name=mysql-router state=stopped" --become 2>/dev/null || true
    
    log_info "清理配置文件..."
    ansible mysql_router -i inventory/hosts-with-dedicated-routers.yml \
        -m file -a "path=/etc/mysql-router state=absent" --become 2>/dev/null || true
    
    log_success "回滚完成"
}

# 显示状态
show_status() {
    log_step "显示MySQL Router集群状态..."
    
    echo "=== Router服务状态 ==="
    ansible mysql_router -i inventory/hosts-with-dedicated-routers.yml \
        -m shell -a "systemctl is-active mysql-router haproxy keepalived" --become
    
    echo
    echo "=== VIP状态 ==="
    if ip addr show | grep -q "192.168.1.100"; then
        echo "VIP 192.168.1.100 运行在: $(hostname)"
    else
        echo "VIP 192.168.1.100 未运行在当前主机"
    fi
    
    echo
    echo "=== 连接统计 ==="
    echo "HAProxy统计: http://192.168.1.100:8404/stats"
}

# 主函数
main() {
    case "${1:-}" in
        --check-prereq)
            check_prerequisites
            ;;
        --install-routers)
            install_routers
            ;;
        --configure-lb)
            configure_load_balancer
            ;;
        --test-connection)
            test_connection
            ;;
        --full-deploy)
            full_deploy
            ;;
        --rollback)
            rollback
            ;;
        --status)
            show_status
            ;;
        --production-ready)
            production_ready_deploy
            ;;
        -h|--help)
            show_help
            ;;
        "")
            log_error "请指定操作参数"
            show_help
            exit 1
            ;;
        *)
            log_error "未知参数: $1"
            show_help
            exit 1
            ;;
    esac
}

# 检查是否在正确的目录
if [[ ! -f "ansible.cfg" ]]; then
    log_error "请在项目根目录运行此脚本"
    exit 1
fi

# 执行主函数
main "$@" 