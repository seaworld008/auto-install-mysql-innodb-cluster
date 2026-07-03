#!/bin/bash

# MySQL 配置管理脚本
# 用于在不同硬件配置之间切换

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

# 配置文件路径
CONFIG_DIR="inventory/group_vars"
CURRENT_CONFIG="$CONFIG_DIR/all.yml"
BACKUP_DIR="$CONFIG_DIR/backups"

# 单一真相源中的可切换 profile
declare -A CONFIGS=(
    ["8c32g-optimized"]="optimized_8c32g"
    ["original-10k"]="original_10k"
)

declare -A CONFIG_DESCRIPTIONS=(
    ["8c32g-optimized"]="8核32G+4核8G优化配置（默认推荐）- MySQL 2500连接/节点（生产余量版）"
    ["original-10k"]="历史高连接配置 - MySQL 10000连接/节点（仅建议高峰专项场景使用）"
)

# 显示帮助信息
show_help() {
    cat << EOF
MySQL 配置管理脚本

用法:
    $0 [选项]

选项:
    --list                  列出所有可用配置
    --current               显示当前配置
    --switch <config>       切换到指定配置
    --backup                备份当前配置
    --restore <backup>      恢复指定备份
    --validate              验证当前配置
    -h, --help              显示此帮助信息

可用配置:
    8c32g-optimized         切换 mysql_hardware_profile=optimized_8c32g
    original-10k            切换 mysql_hardware_profile=original_10k

示例:
    $0 --list                           # 列出所有配置
    $0 --switch 8c32g-optimized        # 切换到8C32G优化配置
    $0 --backup                         # 备份当前配置
    $0 --validate                       # 验证当前配置
EOF
}

# 创建备份目录
ensure_backup_dir() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        log_info "创建备份目录: $BACKUP_DIR"
    fi
}

# 列出所有可用配置
list_configs() {
    log_step "可用配置列表:"
    echo
    for config in "${!CONFIGS[@]}"; do
        local profile="${CONFIGS[$config]}"
        local desc="${CONFIG_DESCRIPTIONS[$config]}"
        local status="${GREEN}✅ 可用${NC}"

        echo -e "  ${BLUE}$config${NC}: $desc"
        echo -e "    Profile: $profile"
        echo -e "    状态: $status"
        echo
    done
}

# 显示当前配置
show_current() {
    log_step "当前配置信息:"
    echo
    
    if [[ -f "$CURRENT_CONFIG" ]]; then
        local profile=$(python - << 'PY'
import yaml, pathlib
data = yaml.safe_load(pathlib.Path("inventory/group_vars/all.yml").read_text(encoding="utf-8"))
print(data.get("mysql_hardware_profile", "unknown"))
PY
)
        local mysql_conn=$(python - << 'PY'
import yaml, pathlib
data = yaml.safe_load(pathlib.Path("inventory/group_vars/all.yml").read_text(encoding="utf-8"))
profile = data.get("mysql_hardware_profile")
print(data.get("mysql_config_profiles", {}).get(profile, {}).get("max_connections", "unknown"))
PY
)
        local router_conn=$(python - << 'PY'
import yaml, pathlib
data = yaml.safe_load(pathlib.Path("inventory/group_vars/all.yml").read_text(encoding="utf-8"))
print(data.get("mysql_router_4c8g_optimized", {}).get("max_connections", "unknown"))
PY
)
        
        echo "  硬件配置文件: $profile"
        echo "  MySQL连接数: $mysql_conn"
        echo "  Router连接数: $router_conn"
        echo "  配置文件: $CURRENT_CONFIG"
        echo "  文件大小: $(stat -f%z "$CURRENT_CONFIG" 2>/dev/null || stat -c%s "$CURRENT_CONFIG" 2>/dev/null || echo "unknown") bytes"
        echo "  修改时间: $(stat -f%Sm "$CURRENT_CONFIG" 2>/dev/null || stat -c%y "$CURRENT_CONFIG" 2>/dev/null || echo "unknown")"
    else
        log_error "当前配置文件不存在: $CURRENT_CONFIG"
        return 1
    fi
}

