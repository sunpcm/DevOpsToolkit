# DevOpsToolkit TODO

> 更新日期：2026-09-26
>
> 原则：这里只保留尚未完成、能够独立验收的工作。完成项及历史证据移入
> [`archive/progress/`](archive/progress/)，不要让历史记录掩盖当前优先级。

## 当前基线与边界

- 2026-09-22 review 从干净的 `main@74ef67b` 开始；这是历史审计基线，不是当前开发分支。
- 2026-09-24 独立 Review 对 PR #2 的权限、验签前解包和系统 Python 路径提出的问题
  已在后续提交修复；PR #2 已合并，合并提交为 `9d613e8`。这不构成草稿 PR #4
  新 goenv 修复的 Review 或发布许可。
- 最新正式 GitHub Release 仍为 `v0.1.7`；`v0.1.8` 标签已推送，但对应发布流程因 Go 验收失败而取消，尚无该版本的正式签名 Release。
- 唯一受支持的环境配置实现仍是 `ansible/`，受支持入口是 `bin/` 与 `install.sh`。
- `AcmeConfig/` 不属于主线 Release，但根 README 仍向用户公开它；在完成下列 P0 安全整改前，不应宣称其为生产级。
- 2026-09-23 控制面缺口是历史快照。2026-09-24 重新认证并回查后，`main`/`v*`
  ruleset、`release` 审批、immutable releases、Actions SHA pin 与 Dependabot 已启用；
  已有一次 `v0.1.8` 真实 tag 尝试，但 Release 被取消；每次发布的同 SHA 一次性 VM 验收与正式 Release 尚未完成。
- 静态验证通过不等于真实 VM、升级回滚、SSH 登录切换或 ACME 证书续期已经完成验收。
- 2026-09-24 起暂缓 `AcmeConfig/` 的真实 CA/DNS 与独立仓库工作：它不在主线 Release 包中，
  其真实 CA 门槛不阻塞主线开发与发布，已有静态检查仍保留；但在自身真实环境验收完成前
  不得用于生产或宣称生产就绪。

## 当前执行顺序

1. P0-2/P0-3：PR #4 的 goenv 修复已重新独立 Review 且 CI 全绿，已授权合并至 `main@de58ca2`；
   确认最终 `main` 提交的必需检查，再另用新版本执行同 SHA 一次性 VM 验收、
   受保护审批、正式签名 Release 与安装/回滚验收。
   `v0.1.8` 旧标签不可复用；未经新的发布授权不打 tag。
2. P1/P2：并行推进不依赖正式 Release 的可靠性回归与文档工作。
3. 暂缓范围：P0-1 ACME 真实签发与续期、P2 ACME 独立仓库迁移；不以静态或自签证据替代其上线门槛。

## P0：安全与发布阻塞项

### P0-1：`AcmeConfig/`（暂缓，不是主线 Release 阻塞项）

已完成的本地实现、静态检查与 Ubuntu 24.04 一次性 VM 证据见
[`archive/progress/2026-09-22-acme-p0-1-vm.md`](archive/progress/2026-09-22-acme-p0-1-vm.md)。
整组证书原子发布、故障恢复及多消费者复测见
[`archive/progress/2026-09-22-acme-p0-1-bundle.md`](archive/progress/2026-09-22-acme-p0-1-bundle.md)。
DNS Token 的 argv 与失败输出泄漏修复、本地回归及 Ubuntu 22.04 `runuser` 语义检查见
[`archive/progress/2026-09-23-acme-p0-1-secret-argv.md`](archive/progress/2026-09-23-acme-p0-1-secret-argv.md)。
交互式 acme.sh 子进程固定 `umask 0077` 的本地补强与剩余日志门槛见
[`archive/progress/2026-09-23-acme-p0-1-log-umask.md`](archive/progress/2026-09-23-acme-p0-1-log-umask.md)。
当前/轮替日志健康检查、logrotate 身份修复、一次性 VM 实测及剩余门槛见
[`archive/progress/2026-09-24-acme-p0-1-log-mode-vm.md`](archive/progress/2026-09-24-acme-p0-1-log-mode-vm.md)。
这不是生产验收：既有部署 VM 仅使用自签证书模拟部署，本轮只证明离线客户端日志与
轮替权限；均未通过真实 CA 签发。以下条目保留为 ACME 独立上线前的硬门槛，
按当前执行顺序暂不继续投入。

