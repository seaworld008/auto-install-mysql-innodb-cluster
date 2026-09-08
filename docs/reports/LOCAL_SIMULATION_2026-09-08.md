# 本地 MySQL 集群模拟测试报告

## 结论

**原版 v0.3.1 未通过本机模拟部署；本轮在测试源码副本中修复了 10 类运行问题。修补后的主要部署、故障、扩缩容和备份恢复流程已验证，但仍不能据此认定当前 main 可直接用于生产。**

本报告记录 2026-09-08 实验结束时的状态。后续 v0.4.0 集成运行修复及可复用配置，并单独进行发布验证；历史测试不等于新版本的全部场景重新验收。原始日志与测试凭据只保存在本地，不随仓库发布。

- 测试基线：`cc47c0503aa95693cf50b819f418d8889d8a5af9`（v0.3.1）。
- 实施日期：2026-09-08，最终环境上限按用户调整为 6 CPU / 12 GiB。
- 运行方式：ARM64 VZ Linux VM + Rosetta，Rocky Linux 9 x86_64 容器内通过官方 RPM 安装服务，由 systemd 管理。容器不是预装 MySQL 的部署替代方案。
- Docker Engine/CLI 29.8.0；Lima 2.2.0；MySQL Server 8.4.11；Shell/Router 8.4.10；XtraBackup 8.4.0-6。
- Rocky 容器报告版本 9.3，软件包来自其 9 系仓库；共享的 VM 内核为 Ubuntu ARM64 Linux 6.8，不是 RHEL 内核。

## 功能验证

| 场景 | 结果 | 说明 |
| --- | --- | --- |
| 空白系统门禁 | 通过 | x86 二进制、签名 RPM、systemd、SSH、cgroup v2、VIP 地址操作实际执行 |
| 原版首次部署 | 失败 | 原始失败日志保留，不能视为生产可用版本 |
| 修补副本部署收敛 | 通过 | 经修复与分阶段重跑，形成 3 MySQL + 2 Router + 2 LB |
| 完整重复部署 | 通过 | 数据库 UUID、Router ID/keyring、表结构和数据保留 |
| 滚动配置更新 | 通过 | 持续写入下验证 wait_timeout=900、Router 连接上限=120；不等于零中断 |
| 整体停机及 VM 扩配后恢复 | 通过 | dry-run 后非强制 rebootClusterFromCompleteOutage，身份与数据不变 |
| MySQL 扩容、切主、缩容 | 通过 | 加入第 4 台，切至该节点，再通过 --new-primary 移除当前 primary |
| Router/LB 扩缩容 | 通过 | 分别添加第 3 台后缩容，保留最低 HA 数量；额外容器停机保留 |
| 逻辑备份及隔离业务库恢复 | 通过 | 数据哈希一致；字段、字符集/排序规则、索引、约束等结构元数据一致 |
| XtraBackup / prepare / copy-back / 隔离恢复 | 通过 | 行数、数据哈希及原始 SHOW CREATE TABLE 哈希均一致 |
| 失去多数派后的写入保护 | 通过 | 确认窗口内无写入 ACK，健康门拒绝通过 |
| 失去多数派后的自动重新入组 | 未通过 | 两节点重启后仍 NO_QUORUM，需要受控恢复 |
| 多数派丢失后的受控恢复 | 通过 | 确认节点状态后停止残留组，dry-run + 非强制完整停机恢复；未使用 forceQuorum |
| 备份默认关闭 | 通过 | 以明确的关闭原因拒绝操作 |
| 备份目标磁盘满 | 通过 | 仅填满 1 MiB tmpfs，备份返回失败且无成功清单；原数据完整 |

### 故障注入结果

写入负载使用明确的 RW 入口 3307。下表是约 5 次/秒合成负载的观测结果，不是生产 RTO/SLA。最大 ACK 间隔包含正常发送间隔、客户端超时及重连。

