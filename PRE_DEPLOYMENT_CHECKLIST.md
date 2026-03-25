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

- [ ] `inventory/group_vars/all.yml` 已确认
- [ ] `mysql_hardware_profile` 已确认
- [ ] 业务密码与 SSH 密码不是示例值
- [ ] `server_id` 唯一
- [ ] Keepalived 网卡名与真实系统一致
- [ ] 若启用备份，`backup_config` 已完整配置

## 推荐执行顺序

```bash
./scripts/deploy_dedicated_routers.sh --check-prereq -i inventory/hosts-with-dedicated-routers.yml
./scripts/deploy_dedicated_routers.sh --production-ready -i inventory/hosts-with-dedicated-routers.yml
./scripts/health-check-ha.sh inventory/hosts-with-dedicated-routers.yml
```

## 参考

- `README.md`
- `DEPLOYMENT_COMPLETE_GUIDE.md`
- `TROUBLESHOOTING.md`
