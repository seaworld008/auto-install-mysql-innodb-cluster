# 应用接入指南

## 选择入口

事务写入、DDL 和读后写一致性访问优先使用 VIP `3307`，只读报表等允许副本延迟的访问使用
`3308`。直连 Router 的对应端口是 `6446` 和 `6447`。

`3309` / `6450` 提供自动读写分离，适合在应用验证后按需采用。验证应覆盖驱动版本、
连接池复用、autocommit、显式事务、会话变量、预编译语句，以及事务开始前的查询序列。
复杂混合端口事务兼容性尚未全面确认，不能把简单 SELECT 连通测试当作应用验收。
若出现只读拒写，停止自动重试写入，使用明确 RW 入口核对事务行为。

## TLS 与证书

生产接入使用组织管理的 CA 和匹配端点名称的证书。自动生成证书适用于初始化，不能
直接替代生产 PKI。当前项目不自动签发、分发或轮换组织证书，需由环境配置管理完成。

Router 终止 TLS 时，需要分别检查客户端到 Router、Router 到 MySQL 的两段连接：

| 链路 | 配置关注点 |
| --- | --- |
| 客户端 → Router | 客户端要求验证 CA 与身份；Router 配置受信任证书及私钥 |
| Router → MySQL | 要求加密，并使用 `server_ssl_verify=VERIFY_IDENTITY` 与正确 CA |

Router 的 `server_ssl_mode` 和 `server_ssl_verify` 分别控制加密与证书验证，不能只打开
加密就认为完成身份验证。参数定义见 [MySQL Router 官方配置说明](https://dev.mysql.com/doc/mysql-router/8.4/en/mysql-router-conf-options.html)。

证书应覆盖客户端实际连接的 DNS 名称或 IP；经 VIP 接入时，两个 Router 都应提供对该
业务端点有效的证书。分别验证正常连接、错误 CA、名称不匹配及过期证书被拒绝，再进行
故障切换。不要通过关闭证书校验消除连接错误。

准备好证书后可用交互密码验证明确的 RW 入口：

```bash
mysql --host=db.example.com --port=3307 --user=app_user --password \
  --ssl-mode=VERIFY_IDENTITY --ssl-ca=/secure/path/organization-ca.pem
```

示例域名和路径必须替换为已签发证书对应的值。HAProxy stats 默认仅监听回环地址，
观察时使用 SSH 转发，不将管理页面公开到业务网络。

## 连接池与恢复

- 应用使用独立、最小权限账号，不使用集群管理账号。
- 使用有限的连接超时和带退避的重连，避免故障期间连接风暴。
- 连接断开不代表事务未提交。写入采用业务幂等键或事务查询确认，不能盲目重放。
- 故障切换后由连接池建立新连接；检查错误率、延迟和已确认写入完整性。
- 失去多数派时维持写入保护，按受控恢复流程检查节点与 GTID，不自动强制恢复。

## 集群身份

每个独立集群使用唯一 UUID。创建时，自动化通过 AdminAPI `groupName` 设置
`group_replication_group_name`；参见 [MySQL Shell 官方说明](https://dev.mysql.com/doc/mysql-shell/8.4/en/customize-your-cluster.html)。

接管已部署集群时，通过受保护连接执行：

```sql
SELECT @@GLOBAL.group_replication_group_name;
```

确认这是目标集群后，将本地 `mysql_group_replication_group_name_override` 设为该值。
状态检查会拒绝不匹配的成员。不要为匹配新配置而热改现有组身份。
