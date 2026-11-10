# 发布供应链安全

DevOpsToolkit 的 Release 使用两层校验：

1. SHA256 检查下载是否完整，并阻止同版本内容静默变化。
2. Sigstore/Cosign 验证产物确实由本仓库的 Release workflow 在对应 tag 上通过 GitHub OIDC 签名。

截至 2026-11-11，最新正式 Release 为 `v0.1.10`，来源提交是
`571a5fef119055470d33ff478c0f69ba0524b1c5`；`main` 为
`1c316b84816a87e6b7b6a8dd3ecac58d30943697`，含 Release 之后的提交。
`v0.1.10` 安装器及本手册的固定示例都绑定正式 Release，不能替换成更新的 `main` 后继续沿用旧摘要。

### 当前依赖安全状态

2026-11-11 的独立审计确认，`v0.1.10` 中仍固化的 uv `0.9.18` 命中已知漏洞，
其中包含官方 critical advisory；旧 NVM 固定 commit 也命中 CNA/CVE 记录。因此
`v0.1.10` 是带已知依赖风险的历史签名资产，不能继续被无条件描述为当前生产安全基线。

当前候选源码的中央 pin 已落地为 uv `0.13.7`、NVM `v0.41.0`
（commit `4e8758a801eea9479b32a904f31093e410ddaba4`）、Node `24.22.2` 和 Go `1.27.3`。
2026-11-11 已在一次性 Ubuntu 22.04/24.04 ARM64 VM 上完成限定的 user-only 组件升级验收：
旧 uv/NVM/Node/Go 升级后，第二次运行满足 `changed=0`、`unreachable=0`、`failed=0`；
严格主机指纹 SSH 后的新 Bash/Zsh 登录版本正确，旧 goenv v2 + Go `1.26.7`、插件及
自定义 Go 策略 hash 未变，旧 Node `24.11.1` 和托管 Go `1.27.1` 仍可运行，NVM 用户文件保留。
该结果只覆盖双 Ubuntu ARM64 user-only 组件升级，不替代精确候选 SHA 的完整 VM smoke、
x86_64/WSL2、Release 打包与实际安装验收。源码修复尚未发布；发布 `v0.1.10` 之后的主线更新
不会追溯修复已有签名资产。

Release 包含三个固定名称资产：

- `devops-toolkit.tar.gz`
- `devops-toolkit.tar.gz.sha256`
- `devops-toolkit.tar.gz.sigstore.json`

## 自动签名链路

`.github/workflows/release.yml` 只在 `v*` tag 上运行，并获得最小的 `contents: write` 与 `id-token: write` 权限。流程会：

1. Release workflow 在同一 tag SHA 上调用完整 Validate workflow，包含质量检查与 Ansible/Python 矩阵；
   并确认 tag commit 是当前 `origin/main` 的祖先。不能把另一个并行的 push 检查当作发布门禁。
2. 在无发布权限的 job 中下载固定版本 Ansible collection 原始归档，按
   `ansible/collections.lock.json` 校验文件名、SHA256 和内部 manifest，再从这些已校验归档安装依赖；
   原始归档和安装目录一起保存为保留 8 天的 workflow artifact。
3. 验证通过后，等待受保护 `release` Environment 人工审批；审批人核对当次一次性 VM 报告
   原件、SHA256、来源 SHA 与同 SHA CI。通过后在全新 runner 上重新 checkout 同一 tag，
   只恢复上一步验证过的 collections；有发布权限的构建 job 不运行 PyPI 或 Ansible Galaxy 安装。
4. 构建脚本再次核对原始归档 SHA256、`requirements.yml`、安装后 manifest、精确版本和完整集合，
   再把 lock、collections 与绑定 lock 摘要的 marker 写入最终 tarball；签名覆盖整个产物。
5. 下载固定版本 Cosign，使用仓库内固定的 SHA256 校验二进制。
6. 通过 GitHub Actions OIDC 获取短期身份，不使用长期签名私钥或 GitHub Secret。
7. 将证书、签名和透明日志证明写入 Sigstore bundle。
8. 在上传 Release 前立即验证签名身份，并在 Release notes 前缀记录精确 source commit SHA。

安装器也会下载固定版本 Cosign，并用内置的平台 SHA256 校验。验证条件不是“存在一个合法签名”即可，而是同时要求：

