# v0.3.0

v0.3.0 是基于 v0.2.0 的可靠性、安全默认值、CI 与文档收敛版本。移除 HAProxy
直连静态 MySQL primary，并默认启用严格 SSH host-key 校验，属于 pre-1.0
非兼容安全收敛。它不增加平行部署入口，继续以
`inventory/group_vars/all.yml` 和 `scripts/deploy_dedicated_routers.sh`
为单一主线。

## 重点变化

- 新增 `validate-ha.yml` 组合门：先执行 preflight，再执行 fail-closed 健康
  检查；每个 inventory MySQL 节点必须 `ONLINE`，Cluster 为 `OK` 且成员数
  匹配，同时检查启用的 Router、HAProxy、Keepalived、业务端口，并要求 VIP
  恰好归属一个入口节点。
- 集群配置与缩容增强幂等和身份校验：只检查并加入 standalone 实例，已有成员跳过
  `configureInstance`，并等待预期成员全部 `ONLINE`；移除 primary 前显式切主，
  并验证缩容后的 Cluster。
- Router 只在首次部署或显式 rebootstrap 时执行 bootstrap，且不再创建跨节点共享
  Router 账号。
- HAProxy 只连接 Router，stats 默认只监听 localhost；Keepalived 在 HAProxy
  连续故障后进入 `FAULT` 并释放 VIP。
- 自定义 MySQL datadir 采用可中断恢复的受保护迁移：拒绝覆盖非空未知目录，
  重跑继续幂等 rsync，收敛 AppArmor / SELinux，并验证最终 `@@datadir`。
- RedHat 重跑先探测目标 root 密码；已生效时跳过首次临时密码流程，没有安全恢复
  路径时阻断。
- MySQL GPG key 与 Percona release 包增加固定 SHA-256；rsync 备份强制严格
  SSH host key 校验。
- 主入口透传 Vault / extra-vars 参数；新增 Git 忽略的本地 inventory、加密
  Vault 与每集群唯一 Group Replication UUID 工作流。
- 备份文档与实现同步为 MySQL Shell 逻辑备份和 Percona XtraBackup，支持
  `local`、`nfs`、`rsync` 目标；压缩 XtraBackup 在 prepare 前先 decompress，
  rsync 严格验证 `known_hosts` / 私钥 owner 与权限。
- Keepalived 配置以 `0600` 写入且渲染任务 `no_log`；辅助状态和故障演练脚本
  通过 stdin 向 mysqlsh 传递密码，不写入 argv。
- 控制节点 `requirements.txt` 只安装 `ansible-core`，要求 Python 3.12+；
  preflight 要求所选目标节点预装 Python 3.9+。
- CI 固定所有 GitHub Actions 到完整 SHA，覆盖 Python 3.12 / 3.13、仓库契约
  测试、PowerShell parser、全部 playbook、三个主 inventory、阻断式
  Markdown / YAML lint、GitHub Actions CodeQL 和 Dependabot。

## 升级注意事项

- 不要把真实 IP、SSH 凭据、私钥、Vault 文件或 Secret 写入 tracked inventory。
  使用 `./scripts/setup-servers.sh` 生成 `inventory/hosts.local.yml`。
- 为每个集群提供唯一 `mysql_group_replication_group_name_override`；默认 UUID
  会被 preflight 阻断。
- 通过 Vault 或外部 Secret 覆盖 MySQL 密码和 `keepalived_auth_pass`。主入口
  支持 `-e @vault.yml`、`--ask-vault-pass` 和 `--vault-password-file`。
- 发布后 SSH 主机密钥校验默认严格。首次连接前先通过可信渠道核验 fingerprint 并
  写入 `known_hosts`，不要关闭校验。
- `haproxy_backend_target` 只允许 `router`。如旧配置使用 `mysql`，必须先部署并
  验证 Router 层再升级。
- 主配置的 `keepalived_vip: 192.0.2.100` 是会被 preflight 阻断的 RFC 5737
  占位值。必须覆盖为目标环境已确认的地址；例如真实私网中可使用未冲突的
  `192.168.1.100`。
- `--status` 和部署后的健康门现在会真实返回失败；自动化不得忽略退出码。
- `mysql_router_rebootstrap` 保持默认 `false`。只有明确重建 Router 时临时启用。
- 使用 XtraBackup 或 rsync 时，保留 `backup_config.percona_release` 校验字段、
  decompress-before-prepare 顺序、`ssh_known_hosts_file` 和文件权限约束。

## 快速验证

```bash
./scripts/deploy_dedicated_routers.sh --check-prereq \
  -i inventory/hosts.local.yml \
  --ask-vault-pass -e @inventory/vault.local.yml

./scripts/deploy_dedicated_routers.sh --status \
  -i inventory/hosts.local.yml \
  --ask-vault-pass -e @inventory/vault.local.yml
```

完整升级、扩缩容和备份操作见
`docs/runbooks/OPERATOR_GUIDE.md` 与
`docs/runbooks/BACKUP_AND_RESTORE_GUIDE.md`。

## 发布资产

Release 附带从 exact v0.3.0 tag 生成的源码归档和 `SHA256SUMS`。下载后请运行：

```bash
shasum -a 256 --check SHA256SUMS
```

## 验证边界

本版本发布前执行仓库级 Python 测试、shell / YAML / Markdown 检查、全部 Ansible
playbook syntax-check、三个主 inventory 解析及 GitHub CI 安全门。

本版本尚未在真实 staging 执行完整部署、故障切换、扩缩容、备份恢复或性能容量
验收。上述运行时结论仍需在目标环境按 `docs/templates/` 留存证据；本 Release
不将静态检查、CI、tag 或发布成功表述为生产验收。
