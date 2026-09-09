# 单独执行内核优化

## 适用条件

此操作只运行内核优化 playbook，不安装 MySQL、Router、HAProxy 或 Keepalived。
不需要完整集群 inventory，也不需要数据库密码；需要 Linux、Python 3.9+、SSH 和提权权限。
它会修改系统参数、limits、THP 与 I/O 相关配置，应在维护窗口执行，容器环境不要执行。

先完成 [公共准备](COMMON.md) 的控制端依赖与 SSH 指纹步骤。可只创建下面的本地 inventory：

```bash
umask 077
(set -o noclobber; cat > inventory/kernel.local.yml <<'YAML'
all:
  children:
    kernel_targets:
      hosts:
        host1:
          ansible_host: 192.0.2.11
  vars:
    ansible_user: root
    ansible_python_interpreter: auto_silent
YAML
)
${EDITOR:-vi} inventory/kernel.local.yml
```

替换文档地址，按需填写 SSH 私钥路径或提权配置。RHEL 8 要提前安装 Python 3.9。

## 执行

```bash
source .venv/bin/activate
ansible kernel_targets -i inventory/kernel.local.yml -m ping
ansible-playbook -i inventory/kernel.local.yml playbooks/kernel-optimization-stable.yml --syntax-check
./scripts/deploy_dedicated_routers.sh --kernel-optimize-only \
  -i inventory/kernel.local.yml --limit kernel_targets
```

如只处理某台机器，将 `--limit kernel_targets` 改为 `--limit host1`。
不要同时传 `--skip-kernel-optimization`；内核专项入口本身就是显式执行内核操作。

## 验证

备份目录由 `mysql_kernel_backup_root` 控制，默认 `/var/backups/mysql-kernel/<时间戳>`，
与 `/etc/sysctl.d` 分离，备份失败会中止后续修改。实际报告在目标机 `/root/` 下。

```bash
ansible kernel_targets -i inventory/kernel.local.yml -b -m command \
  -a 'sysctl net.core.somaxconn fs.file-max vm.swappiness'
ansible kernel_targets -i inventory/kernel.local.yml -b -m shell \
  -a 'ls -lt /root/mysql_kernel_optimization_stable_report_*'
```

逐机检查报告中的成功/失败项以及实际值。内核能力与发行版不同，不能只凭命令退出码认定所有
调优项都生效；对不支持的 BBR、THP 或 I/O 调度器，按报告确认并采用目标环境支持的设置。

## 排障与回退

- SSH/解释器失败：先处理登录、提权与 Python，不通过全量部署绕过。
- 参数未生效：检查内核支持、系统配置覆盖顺序和报告输出。
- 回退前从报告确认本次备份目录；将备份中的 sysctl.conf、limits.conf、sysctl.d
  与现有文件对比后恢复，并移除本次新增且旧环境不存在的配置。
- 还需单独核对 `disable-thp-stable.service`、`optimize-io-stable.service` 和
  `/usr/local/bin/optimize-io-stable.sh`；配置文件备份不是整个操作系统快照。
- `sysctl --system` 会应用所有系统配置，THP/I/O 的运行时状态也需核对；必要时在维护窗口重启。

若主机已有其他调优管理工具，先统一配置归属，避免两个工具反复覆盖。

## 重复执行与结果判定

受管 sysctl 参数统一写入 `/etc/sysctl.d/99-mysql-stable-optimization.conf`；旧
`/etc/sysctl.conf` 中同名的受管项会在备份后移除，其他参数保留。每项运行值会与期望值
核对，失败时不报告整体成功。报告列出期望值、实际值和逐项结果。

每次执行都会确认 THP 与 I/O 持久化服务已启用；即使 unit 文件未变化，也能恢复被禁用的服务。
THP 以输出中实际选中的 `[never]` 为准，而不是仅包含可选项 `never`。目标必须为 Linux。
重启后复查服务启用状态及实际参数，不能用文件存在替代持久化验证。
