# v0.4.0

集成本机 Rocky Linux 9 / MySQL 8.4 模拟验证发现的部署修复，并提供可重建的低资源
Linux 主机模拟配置。生产操作仍统一通过 `scripts/deploy_dedicated_routers.sh`。

## 变更

- 保留 RHEL 上已有的 curl-minimal，避免与 curl 冲突。
- MySQL 管理/复制账号使用 caching_sha2_password；已有集群仅在当前在线 primary
  修改账号，避免重复部署在只读 secondary 执行 GRANT。
- mysqlsh 显式跳过 client defaults，通过 stdin 完成密码认证后关闭 AdminAPI 向导；
  修复 YAML 中 SQL 字符串换行，并同步状态和故障辅助脚本。
- Router bootstrap 不再生成缺少 destinations 的 routing 段；安装 SQL 验证所需 Shell。
- Keepalived 显式启用脚本安全与 root 执行身份，保持配置 0600 和 no_log。
- Percona Release RPM 公钥经固定 SHA-256 和完整指纹校验后导入，继续验证 RPM 签名。
- 新增 simulation_minimal 配置及低连接数边界保护，生产默认硬件规格保持原值。
- 保存 `tests/lab/` 配置生成与生命周期工具、中文完整测试方案、脱敏实测报告；
  每轮重新生成凭据，记录源码 SHA，将磁盘、数据和下载放在当前仓库 tmp/ 下。

## 验证与已知限制

原 v0.3.1 首次模拟部署失败；修补副本通过 3 MySQL + 2 Router + 2 LB 收敛、重复部署、
滚动配置、故障注入、扩缩容和两种隔离备份恢复。最终 8,227 笔已确认写入无缺失或内容
不匹配。逻辑恢复是数据与结构语义一致，原始 DDL 打印形式存在已记录差异。

这些完整场景来自 2026-09-08 原始实验脚本，不是 v0.4.0 所有代码路径重新验收。
发布分支另执行 43 项 Python 回归、Shell、Markdown/YAML lint、全部 playbook syntax、
三个 inventory 检查，并要求 PR / main CI 和发布制品下载校验。新工具另通过 VM 启动、
7 台空白节点严格 SSH 与 systemd/cgroup/VIP 门禁、重复 hosts 保留全部容器 ID；
它使用旧源码快照，只证明环境准备流程。

**仍未通过：** 混合 RW/RO/自动分离端口事务流程偶发只读拒写、默认自动证书的严格 TLS
校验、配置 UUID 与 AdminAPI 实际组 UUID 一致性。失去多数派能阻止写入，但重启节点未
自动恢复，需要受控恢复。新小规格参数边界有自动回归，DEB 分支没有本轮运行时证据。

容器共享 Ubuntu ARM64 内核，不能代替真实 RHEL 内核、SELinux enforcing、生产 PKI、
跨机器故障、物理断电或性能容量验收；NFS/rsync 目标也未实测。本版不是生产验收声明。

## 升级与回退

先保存 inventory、Vault、配置和可恢复备份。在 staging 使用原主入口执行部署及重复
收敛，再按维护窗口应用；单独 `--apply-config` 不负责安装新增包或迁移账号。
已有自定义 backup_config 应补齐 percona_release 公钥 URL、摘要与指纹字段。
不要删除 Router keyring、默认强制 rebootstrap，或通过关闭 super_read_only 绕过错误。
回退 Git tag 不会回退数据库账号、RPM 或数据；发现失败应停止后续批次并按备份恢复方案处理。

源码归档附 `SHA256SUMS`，下载到同一目录后执行：

```bash
shasum -a 256 --check SHA256SUMS
```