| 注入场景 | 结果 | 确认写入 | 失败尝试 | 最大 ACK 间隔（秒） |
| --- | --- | ---: | ---: | ---: |
| haproxy-stop | PASS | 346 | 12 | 3.38 |
| keepalived-stop | PASS | 356 | 2 | 1.27 |
| lb-crash | PASS | 345 | 3 | 3.65 |
| mysql-crash | PASS | 238 | 81 | 24.67 |
| router-active-crash | PASS | 362 | 1 | 0.85 |
| router1-crash | PASS | 364 | 0 | 0.80 |
| router2-crash | PASS | 363 | 0 | 0.64 |

两次指定 Router 故障可能未命中当前写连接，因此另加 router-active-crash：通过稳定 TCP 连接确认承载节点后再中断。

### 数据与恢复证据

最终 events 表 18,230 行，类型样本表 8 行；账本包含 8,227 笔已确认写入。已确认 ID 缺失数和内容不匹配数均为 0，10,000 条种子记录及类型样本完整。

样本包含中文、emoji、引号/换行、NULL、VARBINARY、JSON、DECIMAL 和微秒 DATETIME。所有业务数据均为合成数据，总量远小于 100 MiB；MySQL 系统文件、redo 和备份占用不包含在该业务数据量内。

恢复校验以备份时的 baseline 为准。备份完成后还进行了多数派丢失测试，因此不能拿后续新增的全部 ACK 直接要求历史备份包含。逻辑恢复只加载 ha_lab，并新建隔离的只读核验账号；未声称完整生产账号/权限或整个集群重建已验收。

逻辑恢复原始 DDL 哈希不同，原因是 SHOW CREATE TABLE 是否显式打印 CHARACTER SET。没有忽略差异：另行核对了表属性、字段类型/默认值/字符集/排序规则、索引和约束，均相同。详见 reports/logical-semantic-schema.json。

恢复夹具曾修正初始化顺序、local_infile 导入前置条件、账号 SQL 百分号参数和 systemd 就绪等待。失败尝试和日志均保留。local_infile 只在可信隔离恢复目标导入期间启用，结束后关闭；恢复实例保持复制组隔离并停机保留。

## 必须保留的未通过项

1. **自动读写分离的混合端口事务流程不稳定**：同一探针经 VIP 首轮重复仅 13/20 通过；对等探针直连 Router1 7/20、Router2 7/20、经 VIP 6/20。失败为只读拒写 1290。另一个独立单端口事务/前置查询矩阵 120/120 通过，说明现象与调用序列相关；尚未完成根因定位，不能归咎于 HAProxy，也不能把重试当修复。
2. **严格 TLS 校验未通过**：默认自动生成证书缺少 Authority Key Identifier，多个自动 CA 的名称/序列号相同也造成组合验证问题。本轮未部署生产 PKI 或降低校验后宣称通过；功能测试使用原隔离网络连接方式。
3. **配置 UUID 与实际组 UUID 不一致**：createCluster 自动生成的 UUID 与配置不同，通信栈实际为 MYSQL。未热改运行集群身份；需要明确 Ansible 与 AdminAPI 的配置所有权。
4. **小规格参数边界（后续已修正）**：原模板 max_connections=50 时生成 max_user_connections=-50；v0.4.0 改为预留 10%（最多 100）管理连接、至少 1 个用户连接，50 对应 45。已补边界回归；本历史实验未验证这一新边界。
5. **多数派丢失不能承诺无人工自愈**：本轮写入保护有效，但重启节点后未自动重入；受控恢复通过。生产恢复前仍必须核对存活节点、GTID 和隔离条件。

## 本地运行时补丁

下面 10 类问题已在测试副本中修复并走过相关实际路径。这些修复后续已纳入 v0.4.0 变更。涉及 DEB 分支的同类修改未在本轮 Rocky 环境执行。

| 编号 | 原问题 | 本地修正 | 主要证据 |
| --- | --- | --- | --- |
| 001 | curl-minimal 与 curl 冲突 | 保留目标机已有 curl 提供包 | deploy-original.log |
| 002 | MySQL 8.4 禁用 mysql_native_password，账号创建失败 | 使用 caching_sha2_password 和稳定 salt | deploy-patched-2.log |
| 003 | mysqlsh 读取不兼容的 client 字符集选项 | 显式 --no-defaults | membership-diagnostic.log |
| 004 | --no-wizard 导致初始密码提示被禁用 | 先从 stdin 认证，再关闭 AdminAPI 向导 | mysqlsh-password-diagnostic-2.jsonl |
| 005 | YAML 保留 SQL 字符串裸换行，JavaScript 语法错误 | 修正两处字符串格式，保留检查条件 | membership-yaml-exact.log |
| 006 | Router bootstrap 创建缺少 destinations 的裸 routing 段 | 对实际具名路由应用选项 | router-bootstrap-diagnostic.log |
| 007 | Router SQL 验证依赖 mysqlsh，但未安装 | 在配置官方仓库后安装 MySQL Shell | router-patched-6.log |
| 008 | Keepalived 未启用脚本安全，配置校验拒绝 | 启用 script_security 并显式指定脚本用户 | keepalived-validation-diagnostic.log |
| 009 | 重复部署在只读 secondary 执行 GRANT ALL | 独立实例或当前在线 primary 才写账号 | repeat-deploy.log |
| 010 | Percona Release RPM 签名公钥缺失 | 固定公钥 SHA-256 和完整指纹后导入 | backup-xtrabackup-attempt1.log |

原始合并补丁 SHA-256：`14ddc2585cfab08a2dfc7ea7dda29a3664e9b2f30094fda235109dff0256fc33`。已在独立原始源码副本上执行 git apply 检查并应用，结果与实际测试的 8 个修改文件逐字节一致。v0.4.0 补充自动回归并统一辅助脚本调用；DEB 跨平台实测仍待执行。

## 资源与存储

- 测试目录 du 约 **19G**，其中 VM 磁盘实际分配约 **15G**；虚拟磁盘逻辑上限 60 GiB。
- 系统临时目录运行元数据约 **20M**；已另存到外置盘 runtime/metadata-backup。
- VM free 的 used 列采样峰值约 **3.66 GiB**，不包含全部页缓存或宿主机预留内存，不能当作瞬时总峰值。
- 最终限制：MySQL 各 1 CPU/1536 MiB；Router/LB 各 0.5 CPU/512 MiB；控制容器 1 CPU/1024 MiB；VM 上限 6 CPU/12 GiB。数据库 buffer pool 保持 256 MiB、redo 128 MiB、连接上限 50。
- 入口节点最初 192 MiB 出现 OOM，阶段停止后调整为 384 MiB，再按用户新预算调整到 512 MiB。历史 OOM 保留记录；后续监控没有记录新 OOM。
- 采样存在时间间隔，短时恢复过程可能未捕获其峰值；详情见 reports/resource-summary.json 和 resource-samples.jsonl。
- 原 Colima default、aiops 保持停止状态，未删除或迁移它们的数据；未改变全局 Docker context。

## 验证边界与交付

- 没有验证真实 RHEL 内核、SELinux enforcing、生产防火墙、跨物理主机网络分区、硬件断电、存储故障或生产容量性能。
- 本轮只使用 local 备份目标；NFS/rsync 目标未实测。
- 33 项现有 Python 回归、18 个 playbook syntax-check、三个主 inventory 解析及 Shell 语法检查已通过；这些静态检查不覆盖上述所有运行问题。
- 日志/报告/源码/补丁/配置已按实际测试凭据扫描，未发现密码明文；合法的 secrets、备份和 VM 数据本身属于敏感本地资产，不在该扫描结论内。
- 使用、重建和清理见 [本机模拟方案](../runbooks/LOCAL_SIMULATION.md)。表中的日志名用于对应本地保留证据，不是仓库内可下载文件。

**上线前仍需解决混合事务路由、证书管理与组 UUID 配置归属问题，并在真实目标 Linux 环境完成验收。本报告不是生产上线许可。**
