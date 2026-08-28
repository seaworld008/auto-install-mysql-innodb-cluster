# 服务器配置指南

本仓库当前推荐的生产候选拓扑是：

- MySQL InnoDB Cluster：3 节点
- MySQL Router：2 节点
- HAProxy + Keepalived：2 节点

最小 HA 约束由 `playbooks/preflight-ha.yml` 执行。不要再使用旧的“三台服务器 + 单 Router”方式作为生产默认拓扑；这类拓扑会被当前预检查阻断或降级为测试用途。

## 文件与 Secret 边界

- `inventory/hosts.local.yml`：真实环境的主机拓扑，默认由向导生成，Git 忽略且权限为 `0600`。
- `inventory/vault.local.yml`：真实 MySQL 密码的 Ansible Vault 加密文件，Git 忽略。
- `inventory/hosts-*.yml`：仓库内已跟踪的脱敏示例与 CI 输入，不得写入真实 IP、用户名、密码或私钥路径。
- `inventory/group_vars/all.yml`：非敏感运行时主配置。保留 `CHANGE_ME_*` 占位符，通过 Vault 或外部 Secret 在执行时覆盖。

Vault 口令不得写入仓库。需要非交互执行时，把 Vault password file 放在仓库外、限制为 `0600`，或使用组织的 Secret Manager 临时注入。

## 推荐方式：使用 HA inventory 向导

```bash
./scripts/setup-servers.sh
```

向导固定收集 3 台 MySQL、2 台 Router、2 台 HAProxy / Keepalived 和 1 个 VIP，并执行以下安全约束：

- 默认只写入 `inventory/hosts.local.yml`，拒绝覆盖任何 Git 已跟踪的 inventory。
- 使用 `umask 077`、临时文件和原子替换，生成文件及本地备份权限均为 `0600`。
- 优先询问一条所有节点共用的 SSH 私钥路径；只有留空时才逐节点采集 SSH 密码。
- 对输入执行 YAML 单引号转义，并把密码和私钥路径标记为 Ansible `!unsafe`，避免被当作模板再次解释。
- 为每次生成的独立集群创建新的 `mysql_group_replication_group_name_override` UUID，覆盖仓库历史示例值，避免复用其他集群的 Group Replication 身份。
- SSH host key 校验默认启用，不写入绕过校验的参数。

如确需自定义文件名，只能使用匹配 `inventory/*.local.yml` Git 忽略规则的路径；实际部署文档统一使用默认的 `inventory/hosts.local.yml`。

## 首次连接前核验 SSH fingerprint

`ssh-keyscan` 只能抓取远端当前返回的公钥，不能自行证明该公钥可信。必须先暂存、查看 fingerprint，并通过云控制台、机房控制台或管理员提供的可信渠道比对；确认一致后才能写入 `known_hosts`。

对 inventory 中的 7 台主机逐一执行：

```bash
HOST='192.0.2.10'
HOST_KEY_FILE="$(mktemp)"

ssh-keyscan -H -t ed25519 "$HOST" >"$HOST_KEY_FILE"
ssh-keygen -lf "$HOST_KEY_FILE"
```

通过可信渠道确认 fingerprint 完全一致后：

```bash
install -d -m 0700 "$HOME/.ssh"
cat "$HOST_KEY_FILE" >>"$HOME/.ssh/known_hosts"
chmod 0600 "$HOME/.ssh/known_hosts"
rm -f "$HOST_KEY_FILE"
```

如果 fingerprint 不一致，立即停止并排查地址复用、主机重装或中间人攻击，不要通过关闭校验或绕过标准 `known_hosts` 文件来继续；默认 inventory 明确启用严格校验。

## 手动维护本地 inventory

只编辑被 Git 忽略的 `inventory/hosts.local.yml`。下面使用文档专用地址，保留 3 MySQL + 2 Router + 2 HAProxy 拓扑；替换时仍不得把真实值写回已跟踪示例。

