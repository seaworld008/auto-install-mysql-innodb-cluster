# 备份与恢复指南

本指南面向当前仓库主线，覆盖：

- 逻辑备份（MySQL Shell Dump）
- 物理备份（Percona XtraBackup）
- 本地目录 / NFS / rsync 远端目录
- 恢复建议流程

说明：

- 当前仓库已经将“备份”纳入主入口
- “恢复”目前以运维 runbook 形式提供，不做一键覆盖式自动恢复
- 生产环境恢复强烈建议先在新节点或隔离环境验证，再决定是否回切业务流量

## 1. 当前主线支持的备份能力

主入口：

```bash
./scripts/deploy_dedicated_routers.sh --backup -i inventory/hosts-with-dedicated-routers.yml
```

配置入口：

- `inventory/group_vars/all.yml`
- `backup_config`

支持：

- `backup_config.method: logical`
- `backup_config.method: xtrabackup`

目标类型：

- `local`
- `nfs`
- `rsync`

## 2. 什么时候选逻辑备份，什么时候选物理备份

### 逻辑备份（logical）

适合：

- 数据量中小
- 需要跨版本逻辑导入导出
- 需要按对象级别恢复
- 希望更直观地查看导出内容

特点：

- 默认走 `mysqlsh util.dumpInstance`
- 可读性好
- 迁移与部分恢复更灵活

### 物理备份（xtrabackup）

适合：

- 数据量较大
- 需要更快的全量备份
- 希望保留物理文件级恢复能力
- 对恢复速度更敏感

特点：

- `MySQL 8.0` 对应 `Percona XtraBackup 8.0`
- `MySQL 8.4` 对应 `Percona XtraBackup 8.4`
- 更适合全量恢复

## 3. 推荐执行节点

建议：

- 逻辑备份：默认可在 `mysql_primary` 执行
- 物理备份：更推荐切到 `mysql_secondary`

原因：

- 降低对主节点写流量的影响
- 减少备份时对业务路径的扰动

推荐配置示例：

```yaml
backup_config:
  enabled: true
  run_on_host_group: "mysql_secondary"
```

## 4. 备份配置示例

### 4.1 逻辑备份到本地目录

```yaml
backup_config:
  enabled: true
  method: "logical"
  type: "local"
  base_dir: "/backup/mysql"
  retention_days: 7
  run_on_host_group: "mysql_primary"
```

### 4.2 逻辑备份到 NFS

```yaml
backup_config:
  enabled: true
  method: "logical"
  type: "nfs"
  base_dir: "/mnt/mysql-backup"
  retention_days: 14
  run_on_host_group: "mysql_primary"
```

### 4.3 逻辑备份到远端目录（rsync）

```yaml
backup_config:
  enabled: true
  method: "logical"
  type: "rsync"
  base_dir: "/backup/mysql"
  remote_host: "10.10.10.20"
  remote_user: "backup"
  remote_dir: "/data/mysql-backups"
  ssh_key_path: "/root/.ssh/backup_rsa"
  run_on_host_group: "mysql_primary"
```

### 4.4 XtraBackup 到本地目录

```yaml
backup_config:
  enabled: true
  method: "xtrabackup"
  type: "local"
  base_dir: "/backup/mysql"
  run_on_host_group: "mysql_secondary"
  xtrabackup:
    parallel: 4
    compress: false
    prepare: false
    use_memory: "1G"
```

### 4.5 XtraBackup 到 NFS

```yaml
backup_config:
  enabled: true
  method: "xtrabackup"
  type: "nfs"
  base_dir: "/mnt/mysql-backup"
  run_on_host_group: "mysql_secondary"
  xtrabackup:
    parallel: 4
    compress: true
    compress_algorithm: "zstd"
    compress_threads: 2
    prepare: false
```

### 4.6 XtraBackup 到远端目录（rsync）

