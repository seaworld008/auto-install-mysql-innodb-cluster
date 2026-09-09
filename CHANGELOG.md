# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) 的组织方式，并尽量使用语义化版本。

> 当前运行时真相源是 `inventory/group_vars/all.yml`；静态检查通过不等于真实环境验证完成。

## [Unreleased]

### 新增

- 增加独立、共置、混合、三节点接入层与组件操作的方案索引、拓扑模板和详细执行文档。
- 主入口支持单独部署 HAProxy / Keepalived，以及只读检查的分层 scope。

### 修复

- 组件部署与只读检查按实际操作校验凭据，Router / HAProxy 不再要求未使用的 MySQL 安装口令。

- Router 根据连接预算管理文件句柄上限，服务模板变化及进程限制漂移均能逐台收敛。

- MySQL 文件句柄档位通过 systemd 生效，滚动更新时校验内核、服务配置及运行进程的实际容量。

- 内核配置移除失效 sysctl，保护 systemd 所需的全局文件句柄上限，并核验 THP、I/O 与重启持久化。

- Router 空闲连接池上限纳入统一配置，默认关闭跨客户端复用，保持三类入口的事务路由与固定端口会话语义。

- 修复内核内存比例的数值计算、重跑持久化服务启用、sysctl 双写和实际值报告；内核应用与核验失败不再静默通过。
- 拒绝多个别名指向同一部署地址和重复入口优先级，避免虚增 HA 节点。
- 内核配置备份移出 sysctl 源目录，拒绝危险路径/符号链接与覆盖旧备份，失败时停止后续修改。
- 修复 Bash 3 空参数数组导致完整预检未执行的问题；检查范围在用户变量之后强制设置，避免误关完整 HA 门。

## [0.4.1] - 2026-09-09

### 改进

- 重写中英文 README 与文档导航，突出功能、架构和快速使用；版本历史与维护资料独立组织。
- 补齐快速开始的依赖安装，新增应用接入指南，统一事务、只读与自动分离入口说明。
- 配置管理器兼容 macOS Bash，动态读取硬件档位，严格验证配置；切换和恢复只修改档位选择。
- 所有模拟环境操作检查 Lima 版本；部署前验证源码摘要，缺盘时拒绝恢复元数据。

### 修复

- 创建集群显式传递配置组 UUID，既有成员与健康检查核对实际身份，避免配置被静默忽略。
- 修正配置管理器 Router 连接数显示、缺字段假成功及本地 inventory 检查输出到公共临时文件的问题。

### 升级说明

- 已有集群先读取实际 group_replication_group_name 并对齐本地 override，不热改运行中的组 UUID。
- 配置备份恢复现在仅恢复硬件档位；需要完整配置回退时，应按受控配置恢复流程操作。
- 本地模拟需使用新版 init 重新生成摘要清单；完整目标环境验收仍由使用方按部署拓扑执行。

## [0.4.0] - 2026-09-09

### 新增

- `tests/lab/` 提供专用 Lima/Rocky systemd 主机模拟的配置生成与生命周期工具；
  保存中文测试方案、脱敏报告、源码 SHA 和资源边界，所有生成数据留在忽略目录。
- 唯一运行配置新增 `simulation_minimal` 档位，低资源连接数不再产生负数上限。

### 修复

- 修复 curl-minimal 包冲突、MySQL 8.4 caching_sha2 账号创建和只读 secondary 重复授权。
- 统一 mysqlsh defaults/密码 stdin/向导调用顺序，并修复 YAML 内 SQL 字符串换行。
- Router bootstrap 不再生成空 routing 段，补装验证依赖 MySQL Shell。
- 启用 Keepalived 脚本安全；验证 Percona 公钥摘要与完整指纹后安装签名 RPM。
- 新增对应回归，保存模拟验证仍未通过的混合事务路由、严格 TLS、组 UUID 等边界。

## [0.3.1] - 2026-09-08

### 修复

- 修复 Ubuntu/Debian 新版 libaio 包名与滚动安装跨节点 facts 依赖，消除首次部署阻塞。
- 所有 play 在任一节点失败时整体中止，preflight 增加拓扑、单节点滚动批次、
  server_id 上限和规范化唯一性、Router 端口冲突与危险目录检查。
- 已 bootstrap Router 的受管配置能够原子收敛，保留身份和 keyring，实际变化才重启。
  统一读写分离路由，消除与默认 bootstrap 路由重复绑定的问题。
