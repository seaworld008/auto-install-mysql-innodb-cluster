#!/bin/bash

# MySQL InnoDB Cluster 服务器配置脚本
# 用于配置3台不同IP和密码的服务器

set -e

echo "=========================================="
echo "MySQL InnoDB Cluster 服务器配置向导"
echo "=========================================="
echo

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 获取服务器信息
echo -e "${BLUE}请输入3台服务器的信息:${NC}"
echo

# 服务器1 (主节点)
echo -e "${GREEN}=== 服务器1 (MySQL主节点 + Router) ===${NC}"
read -p "请输入服务器1的IP地址: " SERVER1_IP
read -p "请输入服务器1的SSH用户名 [root]: " SERVER1_USER
SERVER1_USER=${SERVER1_USER:-root}
read -s -p "请输入服务器1的SSH密码: " SERVER1_PASS
echo

# 服务器2 (从节点)
echo -e "${GREEN}=== 服务器2 (MySQL从节点) ===${NC}"
read -p "请输入服务器2的IP地址: " SERVER2_IP
read -p "请输入服务器2的SSH用户名 [root]: " SERVER2_USER
SERVER2_USER=${SERVER2_USER:-root}
read -s -p "请输入服务器2的SSH密码: " SERVER2_PASS
echo

# 服务器3 (从节点)
echo -e "${GREEN}=== 服务器3 (MySQL从节点) ===${NC}"
read -p "请输入服务器3的IP地址: " SERVER3_IP
read -p "请输入服务器3的SSH用户名 [root]: " SERVER3_USER
SERVER3_USER=${SERVER3_USER:-root}
read -s -p "请输入服务器3的SSH密码: " SERVER3_PASS
echo

# 验证输入
echo
echo -e "${YELLOW}请确认服务器信息:${NC}"
echo "服务器1 (主节点): ${SERVER1_USER}@${SERVER1_IP}"
echo "服务器2 (从节点): ${SERVER2_USER}@${SERVER2_IP}"
echo "服务器3 (从节点): ${SERVER3_USER}@${SERVER3_IP}"
echo

read -p "信息是否正确? (y/n): " CONFIRM
if [[ $CONFIRM != "y" && $CONFIRM != "Y" ]]; then
    echo -e "${RED}配置已取消${NC}"
    exit 1
fi

# 生成inventory文件
echo
echo -e "${BLUE}正在生成inventory配置文件...${NC}"

INVENTORY_FILE="inventory/hosts.yml"
BACKUP_FILE="inventory/hosts.yml.backup.$(date +%Y%m%d_%H%M%S)"

# 备份原文件
if [ -f "$INVENTORY_FILE" ]; then
    cp "$INVENTORY_FILE" "$BACKUP_FILE"
    echo -e "${YELLOW}原配置文件已备份为: $BACKUP_FILE${NC}"
fi

# 生成新的inventory文件
cat > "$INVENTORY_FILE" << EOF
all:
  children:
    mysql_cluster:
      children:
        mysql_primary:
          hosts:
            mysql-node1:
              ansible_host: ${SERVER1_IP}
              ansible_user: ${SERVER1_USER}
              ansible_ssh_pass: "${SERVER1_PASS}"
              mysql_server_id: 1
              mysql_role: primary
        mysql_secondary:
          hosts:
            mysql-node2:
              ansible_host: ${SERVER2_IP}
              ansible_user: ${SERVER2_USER}
              ansible_ssh_pass: "${SERVER2_PASS}"
              mysql_server_id: 2
              mysql_role: secondary
            mysql-node3:
              ansible_host: ${SERVER3_IP}
              ansible_user: ${SERVER3_USER}
              ansible_ssh_pass: "${SERVER3_PASS}"
              mysql_server_id: 3
              mysql_role: secondary
    mysql_router:
      hosts:
        mysql-router1:
          ansible_host: ${SERVER1_IP}
          ansible_user: ${SERVER1_USER}
          ansible_ssh_pass: "${SERVER1_PASS}"
  vars:
    # 全局SSH配置
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
    ansible_python_interpreter: /usr/bin/python3
    ansible_host_key_checking: false
EOF

echo -e "${GREEN}✓ inventory配置文件已生成: $INVENTORY_FILE${NC}"

# 测试连接
echo
echo -e "${BLUE}正在测试服务器连接...${NC}"

# 检查ansible是否安装
if ! command -v ansible &> /dev/null; then
    echo -e "${YELLOW}警告: 未检测到ansible，请先安装ansible${NC}"
    echo "安装命令: pip3 install ansible"
    echo
else
    # 测试连接
    echo "测试服务器1连接..."
    if ansible mysql-node1 -m ping -o; then
        echo -e "${GREEN}✓ 服务器1连接成功${NC}"
    else
        echo -e "${RED}✗ 服务器1连接失败${NC}"
    fi

    echo "测试服务器2连接..."
    if ansible mysql-node2 -m ping -o; then
        echo -e "${GREEN}✓ 服务器2连接成功${NC}"
    else
        echo -e "${RED}✗ 服务器2连接失败${NC}"
    fi

    echo "测试服务器3连接..."
    if ansible mysql-node3 -m ping -o; then
        echo -e "${GREEN}✓ 服务器3连接成功${NC}"
    else
        echo -e "${RED}✗ 服务器3连接失败${NC}"
    fi
fi

echo
echo -e "${GREEN}=========================================="
echo "配置完成!"
echo "=========================================="
echo -e "${NC}"
echo "下一步操作:"
echo "1. 如果连接测试失败，请检查网络和SSH配置"
echo "2. 连接成功后，运行部署脚本: ./deploy.sh"
echo "3. 查看详细文档: docs/SERVER_CONFIGURATION.md"
echo

# 询问是否立即部署
read -p "是否立即开始部署MySQL InnoDB Cluster? (y/n): " DEPLOY_NOW
if [[ $DEPLOY_NOW == "y" || $DEPLOY_NOW == "Y" ]]; then
    echo -e "${BLUE}开始部署...${NC}"
    ./deploy.sh
else
    echo -e "${YELLOW}稍后可以运行 ./deploy.sh 开始部署${NC}"
fi 