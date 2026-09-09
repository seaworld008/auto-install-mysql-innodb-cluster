# 本机低资源 MySQL 集群模拟

此方案用容器隔离 Linux 主机，MySQL、Router、HAProxy 和 Keepalived 仍通过
`scripts/deploy_dedicated_routers.sh` 和现有 Ansible 主流程安装、配置，由 systemd
管理。空白节点镜像没有预装数据库，不是另一套生产部署流程。

## 环境与存储

已执行的环境为 Apple Silicon Mac、Lima 2.2.0、ARM64 Ubuntu 24.04 VZ VM +
Rosetta、Rocky Linux 9 `linux/amd64` 容器、Docker Engine 29.8.0。
[最新实测报告](../reports/LOCAL_SIMULATION_2026-09-10.md)记录四种拓扑、组件、故障和恢复的实际结果。
Docker 与 Lima 在此固定为实验版本，不表示以后始终为最新版本。

- VM 上限 6 CPU / 12 GiB，60 GiB 稀疏磁盘。
- MySQL ×3：各 1 CPU / 1536 MiB；Router ×2、LB ×2：各 0.5 CPU / 512 MiB。
- 控制容器：1 CPU / 1024 MiB。临时扩缩容、恢复节点按阶段启动；OOM 时停止阶段并记录。
- `simulation_minimal` 配置在唯一运行配置 `inventory/group_vars/all.yml` 中：
  buffer pool 256 MiB、redo 128 MiB、50 连接。它不代表生产最低资源要求。
- 活跃 MySQL 数据在 VM 的 Linux Docker volumes 内，实际位于外置盘稀疏文件；
  不能直接将 Mac 共享目录当作 MySQL datadir。
- 输出仅允许位于当前仓库 `tmp/` 内。请把仓库放在外置盘。
- 只有 Lima 的短路径 socket 元数据在系统 `/tmp/mysql-lab-*`，由 manifest 标识归属；
  停机后另存到外置目录。VM 仅共享本次实验目录，不共享用户主目录。
- 不发布宿主端口，所有业务探针从隔离网络访问 VIP。节点不挂 Docker socket。
  systemd 所需 privileged 权限只存在于专用 VM 内。

## 快速重建

宿主需要 Python 3.12+（含 PyYAML）、`git`、`ssh-keygen`、`curl`、`qemu-img`、
Lima 2.2.0 和已安装的 Rosetta。`qemu-img` 仅用于在外置盘转换镜像，不运行 QEMU VM。
工具下载也应放在实验目录旁的 `tmp/lab-tools/`，不要更新已有 Colima 环境。