- [ ] 以受控测试域名完成真正的 ACME 首次签发、DNS/webroot 挑战和模拟续期；验证 hook
      仅在证书真实更新后 reload 对应活动服务，且支持多个消费者。
- [ ] 确认真实 DNS provider 响应、acme.sh 持久化状态与日志不会泄露 Token、账户信息或私钥；
      检查轮替后日志仍只有最小读取权限。
- [ ] 扩展真实环境回归：Ubuntu 22.04 的真实签发/续期，以及从备份恢复到真实消费者；
      自签证书、隔离恢复和静态测试不能替代真实 CA 与真实服务行为。

验收证据：ShellCheck/Bats 或同等级测试全绿；临时 VM 中完成首次签发、模拟续期、权限检查、服务 reload 和安全清理；
报告中记录文件 owner/mode、systemd sandbox 结果及失败路径，不记录任何真实凭据。

### P0-2：落实 GitHub 发布控制面

2026-09-23 的只读远端复核及单维护者激活顺序见
[`archive/progress/2026-09-23-github-p0-2-readonly-audit.md`](archive/progress/2026-09-23-github-p0-2-readonly-audit.md)。
首次审计时，规则集、release 环境、immutable releases、Actions 限制及 Dependabot 均未启用；
本地 workflow 代码不等于远端设置生效。
2026-09-24 用户重新认证后，当前会话在沙箱外只读确认 rulesets 仍为空、`release`
Environment 仍无保护规则。随后完成并回查的控制面设置、一次性 VM 方案与剩余边界见
[`archive/progress/2026-09-24-release-gate-manual-vm.md`](archive/progress/2026-09-24-release-gate-manual-vm.md)。
同一 tag SHA 的完整质量门禁、`origin/main` 祖先校验、Release 来源 SHA 记录已在
`.github/workflows/release.yml` 实现；固定安装器 commit 与 SHA256 的示例见
[`docs/SUPPLY_CHAIN_SECURITY.md`](docs/SUPPLY_CHAIN_SECURITY.md)。PR #2 已合并至 `main@9d613e8`，
最终 push/PR 的 quality、Python 3.12/3.14 检查均通过；该 SHA 的双版本一次性 VM 报告见
[`archive/progress/2026-09-24-release-vm-9d613e8.md`](archive/progress/2026-09-24-release-vm-9d613e8.md)。
这证明合并路径未被必需检查误阻，但新版本 Release 仍须远端实际验收。

- [ ] 首次新 tag 发布时验证 `v*` 更新/删除保护、仅 `v*` 可进入 `release` Environment、
      审批确实阻止发布且管理员不能强制绕过；审批人核对当次同 SHA VM 报告原件与 SHA256。
- [ ] 在新版本的真实 Release 中确认同 SHA 质量门禁、main 祖先检查、Source commit 记录及固定 commit 安装入口按预期生效；本地 workflow 和示例不能代替远端执行。
- [ ] 验证新 Release 资产不可替换、三个固定资产及签名/安装/回滚通过；当前
      immutable、官方 Action allowlist/完整 SHA pin、Dependabot 仅有设置和 PR CI 证据。

验收证据：GitHub API 显示 rulesets、Environment protection、immutable 和 Actions 限制均已生效；创建测试 tag 时只有受保护路径可发布；
新 Release 无法替换 tag 或资产，三个资产及 attestation/签名验证通过。

### P0-3：迁移到受支持的 Ansible 控制端基线

