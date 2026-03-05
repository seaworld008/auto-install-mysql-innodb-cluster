# 发布前检查清单（中文）

## 1. 基础语法检查

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --syntax-check
ansible-playbook -i inventory/hosts-ha-reference.yml playbooks/site.yml --syntax-check
```

## 2. 高可用拓扑检查

```bash
ANSIBLE_STDOUT_CALLBACK=default ansible-playbook -i inventory/hosts-ha-reference.yml playbooks/preflight-ha.yml
```

## 3. 入口层健康检查

```bash
./scripts/health-check-ha.sh inventory/hosts-ha-reference.yml
```

## 4. 扩容演练（可选）

```bash
./scripts/scale-router.sh inventory/hosts-ha-reference.yml mysql_router
./scripts/scale-haproxy.sh inventory/hosts-ha-reference.yml haproxy_lb
```

## 5. 推送前确认

- [ ] `git status` 工作区干净
- [ ] README/蓝图文档已同步
- [ ] inventory 中密码/IP 已替换为真实值
- [ ] Keepalived VIP 与网卡名（`keepalived_interface`）已按环境修正

