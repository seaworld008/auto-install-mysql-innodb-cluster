# 发布前检查清单

本清单用于从 PR 到 tag、GitHub Release 和下载复验的完整交付。静态门、tag 和
Release 不替代真实环境验收。

## 1. 内容与安全审计

- [ ] `CHANGELOG.md` 已增加目标版本和日期，`Unreleased` 保持空白
- [ ] Release notes 与本次 diff 一致，没有无法证实的生产或性能声明
- [ ] README、部署指南、runbook、变量参考与实际实现同步
- [ ] tracked inventory 只含脱敏示例
- [ ] **未**把真实 IP、SSH 凭据、私钥路径、Vault 文件、Vault 口令或 Secret 写入
  tracked inventory、文档、测试、提交信息或 PR
- [ ] 所有 `CHANGE_ME_*`、示例 UUID 和示例 VIP 只作为 fail-closed 占位符
- [ ] `requirements.txt` 只包含 `ansible-core`；控制 Python 3.12+ 和目标
  Python 3.9+ 契约已同步
- [ ] 默认 VIP 是被 preflight 阻断的 RFC 5737 `192.0.2.100`，tracked
  inventory 未替换成真实环境地址
- [ ] Keepalived 配置为 `0600` 且模板任务 `no_log`
- [ ] rsync `known_hosts` / 私钥 owner 与权限校验仍为 fail closed
- [ ] 压缩 XtraBackup 在 prepare 前先 decompress
- [ ] 辅助脚本未把 MySQL 密码放入 argv
- [ ] `git diff` 已人工检查，不包含生成物、日志、临时文件或无关用户改动

真实部署值只能进入 Git 忽略的本地 inventory、加密 Vault、CI Secret 或外部
Secret Manager。

## 2. 本地阻断门

在干净、同步远端的发布分支执行：

```bash
git diff --check origin/main...HEAD
for script in deploy.sh validate_deployment.sh scripts/*.sh; do
  bash -n "$script" || exit 1
done
./.venv/bin/python -m pip check
./.venv/bin/python -m unittest discover tests -v
npx --yes markdownlint-cli2@0.23.2
./.venv/bin/yamllint .
```

如本机有 `pwsh`，直接执行 PowerShell parser；没有时必须明确记录“本机未执行”，
并由两个 CI Python matrix job 的 `PowerShell syntax check` step 提供证据：

```bash
if command -v pwsh >/dev/null 2>&1; then
  pwsh -NoProfile -Command '
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
      (Resolve-Path "validate_deployment.ps1"),
      [ref] $tokens,
      [ref] $parseErrors
    ) > $null
    if ($parseErrors.Count -gt 0) {
      $parseErrors | ForEach-Object { Write-Error $_ }
      exit 1
    }
  '
else
  printf '%s\n' \
    '本机未安装 pwsh：PowerShell parser 本机未执行，必须核对两个 CI matrix job。'
fi
```

对全部 playbook：

```bash
for playbook in playbooks/*.yml
do
  extra_vars=()
  if [[ "$playbook" == "playbooks/shrink-mysql.yml" ]]; then
    extra_vars=(
      --extra-vars
      "mysql_shrink_target=mysql-node3 mysql_shrink_new_primary=mysql-node2"
    )
  fi
  ./.venv/bin/ansible-playbook \
    -i inventory/hosts-with-dedicated-routers.yml \
    "$playbook" --syntax-check "${extra_vars[@]}"
done
```

对三个主 inventory：

```bash
for inventory in \
  inventory/hosts.yml \
  inventory/hosts-ha-reference.yml \
  inventory/hosts-with-dedicated-routers.yml
do
  ./.venv/bin/ansible-playbook -i "$inventory" playbooks/site.yml --syntax-check
  ./.venv/bin/ansible-inventory -i "$inventory" --list \
    | ./.venv/bin/python -m json.tool >/dev/null
done
```

确认组合门语法与引用顺序：

```bash
./.venv/bin/ansible-playbook \
  -i inventory/hosts-with-dedicated-routers.yml \
  playbooks/validate-ha.yml --syntax-check
```

- [ ] 所有命令在本次 release commit 上直接通过
- [ ] PowerShell parser 在本机直接通过；或已明确记录本机无 `pwsh`、未直接执行，
  并将在 PR 的两个 Python matrix job 中核对 parser step
- [ ] 失败后重跑才通过的 flake 已单独记录，没有表述成首次直接通过

## 3. PR 与 required checks

- [ ] 发布分支基于最新 `origin/main`
- [ ] PR 描述包含 Summary、Validation、Risk / rollout、真实环境验证状态
- [ ] 所有 review thread 已解决
- [ ] PR 合并前 head SHA 已记录：

```bash
PR_HEAD_SHA="$(gh pr view --json headRefOid --jq .headRefOid)"
printf '%s\n' "$PR_HEAD_SHA"
```

- [ ] PR 的以下 checks 全部在该 `PR_HEAD_SHA` 上成功：
  - `ansible-ci / Python 3.12`，包括 `PowerShell syntax check`
  - `ansible-ci / Python 3.13`，包括 `PowerShell syntax check`
  - `docs-quality / Markdown and YAML lint`
  - `codeql / Analyze GitHub Actions`