- OIDC issuer 为 `https://token.actions.githubusercontent.com`。
- 仓库为 `sunpcm/DevOpsToolkit`。
- workflow 为 `.github/workflows/release.yml`。
- workflow ref 与包内版本对应的 `refs/tags/v*` 完全一致。
- 触发事件为 `push`。

任何条件不匹配都会在发布版本目录和切换 `current` 之前失败。

安装器仅对已发布的旧版本 `v0.1.2`、`v0.1.3`、`v0.1.4`、`v0.1.5`、`v0.1.7`
允许缺少内置 collection 标记时使用 Galaxy 兼容路径。其他版本缺标记一律拒绝，
已有版本的标记与 manifest 在复用前也会重验；新 Release 不会静默回退到网络安装。

## GitHub 控制面：当前状态与复核清单

截至 2026-09-24，仓库控制面已启用并由 API 回查：`main` 禁止删除/force push，
要求来源为 GitHub Actions 的 `quality`、Python 3.12/3.14 三项检查；`v*` tag 禁止
更新/删除；`release` Environment 只允许 `v*` tag，要求 `sunpcm` 审批且不允许管理员
强制绕过；immutable releases、仅 GitHub 官方 Action、完整 SHA pin、Dependabot alerts
和 security updates 均已启用。这些保护已支撑 `v0.1.9`、`v0.1.10` 的正向发布与审批；
标签更新/删除、资产替换和审批绕过的破坏性负例仍未在隔离目标执行，因此不能宣称
所有拒绝路径已经验收。草稿 PR #2 的检查成功也不能替代每次新 tag、Environment 审批和
不可变资产的当次验收。详细 API 证据见
[2026-09-24 发布门禁记录](../archive/progress/2026-09-24-release-gate-manual-vm.md)。

以下是维护或重新配置时的清单；账号 2FA/恢复代码不在仓库 API 验证范围内，必须由账户持有人确认。

### 1. 保护 GitHub 账号

- 开启双因素认证，优先使用 Passkey 或硬件安全密钥。
- 下载并离线保存恢复代码。
- 删除不再使用的 Personal Access Token、SSH key、OAuth App 和 GitHub App 授权。
- 日常操作优先使用细粒度、短有效期 Token，避免 classic PAT。

### 2. 复核 `release` Environment

进入仓库：

`Settings` → `Environments` → `release`（新仓库才需创建同名环境）

必须设置：

- Required reviewers：至少一名可信维护者；审批前执行[发布流程](RELEASING.md)中的一次性 VM 验收。
- Prevent self-review：有第二名维护者时开启；单人仓库开启后会无法自行发布。
- 禁止管理员强制绕过保护规则（`can_admins_bypass=false`）。
- Deployment branches and tags：只允许 `v*` tag；tag 的更新/删除另由 tag ruleset 禁止。

Release workflow 已引用该 Environment。Environment 不需要配置 Cosign 私钥或 Secret。

必须在推送新 `v*` tag 前完成这一步；仅创建同名空 Environment 不构成保护。单维护者
自审是可执行的人工暂停点，不提供独立第二人复核；有第二名维护者时开启防自审。

### 3. 复核 `main`

当前规则集 `23913370` 已覆盖 `main`：禁止删除和 force push，并要求上述三项
GitHub Actions 检查，采用 strict latest-code policy，且无 bypass。待草稿 PR 经独立复核、
完成真实合并后，继续核对最终合并提交的检查。当前**未**要求 PR approval；单维护者
无法满足第二人复核，不能把现有规则写成已经强制了审批。

有第二名可信维护者后，可在 `Settings` → `Rules` → `Rulesets` 评估增加：

- Require a pull request before merging。
- 至少 1 个 approval，并开启 Dismiss stale approvals。
- 保持 required status checks 覆盖 quality 与两个 Ansible/Python 矩阵任务。
- Require conversation resolution。
- 建议 Require signed commits 与 linear history。
- 不允许常规维护者绕过规则；如确需紧急恢复路径，单独审查其权限。

单维护者阶段保留当前必需检查和禁止重写规则，不把尚未实施的第二人审批写成已完成。

### 4. 保护 Release tags

当前 tag ruleset `23913374` 以 `v*` 为目标，禁止更新/删除，且无 bypass。
新 tag 的创建尚未另设 ruleset 限制；当前仓库只有一名管理员具备写权限。若增加维护者，
须重新设计 tag 创建权限，不能误以为目前已经按发布角色隔离。维护时检查：