```yaml
all:
  children:
    mysql_cluster:
      children:
        mysql_primary:
          hosts:
            mysql-node1:
              ansible_host: '192.0.2.11'
              ansible_port: 22
              ansible_user: 'automation'
              mysql_server_id: 1
              mysql_role: 'primary'
        mysql_secondary:
          hosts:
            mysql-node2:
              ansible_host: '192.0.2.12'
              ansible_port: 22
              ansible_user: 'automation'
              mysql_server_id: 2
              mysql_role: 'secondary'
            mysql-node3:
              ansible_host: '192.0.2.13'
              ansible_port: 22
              ansible_user: 'automation'
              mysql_server_id: 3
              mysql_role: 'secondary'

    mysql_router:
      hosts:
        mysql-router-1:
          ansible_host: '192.0.2.21'
          ansible_port: 22
          ansible_user: 'automation'
          router_role: 'primary'
          router_priority: 100
        mysql-router-2:
          ansible_host: '192.0.2.22'
          ansible_port: 22
          ansible_user: 'automation'
          router_role: 'secondary'
          router_priority: 90

    haproxy_lb:
      hosts:
        haproxy-1:
          ansible_host: '192.0.2.31'
          ansible_port: 22
          ansible_user: 'automation'
          keepalived_priority: 150
        haproxy-2:
          ansible_host: '192.0.2.32'
          ansible_port: 22
          ansible_user: 'automation'
          keepalived_priority: 100

  vars:
    ansible_ssh_common_args: '-o StrictHostKeyChecking=yes'
    ansible_ssh_private_key_file: !unsafe '/secure/path/to/mysql-cluster-key'
    ansible_python_interpreter: auto_silent
    keepalived_vip: '192.0.2.100'
    mysql_group_replication_group_name_override: 'CHANGE_ME_UNIQUE_UUID'
```

手动维护时也必须为每个独立集群生成新的 UUID；不要复制上面的文档值：

```bash
uuidgen | tr '[:upper:]' '[:lower:]'
```

私钥本身必须位于仓库外并限制访问权限：

```bash
chmod 0600 /secure/path/to/mysql-cluster-key
```

## 使用 Ansible Vault

创建 Git 忽略的 Vault 文件：

```bash
ansible-vault create inventory/vault.local.yml
```

在 Vault 编辑器中写入运行时变量名和真实强密码：

```yaml
mysql_root_password: "CHANGE_ME_ROOT_PASSWORD"  # 在 Vault 编辑器中替换
mysql_cluster_password: "CHANGE_ME_CLUSTER_PASSWORD"  # 在 Vault 编辑器中替换
mysql_replication_password: "CHANGE_ME_REPLICATION_PASSWORD"  # 在 Vault 编辑器中替换
```

保存后文件应保持 Ansible Vault 密文；可以在安全终端中验证：

```bash
ansible-vault view inventory/vault.local.yml
```

主入口统一透传 Vault 和 extra-vars 参数：

```bash
./scripts/deploy_dedicated_routers.sh --check-prereq \
  -i inventory/hosts.local.yml \
  --ask-vault-pass \
  -e @inventory/vault.local.yml
```

如果使用仓库外的 Vault password file：

```bash
./scripts/deploy_dedicated_routers.sh --check-prereq \
  -i inventory/hosts.local.yml \
  --vault-password-file "$HOME/.config/mysql-cluster/vault-password" \
  -e @inventory/vault.local.yml
```

外部 Secret Manager 或 CI/CD Secret 也必须通过临时、最小权限且不被 Git 跟踪的变量文件传入；任务结束后按组织策略安全销毁临时材料。不要把明文 Secret 写入 shell 历史、命令行参数或 tracked 文件。

## 连接测试

只有在全部 fingerprint 已核验并写入 `known_hosts` 后才能执行：

```bash
ansible all -i inventory/hosts.local.yml -m ping
```

## 前置检查与部署

所有支持的操作继续通过主入口 `scripts/deploy_dedicated_routers.sh`：

```bash
./scripts/deploy_dedicated_routers.sh --check-prereq \
  -i inventory/hosts.local.yml \
  --ask-vault-pass -e @inventory/vault.local.yml

./scripts/deploy_dedicated_routers.sh --production-ready \
  -i inventory/hosts.local.yml \
  --ask-vault-pass -e @inventory/vault.local.yml
```

## 常见问题

### SSH 连接失败

- 检查本地 inventory 中的 IP、端口、用户名和认证方式。
- 确认目标主机 SSH 服务运行。
- 检查防火墙、堡垒机、VPN 或安全组。
- 检查 `known_hosts` 中的公钥是否与可信 fingerprint 一致；不一致时先排查，不能关闭校验。
- 如果不是 root 用户，请配置 `ansible_become`。

### Keepalived VIP 无法漂移

- 确认 `keepalived_vip` 是未被占用的内网地址。
- 确认 `keepalived_interface` 指向真实网卡。
- 确认两台 HAProxy 节点处在同一可达二层或等价网络环境。

### Preflight 提示密码未配置

说明执行时仍解析到 `CHANGE_ME_*` 占位符。确认 `inventory/vault.local.yml` 是有效 Vault 密文，包含三个运行时密码变量，并通过 `--ask-vault-pass -e @inventory/vault.local.yml` 或等价的外部 Secret 参数传入。

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
