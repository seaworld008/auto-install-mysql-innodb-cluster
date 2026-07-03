#!/bin/bash

# MySQL InnoDB Cluster 用户配置应用脚本
# 功能：
# 1. 完全关闭swap内存
# 2. 修改MySQL数据目录为 /data/mysql

set -euo pipefail

# 配置变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 日志函数
log_info() {
    echo "[信息] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo "[成功] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo "[错误] $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_step() {
    echo ""
    echo "=========================================="
    echo "[步骤] $1"
    echo "=========================================="
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行，请使用 sudo"
        exit 1
    fi
}

# 备份当前配置
backup_configs() {
    log_step "备份当前配置..."
    
    local backup_dir="/root/mysql_config_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # 备份fstab
    if [[ -f /etc/fstab ]]; then
        cp /etc/fstab "$backup_dir/fstab.backup"
        log_info "已备份 /etc/fstab"
    fi
    
    # 备份sysctl配置
    if [[ -f /etc/sysctl.d/99-mysql-stable-optimization.conf ]]; then
        cp /etc/sysctl.d/99-mysql-stable-optimization.conf "$backup_dir/"
        log_info "已备份内核优化配置"
    fi
    
    # 备份MySQL配置
    if [[ -f /etc/my.cnf ]]; then
        cp /etc/my.cnf "$backup_dir/my.cnf.backup"
        log_info "已备份MySQL配置"
    fi
    
    log_success "配置备份完成: $backup_dir"
}

# 关闭swap并永久禁用
disable_swap() {
    log_step "关闭swap内存..."
    
    # 检查当前swap状态
    local swap_usage=$(free | grep Swap | awk '{print $2}')
    if [[ "$swap_usage" -eq 0 ]]; then
        log_info "系统当前未启用swap"
    else
        log_info "当前swap使用情况:"
        free -h | grep -E "(Mem|Swap)"
        
        # 立即关闭所有swap
        log_info "正在关闭所有swap分区..."
        swapoff -a
        
        log_info "关闭后的内存状态:"
        free -h | grep -E "(Mem|Swap)"
    fi
    
    # 永久禁用swap（修改fstab）
    if [[ -f /etc/fstab ]]; then
        log_info "正在修改 /etc/fstab 以永久禁用swap..."
        sed -i.bak_$(date +%Y%m%d_%H%M%S) 's/^[^#].*swap.*/#&/' /etc/fstab
        
        log_info "fstab中的swap条目已注释:"
        grep -E "(swap|#.*swap)" /etc/fstab || true
    fi
    
    log_success "Swap已完全关闭并永久禁用"
}

# 创建MySQL数据目录
create_mysql_datadir() {
    log_step "创建MySQL数据目录 /data/mysql..."
    
    # 创建/data目录
    if [[ ! -d /data ]]; then
        mkdir -p /data
        log_info "已创建 /data 目录"
    fi
    
    # 创建MySQL数据目录
    if [[ ! -d /data/mysql ]]; then
        mkdir -p /data/mysql
        log_info "已创建 /data/mysql 目录"
    fi
    
    # 设置正确的权限
    chown mysql:mysql /data/mysql 2>/dev/null || {
        log_info "mysql用户不存在，将在MySQL安装后设置权限"
    }
    chmod 750 /data/mysql
    
    log_success "MySQL数据目录创建完成: /data/mysql"
}

# 迁移现有MySQL数据（如果存在）
migrate_mysql_data() {
    log_step "检查是否需要迁移现有MySQL数据..."
    
    local old_datadir="/var/lib/mysql"
    local new_datadir="/data/mysql"
    
    if [[ -d "$old_datadir" && "$(ls -A $old_datadir 2>/dev/null)" ]]; then
        log_info "发现现有MySQL数据在 $old_datadir"
        
        # 检查MySQL服务状态
        if systemctl is-active --quiet mysqld 2>/dev/null; then
            log_info "正在停止MySQL服务进行数据迁移..."
            systemctl stop mysqld
        fi
        
        # 迁移数据
        log_info "正在迁移数据从 $old_datadir 到 $new_datadir..."
        rsync -av "$old_datadir/" "$new_datadir/"
        
        # 备份旧数据目录
        local backup_dir="/root/mysql_data_backup_$(date +%Y%m%d_%H%M%S)"
        mv "$old_datadir" "$backup_dir"
        log_info "旧数据已备份到: $backup_dir"
        
        # 设置权限
        chown -R mysql:mysql "$new_datadir" 2>/dev/null || true
        chmod -R 750 "$new_datadir"
        
        log_success "MySQL数据迁移完成"
    else
        log_info "未发现现有MySQL数据，无需迁移"
    fi
}

