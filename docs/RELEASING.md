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

先完成独立 PR 复核并合并到 `main`。开发分支的 push 检查验证精确提交，PR 检查验证与
`main` 的模拟合并结果；两者都不能代替合并后提交的检查，更不能代替 tag SHA 的
Release workflow 门禁。当前 `main` 规则要求 quality 与 Python 3.12/3.14 三项检查。

```bash
git fetch origin
git switch main && git pull --ff-only
./tests/verify-ansible.sh          # release.yml 的门禁就是它
git status --short                 # 应为空
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" || exit 1
```

`release.yml` 会在同一 tag SHA 上调用完整 `env-check.yml`，quality 与 Ansible/Python 矩阵任一失败都会
阻止发布；另一个 push 事件触发的 Validate 运行不能替代这条同 SHA 门禁。

推 tag 前还必须在隔离测试主机上，为将要发布的精确 commit 手工运行一次性 VM 验收。
该主机须事先具备 Multipass、SSH、Python 3.12–3.14、ansible-core 2.21.4 和已锁定的
collections；新增安装需事先获得机主同意。切到干净的候选提交后执行：

```bash
RELEASE_SHA="$(git rev-parse HEAD)"
test -z "$(git status --porcelain)" || exit 1
test "${RELEASE_SHA}" = "$(git rev-parse origin/main)" || exit 1
REPORT_FILE="$(mktemp "${TMPDIR:-/tmp}/devops-toolkit-vm-report.XXXXXX")"
./tests/multipass-smoke.sh run --with-faults --report "${REPORT_FILE}"
python3 scripts/verify-vm-evidence.py verify-report \
  --report "${REPORT_FILE}" --sha "${RELEASE_SHA}"
shasum -a 256 "${REPORT_FILE}"
```

保留原始报告及其 SHA256 到受控发布记录，不要提交含敏感信息的运行日志。检查报告中的
`result=passed`、`source_sha=${RELEASE_SHA}`、`source_dirty=false`、`test_faults=1`、
`cleanup_status=passed`，并确认清理后不存在遗留测试实例。报告必须在 8 天内；如果候选提交
改变、报告过期、环境不同或失败，重新跑验收。没有安全可用的一次性 VM 时停止发布，不能用容器
或 syntax check 代替。
工作流保存的已验证 collections 中间产物也保留 8 天，以覆盖人工审批窗口；审批前仍须分别核对
VM 报告和中间产物未过期，不能因其中一项尚在有效期内就忽略另一项。

## 发布步骤

完成上述同 SHA VM 验收后，打 tag、推 tag，并在 GitHub 的 `release` Environment 待审批阶段
再次核对报告原件、报告 SHA256、来源 SHA 与 tag SHA。只有证据一致且同 SHA CI 通过，审批人
才批准；不能为了解除等待而直接批准。当前环境限制为 `v*` tag、要求 `sunpcm` 审批且
禁止管理员强制绕过。单维护者自审只是人工暂停点，不是独立第二人复核；GitHub 无法自动
证明本地 VM 报告的真实性。

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

推送后工作流会：下载并按 lock SHA256 验证固定 collection 归档 → 从归档安装并运行 `verify-ansible.sh` →
将原始归档和已验证 collections 传给全新 release runner → 等待受保护 Environment 的人工审批 →
构建固定名产物 → Cosign 用 GitHub OIDC 签名 → 自校验 Sigstore 身份与打包版本 →
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