```yaml
backup_config:
  enabled: true
  method: "xtrabackup"
  type: "rsync"
  base_dir: "/backup/mysql"
  remote_host: "10.10.10.20"
  remote_user: "backup"
  remote_dir: "/data/mysql-backups"
  ssh_key_path: "/root/.ssh/backup_rsa"
  run_on_host_group: "mysql_secondary"
  xtrabackup:
    parallel: 4
    compress: false
    prepare: false
```

## 5. 执行备份

```bash
./scripts/deploy_dedicated_routers.sh --backup -i inventory/hosts-with-dedicated-routers.yml
```

成功后，当前实现会在备份目录下生成按时间和主机区分的目录结构。

## 6. 恢复原则

### 强烈建议

不要在未验证的情况下，直接对现网集群做原地覆盖恢复。

推荐原则：

1. 先在隔离环境或新节点恢复
2. 校验数据完整性
3. 确认业务检查通过
4. 再通过标准集群流程切回

### 恢复优先策略

- 逻辑备份：更适合对象级、库级恢复
- 物理备份：更适合整实例恢复、全量快速恢复

## 7. 逻辑备份恢复建议流程

### 7.1 恢复到新实例

1. 准备一台新的 MySQL 节点
2. 安装与当前版本一致的 MySQL
3. 使用 MySQL Shell 导入 dump
4. 校验对象、数据量、关键业务表
5. 如需要，把该实例按标准流程加入集群

### 7.2 恢复思路

逻辑备份恢复更适合：

- 导回单个库
- 导回部分对象
- 做数据抽取式恢复

### 7.3 生产建议

- 不建议把逻辑备份恢复直接做成覆盖线上主节点的自动化动作
- 建议始终先导入到新实例或隔离实例

## 8. XtraBackup 恢复建议流程

### 8.1 恢复到新节点（推荐）

推荐步骤：

1. 准备一台干净的新节点
2. 安装与备份对应的 MySQL 版本
3. 如果备份未 `prepare`，先执行 `xtrabackup --prepare`
4. 停止 MySQL 服务
5. 清理目标数据目录
6. 执行 `xtrabackup --copy-back` 或等价恢复方式
7. 修正数据目录权限
8. 启动 MySQL
9. 校验实例可用性
10. 如需要，再以标准方式加入集群

### 8.2 恢复后的关键检查

- `mysql` 服务能正常启动
- `SHOW DATABASES` 与预期一致
- 关键表数量 / 行数与预期一致
- binlog / GTID / Group Replication 相关状态正常

### 8.3 关于 prepare

如果在备份阶段没有启用：

```yaml
backup_config:
  xtrabackup:
    prepare: false
```

那么恢复前必须先对备份目录执行 `prepare`。

## 9. rsync 远端目录模式说明

当前主线的 rsync 流程是：

1. 先在本地 `base_dir` 生成备份
2. 再同步到远端目录

这意味着：

- 远端目录适合作为集中归档
- 恢复时通常需要先把备份再取回到目标主机，或直接在远端挂载访问

## 10. 与扩容/缩容的关系

建议：

- 备份成功后再做高风险缩容
- 做恢复演练时，优先用新节点恢复，再决定是否加入集群
- 不建议把“缩容 + 恢复 + 回切”混成一个自动化动作

## 11. 推荐运维流程

### 日常备份

```bash
./scripts/deploy_dedicated_routers.sh --backup -i inventory/hosts-with-dedicated-routers.yml
```

### 恢复演练

1. 用备份恢复到新实例
2. 校验业务数据
3. 记录恢复耗时
4. 形成恢复手册

### 上线前建议

至少做一次：

- `logical` 恢复演练
- `xtrabackup` 恢复演练
- `rsync` 远端目录回取演练（如启用）

## 12. 当前边界

当前仓库已经支持：

- 逻辑备份执行
- XtraBackup 物理备份执行
- local / nfs / rsync 落盘

当前仓库还没有做成：

- 一键自动恢复线上集群
- 一键切流恢复
- 一键 restore + rejoin + traffic cutover

这部分建议继续保持为人工审核的运维 runbook，而不是现在就做成危险的自动动作。
