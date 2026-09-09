# 公共准备：所有部署方案共用

本页只准备控制端和本地文件，不会安装远端服务。执行位置是仓库根目录，后续示例使用 Bash。

## 1. 控制端与目标主机

控制端需要 Python 3.12+、SSH；所有目标主机预装 Python 3.9+，RHEL 8 需准备 python39。
SSH 用户需要 root 或可提权权限。发行版范围见 [部署前检查](https://github.com/seaworld008/auto-install-mysql-innodb-cluster/blob/main/PRE_DEPLOYMENT_CHECKLIST.md)。

```bash
git clone https://github.com/seaworld008/auto-install-mysql-innodb-cluster.git
cd auto-install-mysql-innodb-cluster
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
ansible-galaxy collection install -r collections/requirements.yml
```

通过可信渠道核对每台主机的 SSH 指纹后加入本机 known_hosts，步骤见
[服务器准备](../runbooks/SERVER_CONFIGURATION.md)。不得关闭主机密钥检查。

## 2. 选择一个模板并创建本地 inventory

四份模板只包含主机和角色关系，不复制运行配置。选择一份，修改第一行后执行：

```bash
# 可选：dedicated / colocated / mixed / three-entry
TOPOLOGY=dedicated
umask 077
# 拒绝覆盖已有文件；已有环境应编辑本地文件，不能再次套用模板。
(set -o noclobber; cat "examples/topologies/${TOPOLOGY}.yml" > inventory/hosts.local.yml)
chmod 600 inventory/hosts.local.yml
${EDITOR:-vi} inventory/hosts.local.yml
```

把所有 `192.0.2.*` 文档地址改成目标主机可互通的真实地址。`all.hosts` 中每台物理主机只
定义一次；在多个角色组中重复引用同一主机名表示共置。不要用三个不同别名模拟三台机器。旧 inventory 若用不同别名描述同一 IP，应将连接变量集中到一个主机定义，
再跨角色引用它；仅整理 inventory 引用，不修改运行数据库的身份。
默认 SSH 用户为 root，如使用其他用户，在下一步设置 `ansible_user`。

## 3. 创建本地参数覆盖

```bash
umask 077
(set -o noclobber; cat > inventory/settings.local.yml <<'YAML'
ansible_user: root
# 如不使用默认 SSH key/agent，可添加绝对路径：
# ansible_ssh_private_key_file: /secure/path/id_ed25519
keepalived_vip: "192.0.2.100"
keepalived_interface: "CHANGE_ME_INTERFACE"
mysql_group_replication_group_name_override: "CHANGE_ME_UUID"
mysql_hardware_profile: "optimized_8c32g"
mysql_release_line: "8.4"
mysql_cluster_name: "prodCluster"
# 新集群用目标机实际地址通告成员，避免依赖系统主机名 DNS。
mysql_report_host_override: "{{ ansible_host }}"
YAML
)
python3 -c 'import uuid; print(uuid.uuid4())'
${EDITOR:-vi} inventory/settings.local.yml
```

Keepalived 方案要求入口网络支持 VIP 漂移和 VRRP；公共云需先确认平台网络能力，不能只开放 TCP 端口。
不具备该条件时，可选择 HAProxy 单独部署并使用已有外部入口。

填写未占用的真实 VIP、正确网卡名，将生成的 UUID 填入 override。已有环境应同时核对 MySQL 版本线与集群名称。已有集群应查询实际
`@@GLOBAL.group_replication_group_name` 并填入，不生成新身份。网卡不同可在 inventory
逐台设置，但这时应从 settings 文件移除全局 `keepalived_interface`，避免 extra vars 覆盖主机值。

这些是用户本地差异值；其余默认参数继续从唯一运行配置读取。按 `-e` 指定参数文件可明确
覆盖优先级，避免 inventory 内联 vars 被 group_vars 中的默认值覆盖。

## 4. 创建加密凭据

```bash
ansible-vault create inventory/vault.local.yml
```

以下字段用于全量部署；单独操作组件或只读检查时，按
[组件凭据表](COMPONENTS.md#按操作准备凭据) 只保留所需字段。
在编辑器中填写对应字段，并替换全部占位值。数据库使用互不相同的强密码，VRRP 口令为
1–8 位字母、数字、下划线、点或横线：

```yaml
mysql_root_password: "CHANGE_ME_ROOT_PASSWORD"
mysql_cluster_password: "CHANGE_ME_CLUSTER_PASSWORD"
mysql_replication_password: "CHANGE_ME_REPLICATION_PASSWORD"
keepalived_auth_pass: "CHANGE_ME"
```

本地 inventory、settings 和 Vault 文件均已被 Git 忽略，不编辑已跟踪模板来部署真实环境。

## 5. 定义共用命令参数

在每个新的 Bash 终端先执行以下块；它不包含密码，也不会连接远端：

```bash
source .venv/bin/activate
INVENTORY=inventory/hosts.local.yml
COMMON_ARGS=(-i "$INVENTORY" -e @inventory/settings.local.yml -e @inventory/vault.local.yml --ask-vault-pass)
DEPLOY=./scripts/deploy_dedicated_routers.sh
```

长流程会多次询问 Vault 密码。自动化可将数组中的 `--ask-vault-pass` 替换为
`--vault-password-file /secure/path/vault-pass`，口令文件应位于仓库外、权限 0600。

先进行不连接目标的检查：

```bash
ansible-inventory "${COMMON_ARGS[@]}" --graph
ansible-playbook "${COMMON_ARGS[@]}" playbooks/site.yml --syntax-check
```

`--graph` 展示角色关系，不加 `--vars`，避免输出凭据。syntax-check 不代表主机已可访问。
然后按所选方案执行对应范围的 `--check-prereq` 和部署命令。

## 排障与回退

- 占位符被拒绝：核对 settings/Vault 是否填好、命令是否带上 `COMMON_ARGS`。
- 主机数不足或地址重复：修正角色分组，不降低最小数量。
- SSH/Python 失败：先逐机验证解释器、认证和提权，再重跑检查。
- 本地模板选错：保留现有本地文件，另用一个 `*.local.yml` 文件准备；未执行部署前无需改动服务器。

不要将未脱敏的 inventory 输出、Vault 明文、私钥或备份发布到 GitHub。
