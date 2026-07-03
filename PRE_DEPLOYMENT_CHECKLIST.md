# 部署前检查清单

## 控制节点

- [ ] Python 可用
- [ ] Ansible / ansible-playbook / ansible-inventory 可用
- [ ] 已安装项目依赖：`pip install -r requirements.txt`

## 目标节点

- [ ] 已在 inventory 中配置真实 IP、SSH 用户、SSH 密码或密钥
- [ ] MySQL 节点数量不少于 3
- [ ] Router 节点数量不少于 2
- [ ] HAProxy 节点数量不少于 2
- [ ] 节点间网络互通
- [ ] 时间同步正常
- [ ] 存储挂载与 `/data/mysql` 规划完成

## 配置检查

- [ ] 已按 `inventory/README.md` 选择正确 inventory
- [ ] `inventory/group_vars/all.yml` 已确认
- [ ] `mysql_hardware_profile` 已确认
- [ ] 已按 `docs/reference/VARIABLE_REFERENCE.md` 复核关键变量
- [ ] 业务密码与 SSH 密码不是示例值
- [ ] `server_id` 唯一
- [ ] Keepalived 网卡名与真实系统一致
- [ ] 若启用备份，`backup_config` 已完整配置

## 验证记录

- [ ] 已准备 staging 验证记录：`docs/templates/staging-validation-record.md`
- [ ] 如涉及 HA 行为，已准备故障演练记录：`docs/templates/failover-drill-record.md`
- [ ] 如涉及备份恢复，已准备隔离恢复演练记录：`docs/templates/restore-drill-record.md`
- [ ] 截图和 CLI 输出会按 `docs/reference/ARCHITECTURE_AND_EVIDENCE.md` 脱敏留存

## 推荐执行顺序

```bash
git diff --check
ansible-inventory -i inventory/hosts-with-dedicated-routers.yml --list >/tmp/inventory-dedicated.json
ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/site.yml --syntax-check
./scripts/deploy_dedicated_routers.sh --check-prereq -i inventory/hosts-with-dedicated-routers.yml
./scripts/deploy_dedicated_routers.sh --production-ready -i inventory/hosts-with-dedicated-routers.yml
./scripts/health-check-ha.sh inventory/hosts-with-dedicated-routers.yml
```

## 参考

- `README.md`
- `DEPLOYMENT_COMPLETE_GUIDE.md`
- `docs/runbooks/OPERATOR_GUIDE.md`
- `inventory/README.md`
- `docs/reference/VARIABLE_REFERENCE.md`
- `docs/reference/ARCHITECTURE_AND_EVIDENCE.md`
- `docs/runbooks/TROUBLESHOOTING.md`