# 备份当前配置
backup_current() {
    ensure_backup_dir
    
    if [[ -f "$CURRENT_CONFIG" ]]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_file="$BACKUP_DIR/all-backup-$timestamp.yml"
        
        cp "$CURRENT_CONFIG" "$backup_file"
        log_success "配置已备份到: $backup_file"
    else
        log_error "当前配置文件不存在，无法备份"
        return 1
    fi
}

# 切换配置
switch_config() {
    local target_config="$1"
    
    if [[ -z "$target_config" ]]; then
        log_error "请指定要切换的配置名称"
        echo "使用 --list 查看可用配置"
        return 1
    fi
    
    if [[ ! "${CONFIGS[$target_config]+isset}" ]]; then
        log_error "未知的配置: $target_config"
        echo "使用 --list 查看可用配置"
        return 1
    fi
    
    local target_profile="${CONFIGS[$target_config]}"
    
    # 备份当前配置
    log_info "备份当前配置..."
    backup_current
    
    # 切换 profile
    log_info "切换到配置: $target_config -> mysql_hardware_profile=$target_profile"
    python - "$CURRENT_CONFIG" "$target_profile" << 'PY'
import sys, pathlib, re
path = pathlib.Path(sys.argv[1])
target = sys.argv[2]
text = path.read_text(encoding="utf-8")
new_text, count = re.subn(r'^(mysql_hardware_profile:\s*").*(".*)$', rf'\1{target}\2', text, flags=re.M)
if count != 1:
    raise SystemExit("未找到唯一的 mysql_hardware_profile 配置项")
path.write_text(new_text, encoding="utf-8", newline="\n")
PY
    
    log_success "配置切换完成!"
    echo
    log_info "新配置详情:"
    show_current
    
    echo
    log_warning "建议运行以下命令应用新配置:"
    echo "  ./scripts/deploy_dedicated_routers.sh --production-ready -i inventory/hosts-with-dedicated-routers.yml"
}

# 恢复备份
restore_backup() {
    local backup_name="$1"
    
    if [[ -z "$backup_name" ]]; then
        log_error "请指定要恢复的备份文件名"
        echo "可用备份:"
        ls -la "$BACKUP_DIR/"*.yml 2>/dev/null || echo "  无可用备份"
        return 1
    fi
    
    local backup_file="$BACKUP_DIR/$backup_name"
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "备份文件不存在: $backup_file"
        return 1
    fi
    
    # 备份当前配置
    backup_current
    
    # 恢复备份
    log_info "恢复备份: $backup_name"
    cp "$backup_file" "$CURRENT_CONFIG"
    
    log_success "备份恢复完成!"
    show_current
}

# 验证配置
validate_config() {
    log_step "验证当前配置..."
    
    if [[ ! -f "$CURRENT_CONFIG" ]]; then
        log_error "配置文件不存在: $CURRENT_CONFIG"
        return 1
    fi
    
    # 验证YAML语法
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import yaml
import sys
try:
    with open('$CURRENT_CONFIG', 'r') as f:
        yaml.safe_load(f)
    print('✅ YAML语法正确')
except Exception as e:
    print(f'❌ YAML语法错误: {e}')
    sys.exit(1)
" || return 1
    else
        log_warning "Python3未安装，跳过YAML语法检查"
    fi
    
    # 验证必要字段
    local required_fields=(
        "mysql_version"
        "mysql_hardware_profile"
        "mysql_max_connections"
        "mysql_innodb_buffer_pool_size"
    )
    
    for field in "${required_fields[@]}"; do
        if grep -q "^$field:" "$CURRENT_CONFIG"; then
            echo "✅ $field: 存在"
        else
            echo "❌ $field: 缺失"
        fi
    done
    
    log_success "配置验证完成"
}

# 主函数
main() {
    case "${1:-}" in
        --list)
            list_configs
            ;;
        --current)
            show_current
            ;;
        --switch)
            if [[ $# -lt 2 ]]; then
                log_error "请指定配置名称"
                echo "使用 --list 查看可用配置"
                exit 1
            fi
            switch_config "$2"
            ;;
        --backup)
            backup_current
            ;;
        --restore)
            if [[ $# -lt 2 ]]; then
                log_error "请指定备份文件名"
                exit 1
            fi
            restore_backup "$2"
            ;;
        --validate)
            validate_config
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
