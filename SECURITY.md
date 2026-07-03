# Security Policy

## Supported Versions

当前项目以 `main` 分支和最新 GitHub Release 为主要维护对象。历史版本仅根据维护者时间和影响范围酌情处理。

## Reporting a Vulnerability

Please report security issues through GitHub Security Advisories or contact the project maintainers.

请不要在公开 Issue、PR、讨论区或截图中披露以下内容：

- 真实 SSH 密码、MySQL 密码、Vault 密钥、API Token、私钥。
- 可直接访问的生产 IP、域名、VPN、堡垒机或内网拓扑。
- 可复现的漏洞利用步骤，除非维护者已确认可以公开。
- 未脱敏的业务数据库、表名、账号或审计日志。

## Scope

安全范围包括：

- Ansible playbook、inventory、模板和脚本中的敏感信息处理。
- 默认配置是否可能导致误用。
- 部署、备份、缩容、回滚流程中的破坏性风险。
- 文档和示例中可能引导用户泄露 Secret 的内容。

不在当前安全范围内：

- 用户自定义环境中的第三方组件漏洞。
- 未按文档替换默认配置导致的环境误配置。
- 未经授权的生产环境渗透测试请求。

## Response

维护者会尽量在收到报告后确认问题影响范围，并根据严重程度决定修复、缓解、文档提醒或发布新版本。由于这是开源项目，响应时间取决于维护者可用性。

## Secret Handling

- 部署前必须替换 `CHANGE_ME_*` 占位符。
- 生产环境建议使用 Ansible Vault、SSH key、CI/CD Secret 或专用 Secret Manager。
- 不要把真实 Secret 提交到仓库历史中。