- 新 tag 只能由被授权的发布者创建；新增写入者前复核权限。
- 禁止更新和删除已经推送的 tag。
- 保持仓库级 immutable releases 启用；它只保护启用后新发布的 Release，历史版本不能追溯变更。

发布后不要复用版本号。`v0.1.2`–`v0.1.10` 均已占用，`v0.1.8` 的 Release 即使取消，
对应标签也不能复用；需要修复时必须创建经过授权且当前未占用的新版本号。

### 5. 收紧 Actions

当前设置只允许 GitHub 官方 Action（非官方 verified 与自定义 pattern 均关闭），并强制完整
commit SHA pin；Dependabot alerts/security updates 已启用。进入 `Settings` → `Actions` →
`General` 定期复核：

- Workflow permissions 默认设为 Read repository contents。
- 不需要时关闭 Allow GitHub Actions to create and approve pull requests。
- 只允许 GitHub 官方 Action；确需第三方 Action 时先独立审核，再增加显式允许项。
- 开启“Require actions to be pinned to a full-length commit SHA”。
- 保持 Dependabot alerts 与 security updates 开启；固定版本与 checksum 的更新仍须经 PR 复核。

本项目引用的 GitHub Actions（包括 collections 在 job 间传递使用的 artifact actions）已固定到完整
commit SHA，避免上游移动 tag 后改变执行代码。

## 依赖锁与可复现边界

`ansible/collections.lock.json` 是 collection 名称、版本、原始 tarball 文件名与 SHA256 的单一来源。
`scripts/verify-collection-lock.py` 强制校验 `requirements.yml`、下载归档、安装目录和 Release marker；
任一归档、checksum、manifest、marker 或 lock 被修改，Release 构建或安装都会 fail closed。

这不代表整台机器可以 bit-for-bit 重建：

- Ansible Core、collections、Cosign、uv 和若干 Git source 固定到版本、checksum 或 commit。
- Ubuntu apt 包及其传递依赖跟随所配置仓库在执行时的候选版本，是滚动输入。
- Docker CE 来自 Docker 官方 apt 仓库，当前角色没有固定完整 `.deb` 集合及仓库快照。
- Linuxbrew bootstrap 固定 Git commit，但 `brew install` 的 formula、bottle 和依赖解析仍跟随 Homebrew 仓库。

因此“Git source 固定”只保证对应源码 checkout 不漂移，不能外推为整个系统完全可复现。需要长期保存的环境
应额外使用 apt 仓库快照、固定 `.deb`/bottle 归档及其校验值，或制作经过签名的基础镜像。

## 月度只读依赖审计

`.github/workflows/dependency-audit.yml` 每月一日及手工触发时运行
`scripts/dependency-audit.py`，输出 Ansible、collections、Cosign、uv、NVM、goenv、Go、Node LTS 与
GitHub Actions 的当前固定值、checksum 和官方复核入口。工作流只有 `contents: read`，只上传报告 artifact，
不会创建 PR、修改依赖或自动合并。手工完整检查使用：

```bash
python3 scripts/dependency-audit.py --check-security \
  --output dependency-audit.md
```

默认模式离线检查固定值一致性；`--check-security` 额外通过 OSV API 查询精确 PyPI pin、
Go 标准库、Node GIT tag、Cosign 源码 Go module，以及 NVM、goenv、Oh My Zsh、Linuxbrew
和 Zsh 插件等精确 commit。当前查询**不覆盖** Ansible collections、uv/goenv/Cosign
预编译二进制、actionlint/gitleaks 的模块坐标、apt/Homebrew、二进制 SBOM 或未登记的传递依赖。
actionlint `1.7.7` 与 gitleaks `8.24.3` 已在 `requirements-dev.txt` 精确固定，但这不等于
已完成其模块漏洞查询。

2026-11-11 对当前声明覆盖范围的完整查询已完成并以状态 0 退出，当前 OSV 无匹配；该结果
只适用于上述覆盖范围。任一网络、HTTP、JSON、响应格式或分页查询失败都会标记为“未完成”，
发现有效漏洞、固定值一致性错误或任一未完成查询都会使脚本非零退出。报告仍会保留，工作流
也会上传报告后显式失败；单次零匹配、查询覆盖有限或查询失败都不能外推为“无漏洞”、完整
Release 安全认证或整机供应链认证。

