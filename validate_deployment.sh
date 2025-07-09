#!/bin/bash

# MySQL InnoDB Cluster 部署验证脚本
# 这个脚本会全面检查项目的完整性和可部署性

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 计数器
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED_CHECKS++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARNING_CHECKS++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED_CHECKS++))
}

check_item() {
    ((TOTAL_CHECKS++))
    local description="$1"
    local command="$2"
    local expected_result="$3"
    
    echo -n "检查: $description ... "
    
    if eval "$command" >/dev/null 2>&1; then
        if [ -n "$expected_result" ]; then
            local actual_result=$(eval "$command" 2>/dev/null)
            if [[ "$actual_result" == *"$expected_result"* ]]; then
                log_success "$description"
            else
                log_error "$description (期望: $expected_result, 实际: $actual_result)"
            fi
        else
            log_success "$description"
        fi
    else
        log_error "$description"
    fi
}

check_file_exists() {
    ((TOTAL_CHECKS++))
    local file="$1"
    local description="$2"
    
    if [ -f "$file" ]; then
        log_success "$description: $file"
    else
        log_error "$description: $file 不存在"
    fi
}

check_dir_exists() {
    ((TOTAL_CHECKS++))
    local dir="$1"
    local description="$2"
    
    if [ -d "$dir" ]; then
        log_success "$description: $dir"
    else
        log_error "$description: $dir 不存在"
    fi
}

check_yaml_syntax() {
    ((TOTAL_CHECKS++))
    local file="$1"
    
    if command -v python3 >/dev/null 2>&1; then
        if python3 -c "import yaml; yaml.safe_load(open('$file'))" >/dev/null 2>&1; then
            log_success "YAML语法检查: $file"
        else
            log_error "YAML语法检查: $file 语法错误"
        fi
    else
        log_warning "YAML语法检查: $file (缺少python3，跳过检查)"
    fi
}

echo "=================================================================="
echo "             MySQL InnoDB Cluster 部署验证"
echo "=================================================================="
echo "项目路径: $(pwd)"
echo "检查时间: $(date)"
echo

# 1. 检查核心文件结构
log_info "1. 检查核心文件结构"
check_file_exists "deploy.sh" "主部署脚本"
check_file_exists "ansible.cfg" "Ansible配置文件"
check_file_exists "requirements.txt" "Python依赖文件"

# 2. 检查目录结构
log_info "2. 检查目录结构"
check_dir_exists "playbooks" "Playbooks目录"
check_dir_exists "inventory" "Inventory目录"
check_dir_exists "roles" "Roles目录"
check_dir_exists "scripts" "Scripts目录"

# 3. 检查核心playbook文件
log_info "3. 检查核心Playbook文件"
check_file_exists "playbooks/site.yml" "主playbook文件"
check_file_exists "playbooks/install-mysql.yml" "MySQL安装playbook"
check_file_exists "playbooks/configure-cluster.yml" "集群配置playbook"
check_file_exists "playbooks/install-router.yml" "Router安装playbook"

# 4. 检查inventory文件
log_info "4. 检查Inventory配置文件"
check_file_exists "inventory/hosts.yml" "基础hosts文件"
check_file_exists "inventory/hosts-recommended-router.yml" "推荐Router配置"
check_file_exists "inventory/hosts-with-dedicated-routers.yml" "专用Router配置"
check_file_exists "inventory/group_vars/all.yml" "全局变量文件"

# 5. 检查roles结构
log_info "5. 检查Roles结构"
check_dir_exists "roles/mysql-server" "MySQL服务器角色"
check_dir_exists "roles/mysql-cluster" "MySQL集群角色"
check_dir_exists "roles/mysql-router" "MySQL Router角色"
check_file_exists "roles/mysql-server/templates/my.cnf.j2" "MySQL配置模板"
check_file_exists "roles/mysql-router/templates/mysqlrouter.service.j2" "Router服务模板"

# 6. 检查脚本文件
log_info "6. 检查脚本文件"
check_file_exists "scripts/cluster-status.sh" "集群状态检查脚本"
check_file_exists "scripts/setup-servers.sh" "服务器设置脚本"
check_file_exists "scripts/failover-test.sh" "故障转移测试脚本"
check_file_exists "scripts/config_manager.sh" "配置管理脚本"