本地实现提交与真实 VM 证据见
[`archive/progress/2026-09-22-ansible-p0-3-runtime.md`](archive/progress/2026-09-22-ansible-p0-3-runtime.md)。
当前分支的锁定产物、完整本地门禁及临时构建复核见
[`archive/progress/2026-09-24-p0-3-current-branch-local-review.md`](archive/progress/2026-09-24-p0-3-current-branch-local-review.md)。
已固定 Python 3.12–3.14 / core 2.21.4、隔离 venv、22.04 目标边界及三项 collections，
并更新 README、安装/交互文档和 CI 定义；PR #2 已合并为 `main@9d613e8`。
安装器对未来版本缺失 collection bundle 的 Galaxy 回退已改为拒绝；仅五个已发布的
旧版本保留精确兼容名单。证据见
[`archive/progress/2026-09-24-bundle-fallback-allowlist.md`](archive/progress/2026-09-24-bundle-fallback-allowlist.md)。

- [ ] 新版本发布前重新验证 2.21.4 runtime 与三项 collections 的 Release 构建、签名、安装及回滚门槛；
      不把本地测试 tarball 视为正式 Release。

验收证据：全新控制端不修改系统 Python，能够离线复用已安装 runtime；支持矩阵全部通过 `verify-ansible.sh` 和真实 VM smoke；
重复安装 runtime 不产生变化，旧 runtime 的迁移/回滚路径有记录。

## P1：运行安全与可靠性

### P1-2：修正用户组件开关和依赖闭环

