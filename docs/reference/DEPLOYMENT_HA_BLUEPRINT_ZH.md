# MySQL InnoDB Cluster 高可用部署蓝图

## 1. 生产候选基线

- MySQL InnoDB Cluster：至少 3 节点
- MySQL Router：至少 2 节点
- HAProxy + Keepalived：至少 2 节点
- 每个集群使用唯一 Group Replication UUID
- 真实 inventory、Vault 和 SSH 材料保持 Git 忽略

默认前置检查由 `playbooks/preflight-ha.yml` 执行。测试环境可显式降低 Router /
HAProxy 数量要求，但这不构成 HA 拓扑。

控制节点要求 Python 3.12+；各目标节点在首次 Ansible 模块连接前必须预装
Python 3.9+。目标选择会随 full / mysql / router profile 收窄。

## 2. 唯一流量路径

```text
Application
    |
    v
Keepalived VIP
    |
    v
HAProxy pair
    |
    v
MySQL Router pair
    |
    v
MySQL InnoDB Cluster
```

组件职责：

- InnoDB Cluster：数据一致性、成员身份和 primary 切换。
- Router：读取 metadata，提供 RW、RO 和自动读写分离路由。
- HAProxy：对多个 Router 做四层健康检查和连接分发。
- Keepalived：在入口节点间漂移 VIP。

HAProxy 后端固定为 Router。仓库不支持直接连接静态 MySQL primary，因为主从切换后
静态目标可能仍把写流量发送给旧主节点。

## 3. 端口

| 层 | 用途 | 默认端口 |
| --- | --- | --- |
| HAProxy VIP | 强制读写 | `3307` |
| HAProxy VIP | 强制只读 | `3308` |
| HAProxy VIP | 自动读写分离 | `3309` |
| Router | 强制读写 | `6446` |
| Router | 强制只读 | `6447` |
| Router | 自动读写分离 | `6450` |
| HAProxy | stats，仅 localhost | `8404` |

应用默认优先使用 VIP `3309`。stats 默认绑定 `127.0.0.1`，远程观察应使用 SSH
tunnel 或受控监控代理。

主配置默认 VIP `192.0.2.100` 属于 RFC 5737 文档地址，preflight 会阻断。
必须覆盖为目标环境已确认且未冲突的地址；例如真实私网中的
`192.168.1.100`。

## 4. VIP 故障语义

Keepalived 的 `vrrp_script` 直接检查：

```text
/usr/bin/systemctl is-active --quiet haproxy
```

检查间隔、超时、连续失败和连续恢复次数由以下变量控制：

- `keepalived_check_interval`
- `keepalived_check_timeout`
- `keepalived_check_fall`
- `keepalived_check_rise`

脚本使用 `weight 0`。连续失败达到 fall 阈值后，当前 VRRP 实例进入 `FAULT` 并
释放 VIP；连续成功达到 rise 阈值后恢复。真实漂移时间和客户端重连效果必须通过
staging 故障演练验证。

Keepalived 配置包含认证口令，目标文件权限保持 root `0600`，Ansible 模板渲染
保持 `no_log`。

## 5. 部署步骤

创建 Git 忽略的本地 inventory 与唯一 UUID：

```bash
./scripts/setup-servers.sh
```

准备 Vault，并严格校验 SSH host key：

```bash
ansible-vault create inventory/vault.local.yml
```

执行静态与目标环境检查：

```bash
./.venv/bin/ansible-inventory \
  -i inventory/hosts.local.yml \
  --ask-vault-pass -e @inventory/vault.local.yml --list >/dev/null
./.venv/bin/ansible-playbook \
  -i inventory/hosts.local.yml \
  --ask-vault-pass -e @inventory/vault.local.yml \
  playbooks/site.yml --syntax-check
./scripts/deploy_dedicated_routers.sh --check-prereq \
  -i inventory/hosts.local.yml \
  --ask-vault-pass -e @inventory/vault.local.yml
```

部署：

```bash
./scripts/deploy_dedicated_routers.sh --production-ready \
  -i inventory/hosts.local.yml \
  --ask-vault-pass -e @inventory/vault.local.yml
```

## 6. 健康门

`scripts/health-check-ha.sh` 执行 `playbooks/validate-ha.yml`，先导入
`preflight-ha.yml`，再导入 `health-check-ha.yml`。部署、状态、滚动配置和
MySQL 扩容使用相应 profile 的组合门：

- 每个 inventory MySQL 节点必须是本地 `ONLINE` 成员
- Cluster 必须严格为 `OK`，且 topology / ONLINE 成员数与 inventory 一致
- 所有 Router 服务和三个路由端口必须可用
- 所有 HAProxy / Keepalived 服务和三个 VIP 入口端口必须可用
- VIP 必须恰好出现在一个入口节点；未绑定或同时绑定多个节点都失败

任一条件不满足即返回非零。不能以 playbook 语法通过或 CI 绿色替代该运行时结果。

MySQL 缩容先在缩容 playbook 内验证剩余成员；从 inventory 移除目标后，再执行
`--status` 全栈组合门。

## 7. 扩缩容与幂等边界

- Router 默认不重复 bootstrap；只有显式
  `mysql_router_rebootstrap: true` 才重建配置。
- Cluster 配置识别已存在成员；只对 standalone 节点执行配置检查并加入，已有成员
  跳过 `configureInstance`。
- MySQL 缩容要求唯一目标、最小剩余节点数，并在移除当前 primary 前显式切主。
- Router / HAProxy 缩容要求 `--limit` 精确匹配一台节点，并保持最小 HA 数量。
- 操作完成后必须再次执行健康门。

## 8. 验证边界

本蓝图描述代码当前意图，不代表已在目标网络和硬件完成验收。上线前至少演练：

- primary 切换
- Router 单节点故障
- HAProxy 进程故障与 VIP 漂移
- Keepalived 节点故障
- 客户端重连
- 扩容、切主与缩容
- 备份与隔离恢复

使用 `docs/templates/staging-validation-record.md`、
`docs/templates/failover-drill-record.md` 和
`docs/templates/restore-drill-record.md` 留存证据。