- 主 CLI 拒绝被静默忽略的目标参数和缩容主机参数注入。
- 备份路径增加目录约束，rsync 本地源路径使用 shell quoting。
- CI 对每个 Shell 脚本单独执行语法检查，新增真实 Ansible 失败传播和模板/配置转换测试。

### 维护

- 删除当前 Router 配置中未生效的线程、内存、连接池和 metadata 缓存字段。
- 合并 deploy-pages 5.0.1 的轮询退避更新（PR #14），保留完整 SHA 固定。
- 同步部署升级文档。静态/CI 通过不表示已完成真实部署、故障或备份恢复验收。

## [0.3.0] - 2026-08-28

### 新增

- 新增 `validate-ha.yml` 组合门，先执行 preflight，再执行 fail-closed 健康
  playbook；要求每个 inventory MySQL 节点 `ONLINE`、Cluster 为 `OK` 且成员数
  匹配，并检查启用的 Router、HAProxy、Keepalived、端口及 VIP 唯一归属。
- 新增 GitHub Actions CodeQL 扫描和 Dependabot 的 pip / Actions 周期更新。
- 新增 Python 仓库契约与主入口测试，并在 Python 3.12 / 3.13 CI 矩阵执行。
- 新增 `validate_deployment.ps1` PowerShell parser 门，并在两个 Python matrix
  job 中执行。
- 新增 GitHub Pages 文档站、英文入口、staging / 故障 / 恢复演练模板，以及
  开源协作文件。
- 新增 Git 忽略的本地 inventory 与 Vault 工作流；服务器向导会为独立集群生成
  唯一 Group Replication UUID。

### 变更

- 作为 pre-1.0 非兼容安全收敛，移除
  `haproxy_backend_target: mysql` 路径，并默认启用严格 SSH host-key 校验。
- 主入口支持 `-e` / `--extra-vars`、`--ask-vault-pass` 和
  `--vault-password-file`，并把参数透传到 preflight、部署和健康检查。
- Router 仅在首次部署或显式设置 `mysql_router_rebootstrap: true` 时
  bootstrap；bootstrap 和 MySQL Shell 调用通过标准输入传递密码。
- 集群配置先识别成员状态，只对 standalone 节点执行配置检查并加入集群，已有成员
  不再重复运行 `configureInstance`，最终等待全部 inventory 成员 `ONLINE`。
- MySQL、Router 和入口层缩容增加单目标与最小节点数校验；MySQL 缩容还包含
  primary 切换和剩余成员健康复核。
- HAProxy 只使用 Router 后端；stats 默认仅监听 `127.0.0.1`。
- Keepalived 使用 HAProxy systemd 检查，连续失败时进入 `FAULT` 并释放 VIP。
- 自定义 MySQL datadir 只从已初始化且受支持的默认目录迁移，拒绝覆盖非空未知目录，
  通过中断标记支持安全重跑，同时收敛 AppArmor / SELinux 文件上下文并校验最终
  运行时 datadir。
- MySQL GPG key 与 Percona release 包使用固定 SHA-256 校验；rsync 备份要求
  预置并严格校验 SSH `known_hosts`。
- 文档 Markdown / YAML lint 从 advisory 提升为阻断门；GitHub Actions 均固定到
  完整 commit SHA。
- Dependabot 的 pip 更新仅在现有版本范围无法覆盖新版本时调整约束，避免无理由
  抬高仍受支持的 `ansible-core` 最低版本。
- 控制节点 `requirements.txt` 收敛为仅安装带版本范围的 `ansible-core`；
  collections 单独声明，目标 PyMySQL 由可信系统仓库安装。
- 控制节点要求 Python 3.12+，preflight 在所选目标组首次模块连接前探测
  Python 3.9+。
- 主文档和项目结构说明更新到当前统一入口、本地 inventory、逻辑 / XtraBackup
  备份及验证边界。

### 安全

- tracked inventory 只保留脱敏示例，禁止写入真实 IP、SSH 凭据、私钥路径或明文
  Secret。
- SSH 默认启用严格主机密钥校验，移除跳过 `known_hosts` 校验的示例和配置。
- Keepalived 口令改为明确占位符，并由 preflight 阻断默认值或不合法长度。
- Keepalived 配置以 `0600` 写入，模板任务保持 `no_log`；默认 VIP 改为会被
  preflight 阻断的 RFC 5737 地址 `192.0.2.100`。
