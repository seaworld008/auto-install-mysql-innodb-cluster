# 服务器配置指南

## 配置3台不同IP和密码的服务器

### 1. 修改主机清单文件

编辑 `inventory/hosts.yml` 文件，配置你的3台服务器信息：

```yaml
all:
  children:
    mysql_cluster:
      children:
        mysql_primary:
          hosts:
            mysql-node1:
              ansible_host: 你的第一台服务器IP    # 例如: 192.168.1.100
              ansible_user: root                   # SSH用户名
              ansible_ssh_pass: "你的第一台服务器密码"  # SSH密码
              mysql_server_id: 1
              mysql_role: primary
        mysql_secondary:
          hosts:
            mysql-node2:
              ansible_host: 你的第二台服务器IP    # 例如: 10.0.0.50
              ansible_user: root                   # SSH用户名
              ansible_ssh_pass: "你的第二台服务器密码"  # SSH密码
              mysql_server_id: 2
              mysql_role: secondary
            mysql-node3:
              ansible_host: 你的第三台服务器IP    # 例如: 172.16.0.200
              ansible_user: root                   # SSH用户名
              ansible_ssh_pass: "你的第三台服务器密码"  # SSH密码
              mysql_server_id: 3
              mysql_role: secondary
    mysql_router:
      hosts:
        mysql-router1:
          ansible_host: 你的第一台服务器IP      # Router部署在第一台服务器
          ansible_user: root
          ansible_ssh_pass: "你的第一台服务器密码"
  vars:
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
    ansible_python_interpreter: /usr/bin/python3
    ansible_host_key_checking: false
```

### 2. 配置示例

参考 `examples/hosts-with-passwords.yml` 文件中的示例配置：

- **服务器1**: 192.168.1.100 (主节点 + Router)
- **服务器2**: 10.0.0.50 (从节点)
- **服务器3**: 172.16.0.200 (从节点)

### 3. 安全注意事项

#### 3.1 密码安全
建议使用 Ansible Vault 加密密码：

```bash
# 创建加密的密码文件
ansible-vault create inventory/vault.yml

# 在vault.yml中添加密码变量
vault_mysql_node1_password: "你的第一台服务器密码"
vault_mysql_node2_password: "你的第二台服务器密码"
vault_mysql_node3_password: "你的第三台服务器密码"
```

然后在hosts.yml中引用：
```yaml
ansible_ssh_pass: "{{ vault_mysql_node1_password }}"
```

#### 3.2 SSH密钥认证（推荐）
如果可能，建议使用SSH密钥认证替代密码认证：

```yaml
mysql-node1:
  ansible_host: 192.168.1.100
  ansible_user: root
  ansible_ssh_private_key_file: ~/.ssh/server1_key
```

### 4. 连接测试

配置完成后，测试连接：

```bash
# 测试所有服务器连接
ansible all -m ping

# 测试特定服务器
ansible mysql-node1 -m ping
ansible mysql-node2 -m ping
ansible mysql-node3 -m ping
```

### 5. 部署命令

连接测试成功后，开始部署：

```bash
# 使用密码认证部署
./deploy.sh

# 如果使用了Ansible Vault
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --ask-vault-pass
```

### 6. 常见问题

#### 6.1 SSH连接失败
- 检查IP地址是否正确
- 确认SSH服务是否运行（端口22）
- 验证用户名和密码是否正确
- 检查防火墙设置

#### 6.2 权限问题
- 确保使用的用户有sudo权限
- 如果不是root用户，添加become配置：
```yaml
ansible_become: yes
ansible_become_method: sudo
ansible_become_pass: "sudo密码"
```

#### 6.3 网络连通性
- 确保3台服务器之间网络互通
- 检查MySQL端口（3306, 33060, 33061）是否开放
- 验证防火墙规则

### 7. 服务器要求

每台服务器需要满足：
- **操作系统**: CentOS 7.9+ 或 CentOS 8.x
- **内存**: 最少2GB，推荐4GB+
- **磁盘**: 最少20GB可用空间
- **网络**: 服务器间网络互通
- **架构**: 支持x86_64和ARM64

### 8. 端口要求

确保以下端口在服务器间开放：
- **3306**: MySQL服务端口
- **33060**: MySQL X Protocol端口
- **33061**: MySQL Group Replication端口
- **6446**: MySQL Router读写端口
- **6447**: MySQL Router只读端口 