# 7. 检查YAML语法
log_info "7. 检查YAML文件语法"
for yaml_file in playbooks/*.yml inventory/*.yml inventory/group_vars/*.yml; do
    if [ -f "$yaml_file" ]; then
        check_yaml_syntax "$yaml_file"
    fi
done

# 8. 检查脚本权限和语法
log_info "8. 检查脚本文件"
for script in deploy.sh scripts/*.sh; do
    if [ -f "$script" ]; then
        # 检查是否有正确的shebang
        ((TOTAL_CHECKS++))
        if head -1 "$script" | grep -q "#!/bin/bash"; then
            log_success "Shebang检查: $script"
        else
            log_error "Shebang检查: $script 缺少 #!/bin/bash"
        fi
        
        # 检查脚本语法（如果有bash）
        if command -v bash >/dev/null 2>&1; then
            ((TOTAL_CHECKS++))
            if bash -n "$script" >/dev/null 2>&1; then
                log_success "语法检查: $script"
            else
                log_error "语法检查: $script 有语法错误"
            fi
        fi
    fi
done

# 9. 检查必要的变量定义
log_info "9. 检查关键变量定义"
config_file="inventory/group_vars/all.yml"
if [ -f "$config_file" ]; then
    # 检查关键变量是否定义
    key_vars=("mysql_version" "mysql_root_password" "mysql_cluster_name" "mysql_cluster_user" "mysql_port")
    for var in "${key_vars[@]}"; do
        ((TOTAL_CHECKS++))
        if grep -q "^$var:" "$config_file"; then
            log_success "变量定义: $var"
        else
            log_error "变量定义: $var 未在 $config_file 中定义"
        fi
    done
fi

# 10. 检查Python依赖
log_info "10. 检查Python依赖"
if [ -f "requirements.txt" ]; then
    required_packages=("ansible" "PyMySQL" "mysql-connector-python")
    for package in "${required_packages[@]}"; do
        ((TOTAL_CHECKS++))
        if grep -q "$package" requirements.txt; then
            log_success "依赖包: $package 已在requirements.txt中"
        else
            log_error "依赖包: $package 未在requirements.txt中"
        fi
    done
fi

# 11. 检查系统兼容性
log_info "11. 检查系统兼容性要求"
((TOTAL_CHECKS++))
if command -v python3 >/dev/null 2>&1; then
    log_success "Python3 可用"
else
    log_warning "Python3 未安装（部署时需要）"
fi

((TOTAL_CHECKS++))
if command -v ansible >/dev/null 2>&1; then
    ansible_version=$(ansible --version | head -1 | awk '{print $3}')
    log_success "Ansible 已安装 (版本: $ansible_version)"
else
    log_warning "Ansible 未安装（部署时需要）"
fi

# 12. 检查网络配置示例
log_info "12. 检查网络配置示例"
inventory_files=("inventory/hosts.yml" "inventory/hosts-recommended-router.yml")
for inv_file in "${inventory_files[@]}"; do
    if [ -f "$inv_file" ]; then
        ((TOTAL_CHECKS++))
        if grep -q "192.168.1" "$inv_file"; then
            log_warning "网络配置: $inv_file 使用示例IP地址，部署前需要修改"
        else
            log_success "网络配置: $inv_file 已自定义IP地址"
        fi
        
        ((TOTAL_CHECKS++))
        if grep -q "your_password" "$inv_file"; then
            log_warning "密码配置: $inv_file 使用示例密码，部署前需要修改"
        else
            log_success "密码配置: $inv_file 已自定义密码"
        fi
    fi
done

# 13. 检查文档完整性
log_info "13. 检查文档完整性"
doc_files=("README.md" "DEPLOYMENT_COMPLETE_GUIDE.md" "TROUBLESHOOTING.md" "QUICK_START.md")
for doc in "${doc_files[@]}"; do
    check_file_exists "$doc" "文档文件"
done

# 14. 检查配置文件一致性
log_info "14. 检查配置文件一致性"
config_files=("inventory/group_vars/all.yml" "inventory/group_vars/all-8c32g-optimized.yml")
for config in "${config_files[@]}"; do
    if [ -f "$config" ]; then
        ((TOTAL_CHECKS++))
        cluster_name=$(grep "mysql_cluster_name:" "$config" | awk '{print $2}' | tr -d '"')
        if [ "$cluster_name" = "prodCluster" ]; then
            log_success "集群名称一致性: $config"
        else
            log_warning "集群名称一致性: $config 使用了不同的集群名称: $cluster_name"
        fi
    fi
done

# 15. 检查模板文件
log_info "15. 检查模板文件完整性"
template_files=("roles/mysql-server/templates/my.cnf.j2" "roles/mysql-router/templates/mysqlrouter.service.j2")
for template in "${template_files[@]}"; do
    if [ -f "$template" ]; then
        ((TOTAL_CHECKS++))
        # 检查模板是否包含变量
        if grep -q "{{" "$template"; then
            log_success "模板变量: $template 包含Ansible变量"
        else
            log_warning "模板变量: $template 可能缺少必要的变量"
        fi
    fi
done

# 16. 最终安全检查
log_info "16. 安全配置检查"
((TOTAL_CHECKS++))
if grep -r "password" inventory/group_vars/ | grep -v "your_password" | grep -q "P@ss"; then
    log_success "密码强度: 使用了强密码模式"
else
    log_warning "密码强度: 建议使用更强的密码模式"
fi

# 总结报告
echo
echo "=================================================================="
echo "                         检查结果汇总"
echo "=================================================================="
echo -e "总检查项目: ${BLUE}$TOTAL_CHECKS${NC}"
echo -e "通过检查: ${GREEN}$PASSED_CHECKS${NC}"
echo -e "警告项目: ${YELLOW}$WARNING_CHECKS${NC}"
echo -e "失败项目: ${RED}$FAILED_CHECKS${NC}"
echo

# 计算成功率
success_rate=$(( (PASSED_CHECKS * 100) / TOTAL_CHECKS ))
echo -e "成功率: ${BLUE}$success_rate%${NC}"

# 总体评估
if [ $FAILED_CHECKS -eq 0 ]; then
    if [ $WARNING_CHECKS -eq 0 ]; then
        echo -e "\n${GREEN}✅ 项目完全通过验证，可以安全部署！${NC}"
        exit 0
    else
        echo -e "\n${YELLOW}⚠️  项目基本通过验证，但有 $WARNING_CHECKS 个警告项需要注意${NC}"
        echo "请检查警告项目，建议解决后再部署"
        exit 1
    fi
else
    echo -e "\n${RED}❌ 项目验证失败，有 $FAILED_CHECKS 个严重问题需要修复${NC}"
    echo "请修复所有失败项目后再进行部署"
    exit 2
fi 