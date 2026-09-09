# v0.4.1

本版完善开源文档入口，并加强集群身份、配置管理和本地模拟的可靠性。

## 改进

- 中英文 README 聚焦功能、架构、快速使用和文档导航，维护记录与版本历史独立组织。
- 快速开始补齐依赖安装；新增应用接入指南，统一端口、事务、TLS 与重连说明。
- 配置管理器支持 macOS 默认 Bash，从唯一配置源列出全部档位；无效配置返回失败。
- 档位切换采用原子写入，备份权限为 0600；恢复档位保留当前其他运行配置。
- 新建集群显式使用配置组 UUID；部署与状态检查拒绝成员身份不匹配。
- 本地模拟全流程核对 Lima 版本，部署前验证源码摘要，缺盘时拒绝恢复。

## 升级

已有集群升级前，读取 `SELECT @@GLOBAL.group_replication_group_name;`，核对目标集群后
将本地 `mysql_group_replication_group_name_override` 对齐到该值。不自动热改现有组身份。

`config_manager.sh --restore` 现在仅恢复备份中的硬件档位。完整配置回退需要明确的配置恢复操作。
旧模拟目录需用新版 `init` 在新目录生成源码摘要；生产部署入口与配置位置保持一致。

## 验证

Python 与 JavaScript 回归、Shell 语法、Markdown/YAML lint、全部 playbook syntax 和
主 inventory 解析通过。PR 与合并后的 main 验证完成后发布，源码归档附 SHA-256 校验。
本轮未重新创建完整集群；自动分离的复杂事务兼容性、组织 PKI 和实际部署拓扑仍需专项验收。

```bash
shasum -a 256 --check SHA256SUMS
```
