# v0.3.1

本版本修复生产自动化部署中的首次安装阻塞、Router 配置不生效和失败传播问题。
运行时主配置仍为 `inventory/group_vars/all.yml`，操作统一通过
`scripts/deploy_dedicated_routers.sh`。

## 修复内容

- Ubuntu 24.04/25.04/25.10 与 Debian 13 选择 `libaio1t64`，避免安装不存在的旧包。
- Group Replication 地址从 inventory 解析，不再依赖其他批次尚未采集的 facts。
- 委派执行 `addInstance` 时明确使用目标 secondary 的地址，避免取到管理节点地址。
- MySQL 缩容后的管理连接使用剩余成员，避免查询已经停服的原管理节点。
- 已有 Router 的端口、连接数、超时和路由策略原子收敛，保留身份及 keyring；
  实际变化才重启，逐台执行三类连接验证。
- 自动读写分离统一到 `routing:bootstrap_rw_split`，移除历史重复路由，
  使用与 PRIMARY_AND_SECONDARY 兼容的 round-robin 策略并阻断非法策略。
- 任一节点失败时停止后续操作；检查 MySQL 分组完整性、单节点滚动批次、
  server_id 范围及唯一性、Router 端口冲突和危险目录。
- CLI 拒绝不支持的 `--limit` / `--target` 参数组合及主机参数注入。
- rsync 备份源路径正确引用；备份根目录与物理备份子目录增加约束。
- CI 逐个检查 Shell 脚本；新增实际 Ansible 失败传播、配置原子更新幂等性、
  模板与发行版包选择回归测试。
- 移除未生效的 Router 调优字段；更新 deploy-pages 到 5.0.1（PR #14）。

## 升级与回退

1. 保存现有受保护配置、inventory 和 Vault，在维护窗口升级。
2. `--check-prereq` → `--apply-config` → `--status`。
3. Group Replication 使用的 inventory 地址必须在集群节点间直接可达，不能使用
   仅用于 SSH 的 NAT 地址。MySQL 每批仅允许一台。
4. 自定义 Router 路由名称需先人工迁移；不要删除 keyring 或默认强制 rebootstrap。
5. 移除 `mysql_primary` 管理节点时，更新 inventory 将一个剩余成员归入该组，
   其余归入 `mysql_secondary`，再执行 `--status`。
6. 出现问题立即停止后续批次，恢复保存的配置并逐台验证；切回旧 tag 不会自动还原
   已应用的运行时配置，也不代表数据库版本降级或数据恢复已完成。

## 验证与边界

本地执行 Python 回归、全部 Shell 语法、YAML/Markdown lint、全部 playbook
syntax-check、三个主 inventory 解析与 site syntax-check。
PR 和合并后的 main 还必须通过 Python 3.12/3.13、PowerShell parser、文档检查和
CodeQL；发布后下载源码归档复验 SHA-256 与解包内容。

真实 Linux/MySQL 环境未在本轮执行，首次部署、重复收敛、故障切换、VIP 漂移、
扩缩容、备份恢复、容量及性能仍待隔离 staging 验收。这是部署自动化修复版，
不能把静态/CI 通过解释为生产环境已经验收通过。

Release 附源码归档及 `SHA256SUMS`，下载到同一目录后执行：

```bash
shasum -a 256 --check SHA256SUMS
```