- [ ] 没有 required check 被跳过、管理员绕过或用旧 SHA 的结果代替

如仓库分支保护尚未把上述检查设为 required，也必须按本清单人工执行同等门槛。

## 4. 合并后 exact main SHA

合并后重新读取远端，不使用历史缓存：

```bash
git fetch --prune origin
git switch main
git pull --ff-only origin main
MAIN_SHA="$(git rev-parse HEAD)"
REMOTE_MAIN_SHA="$(git rev-parse origin/main)"
test "$MAIN_SHA" = "$REMOTE_MAIN_SHA"
printf '%s\n' "$MAIN_SHA"
```

- [ ] `MAIN_SHA` 与 `origin/main` 完全相同
- [ ] 工作区干净
- [ ] main 上由该 SHA 触发的 `ansible-ci`、`docs-quality`、`codeql` 全部成功
- [ ] 文档变更触发时，`pages / build` 与 `pages / deploy` 成功
- [ ] post-merge 安全告警已检查，没有把 CI 绿色误写成运行时证明

发布记录必须保存完整 40 位 `MAIN_SHA`。

## 5. Tag

版本示例：

```bash
VERSION=v0.3.0
```

创建 tag 前确认它不存在，且目标就是 exact main SHA：

```bash
git fetch --tags origin
test -z "$(git tag --list "$VERSION")"
test "$(git rev-parse HEAD)" = "$MAIN_SHA"
git tag -a "$VERSION" "$MAIN_SHA" -m "$VERSION"
test "$(git rev-list -n 1 "$VERSION")" = "$MAIN_SHA"
git push origin "refs/tags/$VERSION"
test "$(git ls-remote origin "refs/tags/$VERSION^{}" | awk '{print $1}')" = "$MAIN_SHA"
```

- [ ] Tag 为 annotated tag；如项目配置签名，还应验证签名
- [ ] 远端 peeled tag SHA 与 `MAIN_SHA` 完全相同
- [ ] 不移动、覆盖或复用已发布 tag

## 6. Release assets 与 SHA-256

在临时目录从 tag 生成确定来源的压缩包：

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
RELEASE_DIR="$(mktemp -d)"
ARCHIVE_NAME="auto-install-mysql-innodb-cluster-${VERSION}.tar.gz"
ARCHIVE_PATH="${RELEASE_DIR}/${ARCHIVE_NAME}"
git -C "$REPO_ROOT" archive \
  --format=tar.gz \
  --prefix="auto-install-mysql-innodb-cluster-${VERSION}/" \
  --output="$ARCHIVE_PATH" "$VERSION"
(
  cd "$RELEASE_DIR"
  shasum -a 256 "$ARCHIVE_NAME" >SHA256SUMS
)
```

- [ ] `SHA256SUMS` 中是 64 位 SHA-256 和准确文件名
- [ ] Release notes 来自 `docs/maintainers/RELEASE_NOTES_DRAFT.md`
- [ ] Release 不是 draft / prerelease（除非发布策略明确要求）
- [ ] 上传 `$ARCHIVE_NAME` 和 `SHA256SUMS`

```bash
gh release create "$VERSION" \
  "$ARCHIVE_PATH" "$RELEASE_DIR/SHA256SUMS" \
  --verify-tag \
  --title "$VERSION" \
  --notes-file "$REPO_ROOT/docs/maintainers/RELEASE_NOTES_DRAFT.md"
```

## 7. 下载复验

不要只验证本地上传前的文件。清空另一个临时目录，从 GitHub Release 重新下载：

```bash
DOWNLOAD_DIR="$(mktemp -d)"
gh release download "$VERSION" --dir "$DOWNLOAD_DIR"
(
  cd "$DOWNLOAD_DIR"
  shasum -a 256 --check SHA256SUMS
  tar -tzf "$ARCHIVE_NAME" >/dev/null
)
```

- [ ] 下载后的 SHA-256 校验通过
- [ ] 压缩包可列出且顶层目录名正确
- [ ] `gh release view "$VERSION"` 显示目标 tag、非 draft、非 prerelease
- [ ] GitHub API 的 tag commit 最终仍等于 `MAIN_SHA`
- [ ] Release 在 Latest 位置

## 8. 真实环境证据边界

只有实际执行并留存 exact tag、环境、时间、命令和脱敏输出时，才勾选：

- [ ] staging 首次部署与重复收敛
- [ ] Cluster primary 故障与切换
- [ ] Router 单节点故障
- [ ] HAProxy 故障、Keepalived `FAULT` 与 VIP 漂移
- [ ] MySQL / Router / HAProxy 扩缩容
- [ ] MySQL Shell 逻辑备份和隔离恢复
- [ ] Percona XtraBackup 和隔离恢复
- [ ] 业务连接、性能和容量

未执行时，Release notes 必须保留：

> 静态验证、测试、Ansible syntax 和 inventory 解析已完成；真实 staging 部署、
> 故障切换、扩缩容、备份恢复及性能验收仍待执行。
