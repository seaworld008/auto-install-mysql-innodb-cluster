# Staging 验证记录模板

> 复制本模板到实际记录文件后填写，例如 `docs/evidence/staging-validation-20260703.md`。提交公开仓库前必须脱敏。

## 1. 基本信息

| 项目 | 内容 |
| --- | --- |
| 环境名称 |  |
| 验证日期 |  |
| 执行人 |  |
| Git commit |  |
| Inventory |  |
| 主配置文件 | `inventory/group_vars/all.yml` |
| MySQL 版本线 |  |
| 目标拓扑 |  |

## 2. 变更范围

- [ ] 文档变更
- [ ] Inventory 变更
- [ ] `inventory/group_vars/all.yml` 变更
- [ ] Playbook / role / template 变更
- [ ] Script 变更
- [ ] CI / workflow 变更
- [ ] 其他：

变更摘要：

```text

```

## 3. 静态验证

| 检查项 | 命令 | 结果 | 证据 |
| --- | --- | --- | --- |
| Diff 空白检查 | `git diff --check` |  |  |
| Shell 语法 | `bash -n deploy.sh validate_deployment.sh scripts/*.sh` |  |  |
| Ansible syntax: basic | `ansible-playbook -i inventory/hosts.yml playbooks/site.yml --syntax-check` |  |  |
| Ansible syntax: HA reference | `ansible-playbook -i inventory/hosts-ha-reference.yml playbooks/site.yml --syntax-check` |  |  |
| Ansible syntax: dedicated routers | `ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/site.yml --syntax-check` |  |  |
| Inventory: basic | `ansible-inventory -i inventory/hosts.yml --list` |  |  |
| Inventory: HA reference | `ansible-inventory -i inventory/hosts-ha-reference.yml --list` |  |  |
| Inventory: dedicated routers | `ansible-inventory -i inventory/hosts-with-dedicated-routers.yml --list` |  |  |

## 4. 部署前检查

```bash
./scripts/deploy_dedicated_routers.sh --check-prereq -i inventory/hosts-with-dedicated-routers.yml
```

结果：

```text

```

## 5. 部署或变更执行

执行的入口命令：

```bash

```

执行结果：

```text

```

## 6. 健康检查

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| MySQL Cluster 状态 |  |  |
| Router RW 端口 `6446` |  |  |
| Router RO 端口 `6447` |  |  |
| Router R/W split 端口 `6450` |  |  |
| HAProxy RW 端口 `3307` |  |  |
| HAProxy RO 端口 `3308` |  |  |
| HAProxy R/W split 端口 `3309` |  |  |
| HAProxy stats `8404` |  |  |
| Keepalived VIP 漂移状态 |  |  |

## 7. 应用侧验证

| 用例 | 输入 | 期望 | 实际 | 结果 |
| --- | --- | --- | --- | --- |
| 写入验证 |  |  |  |  |
| 只读查询验证 |  |  |  |  |
| 连接池重连验证 |  |  |  |  |
| 长查询或批处理验证 |  |  |  |  |

## 8. 风险与遗留事项

| 风险 | 影响 | 负责人 | 截止时间 | 状态 |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |

## 9. 结论

- [ ] 通过，可进入下一阶段
- [ ] 有条件通过，需跟踪遗留事项
- [ ] 未通过，禁止进入下一阶段

结论说明：

```text

```
