# AI Maintainer Guide

这份文档写给后续接手本仓库的 AI / 自动化助手。

目标只有一个：
在不破坏当前生产主线的前提下，继续维护、扩展和验证这套 MySQL InnoDB Cluster 自动化部署仓库。

## 1. 仓库当前状态

本仓库已经从“多套脚本并行、文档与实现漂移”的状态，收敛为一条主线：

- 单一运行时主配置：`inventory/group_vars/all.yml`
- 单一主入口：`scripts/deploy_dedicated_routers.sh`
- 单一配置切换机制：`scripts/config_manager.sh`
- 单一 CI 静态质量门：`.github/workflows/ansible-ci.yml`

当前主线已经覆盖：

- MySQL Cluster 部署
- Router 部署
- HAProxy / Keepalived 部署
- MySQL 扩容
- MySQL 缩容
- Router / LB 缩容
- 滚动配置应用
- 可选逻辑备份

## 2. 先看哪些文件

如果你是第一次接手，请按这个顺序读：

1. `README.md`
2. `inventory/group_vars/all.yml`
3. `scripts/deploy_dedicated_routers.sh`
4. `playbooks/site.yml`
5. `playbooks/preflight-ha.yml`
6. `playbooks/install-mysql.yml`
7. `playbooks/configure-cluster.yml`
8. `playbooks/install-router.yml`
9. `playbooks/backup.yml`
10. `.github/workflows/ansible-ci.yml`

## 3. 单一真相源

### 3.1 配置真相源

运行时唯一主配置是：

- `inventory/group_vars/all.yml`

不要再把新的运行逻辑放进：

- `inventory/group_vars/all-8c32g-optimized.yml`
- `inventory/group_vars/all-original-10k-config.yml`

这两个文件现在只是历史快照参考，不是运行时真相源。

### 3.2 入口真相源

真实用户主入口是：

- `scripts/deploy_dedicated_routers.sh`

根目录 `deploy.sh` 只是兼容包装层，不应继续扩展新能力。

### 3.3 文档真相源

当前主入口文档是：

- `README.md`
- `DEPLOYMENT_COMPLETE_GUIDE.md`
- `QUICK_START.md`
- `PRE_DEPLOYMENT_CHECKLIST.md`

如果实现改变了，这几份文档必须同步。

## 4. 修改原则

### 4.1 不要继续打补丁

如果发现问题，优先问自己：

- 这个问题是不是因为出现了第二套流程？
- 这个变量是不是已经在 `all.yml` 里存在，只是没有复用？
- 这个脚本是不是应该并入主入口，而不是再新建一个旁路脚本？

原则是：

- 优先收敛
- 避免并行入口
- 避免配置复制
- 避免文档与实现双重真相

### 4.2 不要新增“独立配置副本”

如果要新增 profile：

- 在 `inventory/group_vars/all.yml` 的 `mysql_config_profiles` 中加
- 让 `config_manager.sh` 只切 `mysql_hardware_profile`

不要再新增一整份新的 `all-xxx.yml` 作为运行配置。

### 4.3 不要把“看起来有值”的参数放着不生效

任何参数新增后，都必须回答两个问题：

1. 它最终写到哪里？
2. 它是否真的被 playbook / 模板 / bootstrap 命令使用？

仓库以前出现过 Router 参数写在 inventory，但实际上没有生效的问题。以后要避免。

## 5. 关键主流程

### 5.1 完整部署

入口：

- `scripts/deploy_dedicated_routers.sh --production-ready`

编排：

1. `preflight-ha.yml`
2. `site.yml`
3. `health-check-ha.sh`

### 5.2 MySQL 扩容

入口：

- `scripts/deploy_dedicated_routers.sh --scale-mysql-add --limit <new-host>`

要求：

- 新节点必须先加入 inventory
- 新节点必须有合法 `mysql_server_id`

### 5.3 MySQL 缩容

入口：

- `scripts/deploy_dedicated_routers.sh --scale-mysql-remove --target <host> [--new-primary <host>]`

要求：

- 集群节点数不能缩到 3 以下
- 缩容当前主节点时，必须先切主

### 5.4 配置滚动应用

入口：

- `scripts/deploy_dedicated_routers.sh --apply-config`

用途：

