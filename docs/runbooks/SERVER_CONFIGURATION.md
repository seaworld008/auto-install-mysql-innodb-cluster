# 服务器配置指南

本仓库当前推荐的生产候选拓扑是：

- MySQL InnoDB Cluster：3 节点
- MySQL Router：2 节点
- HAProxy + Keepalived：2 节点

最小 HA 约束由 `playbooks/preflight-ha.yml` 执行。不要再使用旧的“三台服务器 + 单 Router”方式作为生产默认拓扑；这类拓扑会被当前预检查阻断或降级为测试用途。

## 推荐方式：使用 HA inventory 向导

```bash
./scripts/setup-servers.sh inventory/hosts-with-dedicated-routers.yml
```

向导会收集：

- 3 台 MySQL 节点
- 2 台 MySQL Router 节点
- 2 台 HAProxy / Keepalived 节点
- 1 个 Keepalived VIP

生成 inventory 后，还必须配置 MySQL 密码：

```bash
vim inventory/group_vars/all.yml
```

至少替换：

- `mysql_root_password`
- `mysql_cluster_password`
- `mysql_replication_password`

生产环境建议使用 Ansible Vault、SSH key、CI/CD Secret 或专用 Secret Manager，不建议把真实密码长期保存在明文 inventory 中。

## 手动配置 inventory

优先编辑：

- `inventory/hosts-with-dedicated-routers.yml`
- `inventory/hosts-ha-reference.yml`

关键结构如下：

```yaml
all:
  children:
    mysql_cluster:
      children:
        mysql_primary:
          hosts:
            mysql-node1:
              ansible_host: 192.168.1.10
              ansible_port: 22
              ansible_user: root
              ansible_ssh_pass: "your_password_1"
              mysql_server_id: 1
              mysql_role: primary
        mysql_secondary:
          hosts:
            mysql-node2:
              ansible_host: 192.168.1.11
              ansible_port: 22
              ansible_user: root
              ansible_ssh_pass: "your_password_2"
              mysql_server_id: 2
              mysql_role: secondary
            mysql-node3:
              ansible_host: 192.168.1.12
              ansible_port: 22
              ansible_user: root
              ansible_ssh_pass: "your_password_3"
              mysql_server_id: 3
              mysql_role: secondary

    mysql_router:
      hosts:
        mysql-router-1:
          ansible_host: 192.168.1.20
          ansible_port: 22
          ansible_user: root
          ansible_ssh_pass: "router_password_1"
        mysql-router-2:
          ansible_host: 192.168.1.21
          ansible_port: 22
          ansible_user: root
          ansible_ssh_pass: "router_password_2"

    haproxy_lb:
      hosts:
        haproxy-1:
          ansible_host: 192.168.1.30
          ansible_port: 22
          ansible_user: root
          ansible_ssh_pass: "haproxy_password_1"
          keepalived_priority: 150
        haproxy-2:
          ansible_host: 192.168.1.31
          ansible_port: 22
          ansible_user: root
          ansible_ssh_pass: "haproxy_password_2"
          keepalived_priority: 100

  vars:
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
    ansible_python_interpreter: /usr/bin/python3
    keepalived_vip: "192.168.1.100"
```

## 使用 SSH key

如果可能，建议用 SSH key 替代明文 SSH 密码：

```yaml
mysql-node1:
  ansible_host: 192.168.1.10
  ansible_user: root
  ansible_ssh_private_key_file: ~/.ssh/mysql_cluster_key
```

## 使用 Ansible Vault

创建 Vault 文件：

```bash
ansible-vault create inventory/vault.yml
```

示例变量：

```yaml
vault_mysql_root_password: "替换为真实强密码"
vault_mysql_cluster_password: "替换为真实强密码"
vault_mysql_replication_password: "替换为真实强密码"
```

在 `inventory/group_vars/all.yml` 中引用：

```yaml
mysql_root_password: "{{ vault_mysql_root_password }}"
mysql_cluster_password: "{{ vault_mysql_cluster_password }}"
mysql_replication_password: "{{ vault_mysql_replication_password }}"
```

执行时带上 Vault：

```bash
ansible-playbook -i inventory/hosts-with-dedicated-routers.yml -e @inventory/vault.yml --ask-vault-pass playbooks/site.yml
```

## 连接测试

```bash
ansible all -i inventory/hosts-with-dedicated-routers.yml -m ping
```

## 前置检查与部署

```bash
./scripts/deploy_dedicated_routers.sh --check-prereq -i inventory/hosts-with-dedicated-routers.yml
./scripts/deploy_dedicated_routers.sh --production-ready -i inventory/hosts-with-dedicated-routers.yml
```

## 常见问题

### SSH 连接失败

- 检查 IP、端口、用户名和认证方式。
- 确认目标主机 SSH 服务运行。
- 检查防火墙、堡垒机、VPN 或安全组。
- 如果不是 root 用户，请配置 `ansible_become`。

### Keepalived VIP 无法漂移

- 确认 `keepalived_vip` 是未被占用的内网地址。
- 确认 `keepalived_interface` 指向真实网卡。
- 确认两台 HAProxy 节点处在同一可达二层或等价网络环境。

### Preflight 提示密码未配置

说明 `inventory/group_vars/all.yml` 仍然是 `CHANGE_ME_*` 占位符。请先替换真实密码，或通过 Ansible Vault 注入。

## 端口要求

- `3306`：MySQL 服务端口
- `33062`：MySQL 管理端口
- `33061`：MySQL Group Replication 端口
- `6446`：MySQL Router 强制读写端口
- `6447`：MySQL Router 强制只读端口
- `6450`：MySQL Router 自动读写分离端口
- `3307`：HAProxy VIP 强制读写端口
- `3308`：HAProxy VIP 强制只读端口
- `3309`：HAProxy VIP 自动读写分离端口
- `8404`：HAProxy stats 端口

## 系统要求

- Ubuntu 22.04 / 24.04 / 25.10，或 RHEL/Rocky/Alma 8/9/10
- 目标主机之间网络互通
- 控制端已安装 Ansible 和所需 collections
- 目标主机可使用 root 或具备 sudo 权限的用户执行自动化任务