- MySQL Shell、Router bootstrap 和 XtraBackup 不再把数据库密码放入命令行参数。
- `cluster-status.sh` 与 `failover-test.sh` 隐藏读取密码或使用受保护环境变量，
  并通过 stdin 交给 mysqlsh，不把密码写入 argv。

### 修复

- 修复 health/status 对 inventory 变量读取错误和健康命令失败被吞掉的问题。
- 修复健康检查只打印提示却未阻断非健康 Cluster、服务、端口或 VIP 的问题。
- 修复 HAProxy 直连静态 MySQL primary 在主从切换后可能继续接收写流量的问题。
- 修复 Keepalived 健康脚本失败后仍可能保留 VIP 的问题。
- 修复健康门只检查 VIP 存在、未阻断双主同时持有 VIP 的问题；现在要求 VIP
  恰好出现在一个入口节点。
- 修复 Router 共享 bootstrap 账号和无条件重复配置集群成员的非幂等路径。
- 修复自定义 datadir 在安装后未安全迁移、迁移中断无法恢复、RedHat SELinux
  上下文缺失与未验证运行时目录的问题。
- 修复 MySQL / Percona 仓库下载缺少摘要校验，以及 rsync 备份关闭 SSH 主机密钥
  校验的问题。
- 修复 RedHat 重跑无条件依赖首次临时 root 密码的问题；现在先用 0600 临时
  option file 探测目标密码，必要时才执行密码重置，并在无安全恢复路径时阻断。
- 修复压缩 XtraBackup 同时启用 prepare 时未先解压的问题。
- 修复 rsync 备份未验证 `known_hosts` / 私钥 owner 与权限的问题。
- 修复旧文档指向不存在的 `docs/*.md` 路径。

### 验证边界

- 本版本包含静态检查、仓库契约测试、Ansible syntax / inventory 校验和 CI 门。
- 尚未在真实 staging 执行完整部署、故障切换、扩缩容、备份恢复或性能容量验证，
  因此不据此宣称生产验收完成。

## [0.2.0] - 2026-03-25

### 新增

- 统一运行时配置模型，以 `inventory/group_vars/all.yml` 作为单一真相源。
- 统一主入口：`scripts/deploy_dedicated_routers.sh`。
- 默认使用 MySQL 8.4 LTS，同时保留 MySQL 8.0 兼容。
- 新增单端口自动读写分离入口：
  - HAProxy VIP：`3309`
  - MySQL Router 直连：`6450`
- 保留显式读写和只读入口：
  - HAProxy VIP：`3307 / 3308`
  - MySQL Router 直连：`6446 / 6447`
- 新增 MySQL、Router 与 HAProxy 扩缩容和滚动应用当前配置流程。
- 新增独立内核优化动作：`--kernel-optimize-only`。
- 新增可选 MySQL Shell 逻辑备份与 Percona XtraBackup 物理备份，支持本地目录、
  NFS 及 SSH + rsync 目标。
- 新增备份恢复 runbook：`docs/runbooks/BACKUP_AND_RESTORE_GUIDE.md`。
- 新增 AI 维护说明：`AGENTS.md`、`docs/maintainers/AI_MAINTAINER_GUIDE.md`。
- 增强 GitHub Actions 静态质量门，覆盖 Ansible syntax-check 和 inventory 校验。

### 变更

- 将此前分散的脚本能力收敛到当前生产部署主线。
- Router bootstrap 行为更偏保守和幂等。
- 围绕当前主线同步文档。

## [0.1.0] - 2025-07-09

### 新增

- MySQL InnoDB Cluster 自动化仓库首次公开发布。
- 提供 MySQL Server 安装、InnoDB Cluster 配置和 MySQL Router 设置的基础
  Ansible 结构。

## 历史记录

### 2024-12-28 - 8C32G + 4C8G 优化配置成为默认设计基线

- 引入 8C32G MySQL + 4C8G Router 容量模型。
- 新增 `scripts/config_manager.sh`，用于切换硬件配置。
- 新增历史硬件配置快照。
- 更新 Router 部署和容量分析相关文档。

### 2024-12-27 - 高并发调优

- 增加 Router 与 MySQL 高并发配置思路。
- 增加系统参数调优说明。
- 增加监控与告警说明。

### 2024-12-26 - 初始内部基线

- 增加初始 MySQL InnoDB Cluster 部署脚本。
- 增加 3 节点 MySQL 集群基础支持。
- 增加 MySQL Router 基础配置。
