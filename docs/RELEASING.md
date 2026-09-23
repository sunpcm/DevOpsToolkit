# 发布流程

本文是发布操作手册。发布产物的安全模型（SHA256 + Sigstore 双重校验、GitHub 加固）见
[发布供应链安全](SUPPLY_CHAIN_SECURITY.md)。

## 一条铁律

**绝不要在 GitHub 网页上手动创建 Release。** `release.yml` 工作流由推送 `v*` tag 触发，
它会**自己创建 Release 并上传资产**（`devops-toolkit.tar.gz` 及其 `.sha256`、`.sigstore.json`）。

如果你先手动建了同名 Release，工作流最后一步 `gh release create` 会因
`a release with the same tag name already exists` 失败——**前面的构建和签名都成功，但资产不会上传**，
于是 Release 是空的，`install.sh` 下载不到产物，装不了。

## 发布前检查

```bash
git fetch origin
git switch main && git pull --ff-only
./tests/verify-ansible.sh          # release.yml 的门禁就是它
git status --short                 # 应为空
```

`release.yml` 会在同一 tag SHA 上调用完整 `env-check.yml`，quality 与 Ansible/Python 矩阵任一失败都会
阻止发布；另一个 push 事件触发的 Validate 运行不能替代这条同 SHA 门禁。

推 tag 前还必须为将要发布的精确 commit 取得 8 天内的真实 VM 报告。合并候选提交后，在带
`self-hosted,multipass` 标签的专用可信 runner 上手工触发（或等待同 SHA 的每周任务）：

```bash
RELEASE_SHA="$(git rev-parse origin/main)"
gh workflow run vm-smoke.yml --ref main
gh run watch "$(gh run list --workflow='VM smoke' --commit "${RELEASE_SHA}" \
  --limit 1 --json databaseId --jq '.[0].databaseId')"
```

必须确认报告为 `result=passed`、`source_sha=${RELEASE_SHA}`、`source_dirty=false`、
`test_faults=1` 和 `cleanup_status=passed`。没有安全可用的 Multipass runner 时不得用容器或 syntax
check 代替；先在隔离主机手工运行 `tests/multipass-smoke.sh ... --report` 审核环境，再接入专用 runner。
远端 Release gate 没有同 SHA artifact 时仍会 fail closed。

## 发布步骤

完成上述同 SHA VM gate 后，只做两件事：打 tag、推 tag。

```bash
# 版本号遵循 vMAJOR.MINOR.PATCH；v0.1.8 仅是当前示例，使用前确认未被占用。
VERSION=v0.1.8
git fetch --tags origin || exit 1
if git show-ref --verify --quiet "refs/tags/${VERSION}"; then
  echo "版本号已经使用：${VERSION}" >&2
  exit 1
fi
git tag -a "${VERSION}" origin/main -m "DevOpsToolkit ${VERSION}"
git push origin "${VERSION}"
```

推荐用签名 tag（需先配置 GPG/SSH signing key）：

```bash
git tag -s "${VERSION}" origin/main -m "DevOpsToolkit ${VERSION}"
```

推送后工作流会：先验证同 SHA 的近期 VM smoke artifact → 下载并按 lock SHA256 验证固定 collection 归档 → 从归档安装并运行 `verify-ansible.sh` →
将原始归档和已验证 collections 传给全新 release runner → 构建固定名产物 → Cosign 用 GitHub OIDC 签名 → 自校验 Sigstore 身份与打包版本 →
创建 Release 并上传三个资产。release runner 本身不会从 PyPI 或 Ansible Galaxy 安装依赖。

## 发布后验证

```bash
gh run watch $(gh run list --workflow=Release --limit 1 --json databaseId -q '.[0].databaseId')
gh release view "${VERSION}" --json assets -q '.assets[].name'
```

必须看到三个资产：

```
devops-toolkit.tar.gz
devops-toolkit.tar.gz.sha256
devops-toolkit.tar.gz.sigstore.json
```

确认签名 tarball 内包含精确的 collection 标记：

```bash
TMP_DIR="$(mktemp -d)"
gh release download "${VERSION}" --pattern devops-toolkit.tar.gz --dir "${TMP_DIR}"
tar -xOf "${TMP_DIR}/devops-toolkit.tar.gz" \
  devops-toolkit/collections/.bundled-collections
rm -rf "${TMP_DIR}"
```

应只输出：

```text
lock-sha256=<ansible/collections.lock.json 的 64 位 SHA256>
ansible.posix=2.2.2
community.general=13.4.0
community.library_inventory_filtering_v1=1.1.5
```

再模拟安装器的 latest 下载确认可达：

```bash
curl -fsSL -o /dev/null -w "%{http_code}\n" \
  https://github.com/sunpcm/DevOpsToolkit/releases/latest/download/devops-toolkit.tar.gz
```

## 失败后的恢复

若 Release 工作流失败或产物缺失（例如误建过同名 Release），先保留失败的 tag、Release、
Actions 日志和资产现场，确认失败原因。不要删除或重指向已推送的 tag，也不要尝试覆盖已有
Release；启用 immutable releases 后，这些操作本应被拒绝。修复代码、重新通过同 SHA 的
质量与 VM 门禁，再使用尚未占用的新 patch 版本。以下 `v0.1.9` 仅为示例：

```bash
# 在新版本代码已合并到 main，且完成全部发布门禁后执行。
VERSION=v0.1.9
git fetch --tags origin || exit 1
if git show-ref --verify --quiet "refs/tags/${VERSION}"; then
  echo "版本号已经使用：${VERSION}" >&2
  exit 1
fi
git tag -a "${VERSION}" origin/main -m "DevOpsToolkit ${VERSION}"
git push origin "${VERSION}"
```

## 安装（发布成功后）

服务器初始化「建用户 + 配置系统」**必须以 root 运行**（普通用户是 `--user` 模式，不会建用户也不提权）：

```bash
sudo /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/sunpcm/DevOpsToolkit/main/install.sh)"
# 固定版本：追加 -- --version <已审查的 tag>
```

安装器会同时校验 SHA256 与 Sigstore 身份，任一失败都不会降级安装。