Lima 官方压缩包为
[2.2.0 Darwin arm64](https://github.com/lima-vm/lima/releases/download/v2.2.0/lima-2.2.0-Darwin-arm64.tar.gz)，
SHA-256：`bbdef91774885a0d05f7b048c4eb89ae2bcf3a0c252ae7ca7934e63df76d93c3`。
下载后先校验，再解包至 `tmp/lab-tools/lima-2.2.0/`；下面显式使用该路径，不覆盖系统安装。

在仓库根目录执行：

```bash
LAB_ROOT="$PWD/tmp/mysql-simulation"
PYTHON="$PWD/.venv/bin/python"
LIMACTL="$PWD/tmp/lab-tools/lima-2.2.0/bin/limactl"
"$PYTHON" tests/lab/lab.py --root "$LAB_ROOT" --ref HEAD --topology dedicated init
"$PYTHON" tests/lab/lab.py --root "$LAB_ROOT" --limactl "$LIMACTL" vm-create
"$PYTHON" tests/lab/lab.py --root "$LAB_ROOT" --limactl "$LIMACTL" start
"$PYTHON" tests/lab/lab.py --root "$LAB_ROOT" --limactl "$LIMACTL" hosts
"$PYTHON" tests/lab/lab.py --root "$LAB_ROOT" --limactl "$LIMACTL" deploy -- --production-ready
"$PYTHON" tests/lab/lab.py --root "$LAB_ROOT" --limactl "$LIMACTL" deploy -- --status
```

`init` 的运行源码只来自指定 Git commit，记录完整 SHA，拒绝覆盖既有目录。
实验生成器与 Dockerfile 来自当前工具，摘要写入 manifest；它们不会替换快照中的生产脚本。
它生成独立 SSH 密钥、强随机数据库密码、VIP 密码与组 UUID。

可将 `--topology dedicated` 改为以下任一选项；每个新环境使用不同的 `LAB_ROOT`，顺序启动：

| 选项 | Linux 节点布局 | 容器 CPU 合计 | 容器内存合计 |
| --- | --- | --- | --- |
| `dedicated` | 3 MySQL + 2 Router + 2 LB | 6 | 7680 MiB |
| `colocated` | 3 台主机，每台运行 MySQL + Router + LB | 5.5 | 8704 MiB |
| `mixed` | 3 MySQL（其中 2 台兼任 Router）+ 2 LB | 5 | 7680 MiB |
| `three-entry` | 3 MySQL + 3 Router + 3 LB | 5.98 | 8704 MiB |

表中已包含控制容器；VM 总上限仍为 6 CPU / 12 GiB，保留系统开销。
拓扑来自 `examples/topologies/`，优先使用快照内示例；旧提交缺少示例时使用当前工具的
示例，并在 manifest 中注明来源及摘要。测试地址只能从文档网段映射到专用网络，
不接受真实外部地址或未声明主机。共置角色复用同一主机身份。

控制容器依赖从该源码快照的 `requirements.txt`、`collections/requirements.yml` 复制。
每次重建记录实际镜像摘要；基础镜像标签和 RPM 仓库后续会变化，不能承诺包级逐字节重现。
如需逐包复现，另建经过签名验证的仓库快照，不关闭 RPM 签名检查。

`vm-create` 校验 Ubuntu 镜像摘要，将 qcow2 转为外置 raw 稀疏文件，再写入 Lima 2.2.0 的最小实例元数据（lima.yaml、lima-version）和短路径磁盘符号链接；不调用会提前复制磁盘的 `limactl create`，不使用 Lima 的系统盘下载缓存。
此元数据布局固定为 2.2.0，升级 Lima 必须重新验证。
失败时保留证据，检查 manifest 和磁盘，不能覆盖后继续假装成功。
`hosts` 构建空白节点，等待 systemd/sshd，从专用 Docker API 读取并固定主机公钥，
然后使用严格 SSH 检查执行 Ansible ping。
中途失败可重跑 `hosts`；它仅使用 `up --no-recreate` 补齐已有项目，拒绝未知同前缀容器
或已固定公钥变化。任一步失败，应停止后续场景。

命令失败会返回非零退出码。建议用 `set -o pipefail` 加 `tee` 保存输出至本地 reports。
不要打印 `secrets/runtime.yml`，也不要上传生成目录、镜像、日志、备份或 SSH 密钥。

## 可复用业务探针

初始化工具会生成单独的随机 `lab_app_password`，并把测试探针复制到 `config/probe/`，
在 manifest 中记录每个脚本的摘要，`probe` / `verify-ledger` 在执行前后均核对摘要。
脚本缺失、被修改或替换为符号链接时拒绝运行。探针属于测试工具，不负责安装软件或管理复制组。
它只接受本地模拟网段和已声明主机，默认测试固定的三类入口。

完整部署成功后执行一次初始化；已有 `ha_lab` 数据库时会拒绝覆盖：

```bash
"$PYTHON" tests/lab/lab.py --root "$LAB_ROOT" --limactl "$LIMACTL" probe init
"$PYTHON" tests/lab/lab.py --root "$LAB_ROOT" --limactl "$LIMACTL" probe ports --loops 50
(set -o noclobber; "$PYTHON" tests/lab/lab.py --root "$LAB_ROOT" --limactl "$LIMACTL" probe signature \
  > "$LAB_ROOT/reports/data-baseline.json")
```

探针生成 1000 条种子记录和 8 条类型样本，覆盖中文、二进制、JSON、精确小数、微秒时间与 NULL。
端口检查交替使用 RW、RO 和自动分离端口，包含只读拒写及事务前读、事务写入、读后写结果核对。
`--host` 可选择 inventory 中的 Router 地址，直连使用 6446/6447/6450；VIP 使用 3307/3308/3309。

在另一个终端持续写入，同时按测试表执行滚动变更或故障注入：

```bash
"$PYTHON" tests/lab/lab.py --root "$LAB_ROOT" --limactl "$LIMACTL" probe writer \
  --label writer-failover-01 --seconds 180
"$PYTHON" tests/lab/lab.py --root "$LAB_ROOT" --limactl "$LIMACTL" verify-ledger --label writer-failover-01
```

每次使用新的 `writer-` 标签；已有账本或停止标记时拒绝覆盖。写入约每 200 ms 发起一次，
时长最多 3600 秒。可创建 `reports/<标签>.stop` 提前结束，等待进程退出再校验。
校验器检查每条已确认写入的 ID 与内容，并单独报告未获确认但实际已提交的记录；
必须用 `--label` 指定本轮预期账本；缺失该文件时，旧账本不能替代本轮证据。
没有账本、空账本或完全没有成功写入时，不报告通过。需要汇总全部既有账本时，显式使用 `--all`。
切换到新建集群前先校验并归档旧账本，不能把旧集群的账本与新集群混合核对。

业务探针默认使用隔离实验的连接方式，不能据此宣称生产证书链或主机名严格校验通过。
生成数据、账本、配置中的凭据及未经脱敏的身份信息只保存在忽略目录中。

## 顺序测试方案与验收

测试数据全部合成，初始业务数据不超过 100 MiB；不做生产容量压测。
每阶段先保存 baseline，运行后记录“通过 / 失败 / 环境限制未执行”，不能降低健康门。
所有部署、配置、扩缩容和备份动作通过上面的 `deploy -- ...` 调用生产入口。
业务探针和故障注入可用 `docker -- ...` 操作专用 VM 内资源。

| 顺序 | 操作 | 必须保存的证据 |
| --- | --- | --- |
| 1 | 空白系统门禁；确认 x86 ELF、systemd PID 1、cgroup v2、SSH、RPM 签名安装、VIP 地址操作 | 架构、服务状态、软件版本、镜像摘要；失败即停 |
| 2 | `--production-ready`，再 `--status` | 3 成员 ONLINE、VIP 唯一归属；分别测试 RW/RO/自动分离入口 |
| 3 | 再执行完整部署，然后 `--apply-config` 修改低风险参数 | UUID、数据、Router ID/keyring 前后对比；实际参数生效；持续写入结果 |
| 4 | 分别停止 primary、活跃 Router、HAProxy、Keepalived；再模拟容器突然停止与重启 | 注入时间、已确认写入账本、失败/重连、最大 ACK 间隔、完整健康恢复 |
| 5 | 顺序创建 MySQL4、Router3、LB3；更新本地 inventory，再分别扩缩容 | 新节点加入；MySQL 切主后移除；缩容后从 inventory 摘除并重新完整健康检查 |
| 6 | `--backup` 分别执行 logical/XtraBackup；使用另一 internal 网络的恢复节点 | dump/load 或 backup/decompress/prepare/copy-back；表结构、行数、数据校验 |
| 7 | 停止两个成员导致失去多数派；备份默认关闭；有限空间目标满 | 多数派丢失窗口没有写入 ACK；健康检查失败；备份失败无成功清单 |
| 8 | 导出报告后停止容器和 VM | 最终数据校验、资源采样、磁盘 du、停止状态、复现步骤 |

### 管理员账号更新回归

在只含合成数据的三节点实验中，先用 `--mysql-only` 完成部署，记录节点 UUID、通告地址、
MySQL PID、表结构及数据摘要。通过 AdminAPI 把实际 primary 切至 inventory 中的第二台节点，
保持清单顺序，测试以下两种情况：

1. 只修改本地秘密文件中的 `mysql_cluster_password`，再执行 `deploy -- --mysql-only`。
   三节点都应接受新密码、拒绝旧密码，最终健康检查通过，基线身份与数据保持。
2. 在隔离实验的实际 primary 上通过已有 root 连接删除该测试管理员账号，确认删除已复制到
   三节点；再执行同一部署命令，应恢复管理员账号并通过最终健康检查，基线保持。

删除账号属于故障注入，仅限已核对身份的专用合成数据实验，不用于生产升级。
密码通过权限为 0600 的本地秘密文件或标准输入传递；报告只保存认证成败和摘要。
逐台 ONLINE 等待仍必须通过，不能通过跳过健康检查绕过账号更新顺序问题。

临时节点沿用 `config/compose.yml` 的 systemd、cgroup、资源和卷规则，使用未占用的
`.14` / `.23` / `.33` 地址；一次只添加一个角色，不能降低三数据库、双 Router、双 LB
的 HA 门槛。缩容使用 `--scale-mysql-remove --target ... --new-primary ...`、
`--shrink-router --limit ...`、`--shrink-lb --limit ...`。先完成逻辑摘除再停容器。
扩容参数及拓扑准备见 [操作指南](OPERATOR_GUIDE.md)，不另写 SQL 加入集群流程。

备份覆盖文件应从源码 `backup_config` 完整生成后只改 `enabled`、`method`、`type`
和必要并行度，避免 Ansible 字典浅覆盖丢失签名配置。备份默认仍关闭。
恢复见 [备份恢复指南](BACKUP_AND_RESTORE_GUIDE.md)。隔离恢复节点不能接入原复制组；
只在可信导入期间开启 `local_infile`，结束后关闭并只读校验。
恢复必须对备份时 baseline 校验，不能要求旧备份包含后续故障探针写入。

探针应为每次尝试生成唯一事务 ID，成功返回才记 ACK，并记录超时后的“不确定提交”。
校验所有已确认 ID 和内容、种子数据及类型样本；不能仅比行数或宣称 exactly-once。
逻辑恢复的原始 SHOW CREATE TABLE 若不同，保存差异，并核对字段、字符集/排序规则、
索引和约束等结构语义，不可静默忽略。

磁盘故障只在另挂的 1 MiB tmpfs 中写合成填充文件，不填满 VM 或外置盘。
失去多数派后先确认各节点和 GTID，按受控恢复手册 dry-run 再恢复；测试工具不自动
`forceQuorum`，不将手动恢复结果当作自动自愈。

## 停止、再启动与清理

```bash
"$PYTHON" tests/lab/lab.py --root "$LAB_ROOT" --limactl "$LIMACTL" stop
"$PYTHON" tests/lab/lab.py --root "$LAB_ROOT" --limactl "$LIMACTL" start
"$PYTHON" tests/lab/lab.py --root "$LAB_ROOT" --limactl "$LIMACTL" hosts
```

`hosts` 使用已保存的 Compose 与固定 SSH 指纹恢复节点，不重建容器。
`stop` 会先检查容器归属；发现其他项目容器时拒绝停止专用 VM。控制容器使用 init 转发退出信号，
旧环境的控制容器也不会占用数据库的完整停机等待时间。

启动 VM 不会重建或自动恢复 MySQL 复制组。完整停机后先检查集群状态，必要时按
[故障排查](TROUBLESHOOTING.md)受控恢复，再执行 `deploy -- --status`。
禁止对保留数据的环境执行全局 `compose up --force-recreate`：RPM 和 `/etc` 配置在
容器可写层，仅保留 Docker volume 不足以保存已安装主机。

彻底清理前：保存本方案、源码 SHA、配置生成器、版本清单与脱敏报告。
纯合成数据库、备份、镜像、凭据和原始日志随本次环境删除，不上传或保留为发布附件。
确认 manifest 的 owner、root、metadata 指向本次目录，容器和 VM 均已停止。
然后在**只对该命令生效**的 `LIMA_HOME=<manifest.metadata>` 下执行
`limactl delete mysql-ha`，核对后删除本次 `runtime/disk`、cache、source、secrets。
符号链接删除不一定删除外置目标文件，必须另查 `du`。
不要使用全局 Docker prune、删除 `~/.colima` 或整个 Lima 缓存目录。
本工具不提供一键删除，以保留明确的归属检查和备份检查步骤。

## 验证边界

每轮都要记录实际执行范围、源码 SHA 与配置摘要。当前完整记录见
[2026-09-10 实测报告](../reports/LOCAL_SIMULATION_2026-09-10.md)；
[2026-09-08 历史记录](../reports/LOCAL_SIMULATION_2026-09-08.md)只代表当时的源码与环境。
容器功能验证不替代真实 RHEL 内核、SELinux enforcing、跨主机网络故障、物理断电、
生产 PKI、防火墙、NFS/rsync 目标和性能容量验收。

技术参考：[Lima Rosetta](https://lima-vm.io/docs/config/multi-arch/)、
[Docker 29 版本说明](https://docs.docker.com/engine/release-notes/29/)。

### 历史工具整理验证记录

2026-09-09 本机重新验证了最小 Lima 元数据启动、Docker 29.8.0 安装、7 台空白节点的
x86_64 / systemd / cgroup / 严格 SSH 连通，以及 VIP 地址操作；再次执行 `hosts`
后所有容器 ID 保持不变。发现并修正了 Lima create 提前写磁盘与构建平台遗漏，原始
失败日志单独保留。本轮源码快照仍为 v0.3.1，因此这些只证明环境门禁，不是新运行修复
的完整集群重测。完整功能证据来自前述 2026-09-08 修补副本报告。

### 工具与源码一致性

所有生命周期操作都会校验 Lima 实际版本与 manifest 一致。缺失磁盘时拒绝恢复或启动，
不会按旧元数据创建新磁盘。`init` 同时记录源码内容、权限和链接摘要；`deploy` 前再次验证，
避免把已修改的测试副本结果归到旧提交。需要测试新补丁时，先提交，再使用新输出目录初始化。

## 原生 Linux 内核专项夹具

容器共享 VM 内核，不能用容器中的 sysctl/THP 结果代表独立主机调优。
需要验证 `--kernel-optimize-only` 时，先停止上面的集群 VM，再创建独立原生 Linux VM。
本轮使用的脱敏配置保存在 [native-kernel.yaml](../../tests/lab/native-kernel.yaml)：
Ubuntu 24.04 ARM64、2 CPU、3 GiB、12 GiB 稀疏磁盘，没有安装 Docker。

重建时沿用上文的外置磁盘原则：先把固定摘要的 Ubuntu 镜像下载至新实验目录，
用 `qemu-img convert -f qcow2 -O raw` 转换，再用 `qemu-img resize -f raw ... 12G`
设定上限。将模板的 `mounts[0].location` 替换为该实验目录；Lima 2.2.0 的实例元数据
放在独立短路径目录，`mysql-ha/disk` 只链接到该外置 raw 文件。不要对原有集群磁盘缩容。
此模板是独立 VM 夹具，不应直接覆盖已初始化的集群实验配置。

启动后，从该专用 Lima 实例读取 SSH 端口、登录用户和 Ed25519 主机公钥，固定指纹，
使用 SSH 连接的 inventory 执行 [内核专项命令](../scenarios/KERNEL.md)。
`ansible_connection` 必须为 `ssh`，不能用 `local` 将 Linux 调优误跑到 Mac 控制端。
内核操作不需要数据库凭据。控制端使用 Python 3.12+ 和仓库声明的 Ansible 依赖。

验收分四步：

1. 原生内核首次执行，逐项核对运行 sysctl、THP 和适用磁盘的 I/O 参数。
2. 重复执行，比较受管 sysctl、PAM、unit 和脚本内容摘要。
3. 人为禁用两个持久化 unit，并在该测试 VM 内改变 THP/I/O 参数；重跑后确认恢复。
4. 完整停止再启动 VM，重新核对所有值，另用 `systemd-run --wait --collect /bin/true`
   验证新 systemd 服务能够启动。保留未受管配置，不能通过删除系统配置消除冲突。

模板显式设置 `ssh_deletekeys: false`，避免该专用 VM 冷启动时 cloud-init 重建主机密钥。
仍必须比较固定指纹；出现变化先调查原因，不自动接受新指纹。
若外置目录过长导致控制端 Unix socket 路径超限，只把 `TMPDIR` 和
`ANSIBLE_SSH_CONTROL_PATH_DIR` 放入本次短路径元数据目录，下载、源码、磁盘与日志仍在外置盘。
设置 `PYTHONDONTWRITEBYTECODE=1`，避免 Ansible 给封存源码写入 Python 字节码缓存。

结束后与集群实验分别核对归属、删除 VM、外置 raw 磁盘及短路径元数据；
本模板和脱敏验收报告可保留，不保留 SSH 私钥、原始日志、备份或测试数据库。
原生 Ubuntu 的通过结果也不能替代 RHEL 内核与 SELinux enforcing 验收。