维护者查看报告后必须在官方来源核对支持周期与变更日志；更新通过独立 PR，重新复核归档 checksum，
并通过静态门禁、篡改负向测试和一次性 VM smoke 后才能合并。高风险依赖禁止自动合并。

## 手工验证 Release

以下流程需要 GitHub CLI 和 Cosign。先确认命令可用；Cosign 应从 [Sigstore 官方 Release](https://github.com/sigstore/cosign/releases)安装并核对官方 checksum：

```bash
gh --version
cosign version
```

下载同一版本的三个资产：

```bash
VERSION=v0.1.10
gh release download "${VERSION}" \
  --repo sunpcm/DevOpsToolkit \
  --pattern 'devops-toolkit.tar.gz*' \
  --dir "/tmp/devops-toolkit-${VERSION}"
cd "/tmp/devops-toolkit-${VERSION}"
```

先检查 SHA256：

```bash
sha256sum --check devops-toolkit.tar.gz.sha256
```

macOS 使用：

```bash
shasum -a 256 --check devops-toolkit.tar.gz.sha256
```

再验证精确的 GitHub Actions 身份：

```bash
cosign verify-blob \
  --bundle devops-toolkit.tar.gz.sigstore.json \
  --certificate-identity \
    "https://github.com/sunpcm/DevOpsToolkit/.github/workflows/release.yml@refs/tags/${VERSION}" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-github-workflow-repository sunpcm/DevOpsToolkit \
  --certificate-github-workflow-ref "refs/tags/${VERSION}" \
  --certificate-github-workflow-trigger push \
  devops-toolkit.tar.gz
```

只有两项验证都通过时才应手工解包或安装。

## 发布前检查

推送 tag 前执行：

```bash
./tests/verify-ansible.sh
git status --short
git log -1 --show-signature
```

确认工作区为空、测试通过，并核对 tag 指向：

```bash
VERSION=v0.1.11  # 截至 2026-11-11 核对未占用；实际发布须另行授权并实时查重
git fetch --tags origin || exit 1
RELEASE_SHA="$(git rev-parse HEAD)"
test -z "$(git status --porcelain)" || exit 1
test "${RELEASE_SHA}" = "$(git rev-parse origin/main)" || exit 1
if git show-ref --verify --quiet "refs/tags/${VERSION}"; then
  echo "版本号已经使用：${VERSION}" >&2
  exit 1
fi
git tag -s "${VERSION}" "${RELEASE_SHA}" -m "DevOpsToolkit ${VERSION}"
git show --show-signature "${VERSION}"
git push origin "${VERSION}"
```

`git tag -s` 需要提前配置 GPG 或 SSH signing key。不要在签名验证失败时改用未签名 tag 绕过规则。
打标签和推送前必须取得明确授权；`v0.1.2`–`v0.1.10` 均不可复用。

## 仍然存在的边界

- Sigstore 证明“哪个 workflow 在哪个 tag 上构建了文件”，不证明源码没有恶意逻辑。
- 如果攻击者同时取得 `main`、tag、Environment 审批和 Actions 配置权限，仍可能发布带合法签名的恶意新版本。
- 安装器本身来自可变的 `main`。高安全环境应先固定并审查安装器提交：

```bash
INSTALLER_COMMIT="571a5fef119055470d33ff478c0f69ba0524b1c5"  # v0.1.10 来源提交
curl -fsSLo /tmp/devops-toolkit-install.sh \
  "https://raw.githubusercontent.com/sunpcm/DevOpsToolkit/${INSTALLER_COMMIT}/install.sh"
printf '%s  %s\n' \
  '4cc4af56e1a6e828e5386f35488b7e89065b5182a0772951face51cea356101a' \
  /tmp/devops-toolkit-install.sh | sha256sum --check --strict
less /tmp/devops-toolkit-install.sh
/bin/bash /tmp/devops-toolkit-install.sh --version v0.1.10
```

- 上例 SHA256 来自 `v0.1.10` 来源提交的 `install.sh`，仅适用于该提交；切换版本或提交必须独立复核。
- Cosign 信任根和透明日志验证需要网络。网络受限时安装器会安全失败，不会降级为只检查 SHA256。