本地实现提交 `c22645e` 已完成下面各项代码改动；静态门禁与 16 组开关矩阵见
[`archive/progress/2026-09-22-user-profile-p1-2.md`](archive/progress/2026-09-22-user-profile-p1-2.md)。
已拆分基础 Shell/Oh My Zsh，环境 loader 不再依赖 Shell 开关；向导约束、
user-only 依赖重检、缺失共享 brew 的“警告并跳过”语义及对应本地测试均已实现。
干净 Ubuntu HOME 的验收已逐步补齐，以下只保留尚未关闭的门槛。
2026-09-25 对已推送 `v0.1.8` 的源码提交 `9d613e8` 补做双版本 aarch64 VM：Shell/Oh My Zsh、
仅 uv、仅 Node、共享 brew 缺失/存在 fixture 均两次收敛且新登录检查通过；仅 Go 在两版系统
均因上游 goenv v3 不再提供 `bin/goenv` 而失败。草稿 PR #4 pin 的是同一上游提交，不能修复此问题。
`v0.1.8` Release workflow 已取消，标签仍保留在旧 SHA；修复后应使用新 patch 标签。草稿 PR #4
在代码提交 `04c7534` 改用按 SHA256 验证的 goenv 3.1.4 官方二进制包，并把默认 Go 升至
1.27.1；Ubuntu 22.04/24.04 aarch64 的仅 Go 和全组件组合首次成功、二次 `changed=0`，
Bash/Zsh 新登录、错误二进制不执行及真实 goenv v2 checkout 基本共存均已实测。
最终草稿 head `9fe579f` 的六项 CI 全绿，重新独立 Review 已给出 APPROVED；
2026-09-26 已授权合并为 `main@de58ca2`，但这不是正式 Release 验收。amd64 实机、复杂旧配置迁移及 apt 故障注入仍未覆盖。
旧标签失败证据见 [`archive/progress/2026-09-25-user-profile-p1-2-vm.md`](archive/progress/2026-09-25-user-profile-p1-2-vm.md)；
修复后的 VM 报告已随 [PR #4](https://github.com/sunpcm/DevOpsToolkit/pull/4) 合并：
[`archive/progress/2026-09-25-goenv-reviewfix-04c7534.md`](archive/progress/2026-09-25-goenv-reviewfix-04c7534.md)。
Ubuntu 24.04 对“仅请求缺失的共享 brew”、关闭 loader、缺少 zsh 时的 fail-closed
进行了部分真实 HOME 验证；结果与网络边界见
[`archive/progress/2026-09-23-user-profile-p1-2-vm-partial.md`](archive/progress/2026-09-23-user-profile-p1-2-vm-partial.md)。
环境 loader 的 16 组实际 `/bin/sh` 加载测试见
[`archive/progress/2026-09-23-user-profile-p1-2-shell-matrix.md`](archive/progress/2026-09-23-user-profile-p1-2-shell-matrix.md)。
Shell 关闭但语言工具开启、Oh My Zsh 约束及 user-only 依赖例外的向导链路测试见
[`archive/progress/2026-09-23-user-profile-p1-2-wizard-paths.md`](archive/progress/2026-09-23-user-profile-p1-2-wizard-paths.md)。

- [ ] 在 Ubuntu 22.04/24.04 的全新 HOME 覆盖基础 Shell/Oh My Zsh 开关、仅 uv、仅 Node、仅 Go、
      缺失及存在的共享 brew、全部语言工具开启等关键组合；各执行两次，第二次 `changed=0`。
- [ ] 用新登录 Bash/Zsh 验证所选工具可发现、未选 loader 不出现；完成因网络超时尚未证明的
      uv 下载路径及 Node/Go/Oh My Zsh 真实安装验证。
- [ ] 在一次性 VM 注入白名单 apt 返回成功但命令仍缺失的情形，证明依赖重检阻止继续修改 HOME；
      安装测试依赖前须按用户要求取得明确同意。

验收证据：每种受支持组合在干净 HOME 中执行两次，第二次 `changed=0`；新登录 Shell 能找到所选工具，未选工具不会被意外加载或删除。

### P1-4：自动化真实环境回归

本地代码提交 `b41a1e6` 曾增加 PR 阶段编排测试、专用 Multipass runner workflow、机器可读报告、
失败清理与 Release 同 SHA 报告门禁；用户现已选择改为每次发布前手工一次性 VM 验收加受保护
Environment 审批，不再维护每周自托管 runner。早期网络失败与自动清理见
[`archive/progress/2026-09-23-vm-p1-4-first-run.md`](archive/progress/2026-09-23-vm-p1-4-first-run.md)；
从干净提交 `f40192f` 经一次性 VM 代理完成的 22.04/24.04 首次配置、二次 `changed=0`、
SSH/UFW/Docker/Nginx 和故障恢复见
[`archive/progress/2026-09-23-vm-p1-4-proxy-e2e.md`](archive/progress/2026-09-23-vm-p1-4-proxy-e2e.md)。
最新双版本主路径与既有故障注入证据见
[`archive/progress/2026-09-23-ssh-p1-1-final-vm.md`](archive/progress/2026-09-23-ssh-p1-1-final-vm.md)。
SSH finalize 在 UFW 更新失败时的新端口保活与恢复证据见
[`archive/progress/2026-09-23-ssh-p1-1-guard-final.md`](archive/progress/2026-09-23-ssh-p1-1-guard-final.md)。
PR 编排测试、双版本本地 VM smoke、报告及失败清理代码已有本地证据；PR #2
已合并，quality 与双 Python 矩阵也已通过。以下只保留当次 VM 与新 Release 门槛。
2026-09-24 补强了运行时实际 Ubuntu 版本断言及报告中同一次测试的双实例校验；
本地证据见 [`archive/progress/2026-09-24-vm-report-image-proof.md`](archive/progress/2026-09-24-vm-report-image-proof.md)。
它防止单实例/错版本报告被当作双版本证据，但不能替代候选 SHA 的当次真实 VM 验收。

- [ ] 每次发布前在隔离主机针对候选 SHA 运行一次性 Ubuntu 22.04/24.04 VM，覆盖首次收敛、
      二次 `changed=0`、SSH/UFW/Docker/Nginx 与故障恢复；保留 8 天内的报告原件和 SHA256。
- [ ] 核验报告准确记录镜像、来源 SHA、Ansible 版本、结果和清理状态；失败时实例仍清理，
      报告失败或缺失时审批人拒绝 Release。不能用容器 syntax check 或历史报告替代。
- [ ] 在新 Release 实际验证同 SHA CI 通过后进入受保护审批，审批人核对报告原件、摘要、
      tag SHA 与候选 SHA 后才批准；单人自审不是独立复核。

验收证据：每次发布保存可追溯的本地报告和审批记录；实例无论成功或失败都会安全清理，
证据缺失或失败时不得批准发布。GitHub 无法自动证明本地报告真实性，此门槛依赖人工执行。

### P1-5：完成真实升级与回滚闭环

首次 24.04 临时 VM 验证发现真实 `v0.1.4` Release 安装后目录由归档的 UID 1001 持有；
安装器本地修复及其复测过程见
[`archive/progress/2026-09-23-installer-system-ownership.md`](archive/progress/2026-09-23-installer-system-ownership.md)。

从干净提交 `c2132d5` 在一次性 Ubuntu 24.04 VM 完成真实 `v0.1.4 → v0.1.7`、
latest/固定版本、签名校验、重复安装、普通用户入口及原子回滚/前滚；见
[`archive/progress/2026-09-23-upgrade-rollback-p1-5.md`](archive/progress/2026-09-23-upgrade-rollback-p1-5.md)。
下列 macOS 系统安装边界仍未实测，因此 P1-5 不关闭。

- [ ] 记录 macOS `sudo --system` 安装后普通用户解析 launcher 符号链接的真实结果。

验收证据：将命令、环境、版本、关键输出和失败边界写入 `archive/progress/`；不得包含 Token、私钥、密码或用户真实主机信息。

## P2：维护性与文档一致性

- [ ] 在真实 WSL2 Ubuntu 24.04 上验收安装器与 Playbook 的平台预检、首次及重复运行；
      本地 WSL1/非支持平台拒绝矩阵已实现，但模拟内核标记不替代真实 WSL2 启动证据。
- [ ] 在新签名 Release 中验证安装器、向导和 Playbook 的 `--capabilities-json` 协议；本地实现与包测试不能证明远端资产已更新。
- [ ] 暂缓：在 P0-1 真实环境门槛通过后，将 `AcmeConfig/` 迁入受保护的独立仓库与签名 Release，迁移主线 CI/README 引用；不把证书生命周期塞进主线 Ansible role。

`AcmeConfig/` 维护边界已评估，迁移尚未执行，故上项仍开放。决策及验收顺序见
[`docs/ACME_BOUNDARY.md`](docs/ACME_BOUNDARY.md)。

版本示例与历史版本边界的修订证据见
[`archive/progress/2026-09-23-release-doc-version-cleanup.md`](archive/progress/2026-09-23-release-doc-version-cleanup.md)。
平台预检的本地实现、拒绝矩阵与尚缺的真实 WSL2 验收见
[`archive/progress/2026-09-23-platform-preflight-p2.md`](archive/progress/2026-09-23-platform-preflight-p2.md)。
机器可读能力协议的本地用例与输出边界见 [`docs/INSTALLATION.md`](docs/INSTALLATION.md)；
提交、测试结果与远端边界见
[`archive/progress/2026-09-23-capabilities-p2-local.md`](archive/progress/2026-09-23-capabilities-p2-local.md)。
只读 doctor 的本地实现、修复和双版本一次性 VM 验收见
[`archive/progress/2026-09-23-doctor-p2-vm.md`](archive/progress/2026-09-23-doctor-p2-vm.md)；
正式签名 Release 尚未包含它，该门槛仍随 P0-3/P1-4 开放。

## 完成规则

- 每个任务必须有可重复命令、精确 Git SHA、测试环境和结果证据。
- 静态检查、真实 VM、发布、安装、升级、回滚和生产使用是独立门槛，不得互相替代。
- 任何安全门槛失败都必须 fail closed；不得为了发布而放宽 host key、签名、checksum、权限或 root/user 边界。
- 完成项从本文件删除，并把必要证据移入 `archive/progress/`；本文件始终只表示当前未完成工作。