# 应用内核优化配置（关闭swap）
apply_kernel_optimization() {
    log_step "应用内核优化配置（关闭swap）..."
    
    if [[ -f "$PROJECT_ROOT/scripts/optimize_mysql_kernel_stable.sh" ]]; then
        log_info "使用更新的内核优化脚本..."
        bash "$PROJECT_ROOT/scripts/optimize_mysql_kernel_stable.sh"
    else
        log_error "未找到内核优化脚本"
        return 1
    fi
}

# 验证配置
verify_configs() {
    log_step "验证配置更改..."
    
    # 验证swap状态
    local swap_status=$(swapon --show 2>/dev/null || echo "")
    if [[ -z "$swap_status" ]]; then
        log_success "✓ Swap已完全关闭"
    else
        log_error "✗ Swap仍然活动:"
        echo "$swap_status"
    fi
    
    # 验证内存状态
    echo ""
    echo "当前内存状态:"
    free -h
    
    # 验证数据目录
    if [[ -d /data/mysql ]]; then
        log_success "✓ MySQL数据目录已创建: /data/mysql"
        ls -la /data/mysql || true
    else
        log_error "✗ MySQL数据目录创建失败"
    fi
    
    # 验证fstab
    local fstab_swap=$(grep -v "^#" /etc/fstab | grep swap || echo "")
    if [[ -z "$fstab_swap" ]]; then
        log_success "✓ fstab中的swap条目已禁用"
    else
        log_error "✗ fstab中仍有活动的swap条目"
    fi
    
    # 验证内核参数
    local swappiness=$(sysctl -n vm.swappiness 2>/dev/null || echo "未设置")
    log_info "当前 vm.swappiness 值: $swappiness (应该为0)"
}

# 显示使用说明
show_usage() {
    echo "MySQL InnoDB Cluster 用户配置应用脚本"
    echo ""
    echo "功能："
    echo "  1. 完全关闭swap内存（vm.swappiness=0）"
    echo "  2. 永久禁用swap（修改fstab）"
    echo "  3. 修改MySQL数据目录为 /data/mysql"
    echo "  4. 迁移现有MySQL数据（如果存在）"
    echo ""
    echo "用法："
    echo "  sudo $0 [选项]"
    echo ""
    echo "选项："
    echo "  --full          完整应用所有配置（默认）"
    echo "  --swap-only     仅关闭swap"
    echo "  --datadir-only  仅修改MySQL数据目录"
    echo "  --verify-only   仅验证当前配置"
    echo "  --help          显示此帮助信息"
    echo ""
}

# 主函数
main() {
    local mode="full"
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --full)
                mode="full"
                shift
                ;;
            --swap-only)
                mode="swap"
                shift
                ;;
            --datadir-only)
                mode="datadir"
                shift
                ;;
            --verify-only)
                mode="verify"
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    echo "MySQL InnoDB Cluster - 用户配置应用脚本"
    echo "=================================================="
    echo "模式: $mode"
    echo "时间: $(date)"
    echo ""
    
    case $mode in
        verify)
            verify_configs
            ;;
        swap)
            check_root
            backup_configs
            disable_swap
            apply_kernel_optimization
            verify_configs
            ;;
        datadir)
            check_root
            backup_configs
            create_mysql_datadir
            migrate_mysql_data
            verify_configs
            ;;
        full)
            check_root
            backup_configs
            disable_swap
            create_mysql_datadir
            migrate_mysql_data
            apply_kernel_optimization
            verify_configs
            ;;
    esac
    
    echo ""
    echo "=================================================="
    echo "配置应用完成！"
    echo ""
    echo "重要提醒："
    echo "1. 系统已完全关闭swap，重启后也不会重新启用"
    echo "2. MySQL数据目录已设置为 /data/mysql" 
    echo "3. 如需重新部署MySQL，请运行："
    echo "   ./scripts/deploy_dedicated_routers.sh --production-ready"
    echo ""
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 