- 修改 `all.yml` 后，将配置滚动应用到现有节点

### 5.5 可选备份

入口：

- `scripts/deploy_dedicated_routers.sh --backup`

默认：

- `backup_config.enabled=false`

支持：

- `local`
- `nfs`
- `rsync`

当前实现是逻辑备份，走：

- `mysqlsh util.dumpInstance`

## 6. 关键参数说明

### 6.1 MySQL Server

重点关注：

- `max_connections`
- `innodb_buffer_pool_size`
- `max_allowed_packet`
- `wait_timeout`
- `interactive_timeout`
- `net_read_timeout`
- `net_write_timeout`

当前主线默认是“生产余量版”，不是“吃满内存版”。

### 6.2 Router

Router 相关参数要区分：

- 元数据连接超时
- 路由层连接超时
- 客户端连接到 Router 的超时
- 最大总连接数
- 单 route 最大连接数

不要把“SQL 执行时长”与“Router 连接建立超时”混为一谈。

### 6.3 备份

启用备份前必须确认：

- `backup_config.enabled = true`
- `backup_config.type`
- `backup_config.base_dir`
- `backup_config.remote_host`
- `backup_config.remote_dir`
- `backup_config.ssh_key_path`（如使用）

## 7. 幂等性要求

后续修改必须尽量满足：

- 重复执行 playbook 不应破坏现有节点
- Router 默认不重复 bootstrap
- 配置应用应以滚动方式执行
- 缩容动作必须显式、可审计
- 备份默认关闭，显式启用后才执行

如果新增功能不能做到完全幂等，至少要做到：

- 有显式开关
- 有前置校验
- 有清晰告警

## 8. 静态验证要求

改动后至少要过这些检查：

### 本地静态检查

- YAML 解析通过
- shell `bash -n` 通过
- `git diff --check` 通过

### Ansible 语义检查

需要安装：

- `ansible-core`
- `community.mysql`
- `community.general`
- `ansible.posix`

并通过：

- `ansible-playbook -i inventory/hosts-ha-reference.yml playbooks/site.yml --syntax-check`
- `ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/site.yml --syntax-check`
- `ansible-inventory --list`

### GitHub Actions

CI 文件：

- `.github/workflows/ansible-ci.yml`

如果增加了新的 playbook / inventory / collection 依赖，必须同步更新 CI。

## 9. 哪些文件要谨慎改

高风险文件：

- `inventory/group_vars/all.yml`
- `playbooks/install-mysql.yml`
- `playbooks/configure-cluster.yml`
- `playbooks/install-router.yml`
- `roles/mysql-server/templates/my.cnf.j2`
- `scripts/deploy_dedicated_routers.sh`

这些文件改动时，必须同步检查：

- README
- 部署总览
- 快速开始
- 部署前检查清单
- CI

## 10. 文档同步规则

如果改了以下内容，必须同步文档：

- 默认端口
- 默认 profile
- timeout / 连接数 / buffer pool
- 主入口命令
- 扩容 / 缩容命令
- 备份启用方式
- 支持的操作系统矩阵

至少同步：

- `README.md`
- `DEPLOYMENT_COMPLETE_GUIDE.md`
- `QUICK_START.md`
- `PRE_DEPLOYMENT_CHECKLIST.md`

## 11. 现在还没完成的事

仓库已经完成：

- 静态质量主线
- 主配置收敛
- 主入口收敛
- Ansible syntax-check

仓库还没有完成：

- 真实环境 staging 演练
- 真实扩容/缩容/备份/恢复的端到端实证

所以不要对外宣称：

- “已经实测过完整生产场景”

更准确的说法是：

- “仓库主线代码与静态验证已就绪，等待真实环境演练闭环”

## 12. 推荐工作方式

如果你是后续 AI，请用这个顺序工作：

1. 先确认需求是否应该并入主线，而不是新增旁路
2. 只在 `all.yml` 中新增或修改运行时配置
3. 保持 `deploy_dedicated_routers.sh` 为统一入口
4. 修改实现后同步主文档
5. 跑静态检查
6. 跑 Ansible syntax-check
7. 最后再提交

如果你发现“文档是新的，但代码是旧的”或“代码是新的，但脚本入口没接上”，优先修正这种断裂。
