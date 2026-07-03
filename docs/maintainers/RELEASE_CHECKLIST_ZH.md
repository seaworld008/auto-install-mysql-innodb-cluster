# 发布前检查清单（中文）

## 1. 基础语法检查

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --syntax-check
ansible-playbook -i inventory/hosts-ha-reference.yml playbooks/site.yml --syntax-check
ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/site.yml --syntax-check
ansible-inventory -i inventory/hosts-with-dedicated-routers.yml --list >/tmp/inventory-dedicated.json
```

## 2. 高可用拓扑检查

```bash
ANSIBLE_STDOUT_CALLBACK=default ./scripts/deploy_dedicated_routers.sh --check-prereq -i inventory/hosts-with-dedicated-routers.yml
```

## 3. 入口层健康检查

```bash
./scripts/health-check-ha.sh inventory/hosts-with-dedicated-routers.yml
```

## 4. 入口层扩容或重配演练（可选）

```bash
# 先把新增 Router / HAProxy 主机加入 inventory，再通过主入口收敛配置
./scripts/deploy_dedicated_routers.sh --install-routers -i inventory/hosts-with-dedicated-routers.yml
./scripts/deploy_dedicated_routers.sh --configure-lb -i inventory/hosts-with-dedicated-routers.yml
```

## 5. 推送前确认

- [ ] `git status` 工作区干净
- [ ] README/蓝图文档已同步
- [ ] inventory 中密码/IP 已替换为真实值
- [ ] Keepalived VIP 与网卡名（`keepalived_interface`）已按环境修正
- [ ] 如有 staging 验证，已填写 `docs/templates/staging-validation-record.md`
- [ ] 如有故障演练，已填写 `docs/templates/failover-drill-record.md`
- [ ] 如有恢复演练，已填写 `docs/templates/restore-drill-record.md`
- [ ] 文档截图和 CLI 输出已按 `docs/reference/ARCHITECTURE_AND_EVIDENCE.md` 脱敏

## 6. 可选文档质量检查

```bash
npx --yes markdownlint-cli2
python -m pip install yamllint
yamllint .
```

当前文档 lint 是 advisory，不替代 Ansible syntax check、inventory 校验或真实环境验证。
