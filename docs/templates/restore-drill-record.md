# 隔离环境恢复演练记录模板

> 恢复演练必须优先在新节点或隔离环境执行。除非已有维护窗口、回滚方案和人工审批，不要对线上集群做原地覆盖恢复。

## 1. 基本信息

| 项目 | 内容 |
| --- | --- |
| 演练日期 |  |
| 环境 |  |
| 执行人 |  |
| Git commit |  |
| Inventory |  |
| 备份类型 | `logical` / `xtrabackup` |
| 备份目标类型 | `local` / `nfs` / `rsync` |
| 备份时间点 |  |
| 恢复目标主机 |  |

## 2. 备份身份

| 项目 | 内容 |
| --- | --- |
| 备份目录 |  |
| Manifest 路径 |  |
| 源 MySQL 版本 |  |
| 源实例 UUID |  |
| 源 GTID / binlog 信息 |  |
| 备份大小 |  |
| 校验值 |  |

## 3. 恢复前检查

- [ ] 目标主机不是生产主节点
- [ ] 目标数据目录可以安全清空
- [ ] 目标 MySQL 版本与备份兼容
- [ ] 目标磁盘容量充足
- [ ] 已记录恢复开始时间
- [ ] 已准备失败清理方案

## 4. 恢复步骤

### 逻辑备份恢复

```bash
# 示例，按实际 dump 目录和连接参数替换
mysqlsh -- util loadDump /backup/mysql/<dump-dir> --threads=4
```

### XtraBackup 恢复

```bash
# 示例，按实际备份目录替换
xtrabackup --prepare --target-dir=/backup/mysql/<backup-dir>
systemctl stop mysql
rm -rf /data/mysql/*
xtrabackup --copy-back --target-dir=/backup/mysql/<backup-dir>
chown -R mysql:mysql /data/mysql
systemctl start mysql
```

实际执行记录：

| 步骤 | 命令 | 开始时间 | 结束时间 | 结果 |
| --- | --- | --- | --- | --- |
| 1 |  |  |  |  |
| 2 |  |  |  |  |
| 3 |  |  |  |  |

## 5. 数据校验

| 校验项 | 期望 | 实际 | 结果 |
| --- | --- | --- | --- |
| MySQL 服务启动 |  |  |  |
| 数据库列表 |  |  |  |
| 关键表数量 |  |  |  |
| 关键表行数 |  |  |  |
| 业务抽样查询 |  |  |  |
| 权限与账号检查 |  |  |  |
| GTID / binlog 状态 |  |  |  |

## 6. RTO / RPO 记录

| 指标 | 目标 | 实际 | 说明 |
| --- | --- | --- | --- |
| RTO |  |  |  |
| RPO |  |  |  |
| 备份回取耗时 |  |  |  |
| prepare 耗时 |  |  |  |
| copy-back 或 loadDump 耗时 |  |  |  |
| 校验耗时 |  |  |  |

## 7. 是否可用于生产恢复决策

- [ ] 可以作为生产恢复参考
- [ ] 只能作为技术验证，仍需补充业务校验
- [ ] 不可作为恢复依据，需要修复后重演

原因：

```text

```

## 8. 后续行动

| 行动项 | 优先级 | 负责人 | 截止时间 | 状态 |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |
