# DevOpsToolkit TODO

> 更新日期：2026-09-24
>
> 原则：这里只保留尚未完成、能够独立验收的工作。完成项及历史证据移入
> [`archive/progress/`](archive/progress/)，不要让历史记录掩盖当前优先级。

## 当前基线与边界

- 2026-09-22 review 从干净的 `main@74ef67b`（与 `origin/main` 一致）开始；以下结论以该基线为准。
- 最新 GitHub Release 为 `v0.1.7`；Validate、Release 均成功，三个固定名称资产齐全。
- `./tests/verify-ansible.sh`、ShellCheck、Actionlint、gitleaks 在 2026-09-22 review 中通过。
- 唯一受支持的环境配置实现仍是 `ansible/`，受支持入口是 `bin/` 与 `install.sh`。
- `AcmeConfig/` 不属于主线 Release，但根 README 仍向用户公开它；在完成下列 P0 安全整改前，不应宣称其为生产级。
- 2026-09-23 首次审计时 GitHub 控制面尚未落实仓库文档要求：`main`/`v*` 无 ruleset，
  `release` Environment 无保护规则，Release 未启用 immutable，Actions 未强制 SHA pin，
  Dependabot alerts/security updates 未启用；后续须重新认证并复核，不能将旧快照当成现状。
- 静态验证通过不等于真实 VM、升级回滚、SSH 登录切换或 ACME 证书续期已经完成验收。
- 2026-09-24 起暂缓 `AcmeConfig/` 的真实 CA/DNS 与独立仓库工作：它不在主线 Release 包中，
  其真实 CA 门槛不阻塞主线开发与发布，已有静态检查仍保留；但在自身真实环境验收完成前
  不得用于生产或宣称生产就绪。

## 当前执行顺序

1. P0-2：GitHub 发布控制面；待 `gh` 重新认证后先只读复核，再按获准范围落实设置。
2. P0-3：独立复核控制端基线并取得同 SHA 远端 Validate/正式 Release 证据。
3. P1/P2：继续可独立验收的运行安全、回归、升级回滚与文档工作。
4. 暂缓范围：P0-1 ACME 真实签发与续期、P2 ACME 独立仓库迁移；不以静态或自签证据替代其上线门槛。

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
同日后续无凭据复核再次看到 rulesets 为空；其余设置因本机 `gh` 凭据失效、API 返回
401 未能重新验证，不能把首次审计结果当成持续有效的现状。
同一 tag SHA 的完整质量门禁、`origin/main` 祖先校验、Release 来源 SHA 记录已在
`.github/workflows/release.yml` 实现；固定安装器 commit 与 SHA256 的示例见
[`docs/SUPPLY_CHAIN_SECURITY.md`](docs/SUPPLY_CHAIN_SECURITY.md)。这些实现仍须随新版本在远端实际验收。

- [ ] 为 `main` 建立 branch ruleset：禁止 force push/deletion，要求 Validate 必需检查；有第二维护者时再要求 approval 和防自审。
- [ ] 为 `v*` 建立 tag ruleset：限制创建者，禁止更新和删除已发布 tag。
- [ ] 为 `release` Environment 配置允许的 tag、审批或等价发布约束；不能继续保持空保护规则。
- [ ] 启用 immutable releases。已有非 immutable Release 保留历史状态；后续使用新版本号发布，不复用旧 tag。
- [ ] 将 Actions 限制为 GitHub 官方和显式审核的 Action，并在仓库设置中强制完整 commit SHA pin。
- [ ] 启用 Dependabot alerts/security updates；另行使用 Renovate regex manager 或自有脚本维护非标准 YAML/Shell 版本与 SHA256。
- [ ] 在新版本的真实 Release 中确认同 SHA 质量门禁、main 祖先检查、Source commit 记录及固定 commit 安装入口按预期生效；本地 workflow 和示例不能代替远端执行。

验收证据：GitHub API 显示 rulesets、Environment protection、immutable 和 Actions 限制均已生效；创建测试 tag 时只有受保护路径可发布；
新 Release 无法替换 tag 或资产，三个资产及 attestation/签名验证通过。

### P0-3：迁移到受支持的 Ansible 控制端基线

本地实现提交与真实 VM 证据见
[`archive/progress/2026-09-22-ansible-p0-3-runtime.md`](archive/progress/2026-09-22-ansible-p0-3-runtime.md)。
当前分支的锁定产物、完整本地门禁及临时构建复核见
[`archive/progress/2026-09-24-p0-3-current-branch-local-review.md`](archive/progress/2026-09-24-p0-3-current-branch-local-review.md)。
已固定 Python 3.12–3.14 / core 2.21.4、隔离 venv、22.04 目标边界及三项 collections，
并更新 README、安装/交互文档和 CI 定义。当前仍是未发布的本地分支。

- [ ] 推送前独立复核本地提交，并取得 GitHub Validate 在 Python 3.12、3.14 上对同一 SHA 的真实通过结果；
      本地 macOS Python 3.14 门禁与 Ubuntu 24.04 Python 3.12 runtime/两版目标 VM smoke 不等于远端矩阵通过。
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
干净 Ubuntu HOME 的完整两次收敛和新登录 Shell 验证尚未完成，以下只保留开放验收门槛。
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

本地代码提交 `b41a1e6` 已增加 PR 阶段编排测试、专用 Multipass runner workflow、机器可读报告、
失败清理与 Release 同 SHA 报告门禁。早期网络失败与自动清理见
[`archive/progress/2026-09-23-vm-p1-4-first-run.md`](archive/progress/2026-09-23-vm-p1-4-first-run.md)；
从干净提交 `f40192f` 经一次性 VM 代理完成的 22.04/24.04 首次配置、二次 `changed=0`、
SSH/UFW/Docker/Nginx 和故障恢复见
[`archive/progress/2026-09-23-vm-p1-4-proxy-e2e.md`](archive/progress/2026-09-23-vm-p1-4-proxy-e2e.md)。
最新双版本主路径与既有故障注入证据见
[`archive/progress/2026-09-23-ssh-p1-1-final-vm.md`](archive/progress/2026-09-23-ssh-p1-1-final-vm.md)。
SSH finalize 在 UFW 更新失败时的新端口保活与恢复证据见
[`archive/progress/2026-09-23-ssh-p1-1-guard-final.md`](archive/progress/2026-09-23-ssh-p1-1-guard-final.md)。
PR 编排测试、双版本本地 VM smoke、专用 runner workflow、报告及失败清理代码均已有
本地证据；以下验收项在远端 runner、PR 与 Release gate 实际运行前保持开放。

- [ ] 在真实 PR 的同一 SHA 上取得 Python 3.12/3.14 Validate 结果，确认 role/向导组合测试随 PR
      自动运行，而不只依赖本地静态检查。
- [ ] 接入可信的专用 `self-hosted,multipass` runner，在每周计划任务及发布前实际运行
      Ubuntu 22.04/24.04 首次收敛、二次 `changed=0`、SSH/UFW/Docker/Nginx 和故障恢复。
- [ ] 核验远端报告准确记录镜像、来源 SHA、Ansible 版本、结果和清理状态；注入失败时报告仍上传、
      测试实例仍清理，且缺少近期同 SHA 成功报告会阻止 Release。
- [ ] 在 runner 未就绪时保留明确的手工真实 VM release gate；不得以容器 syntax check
      或本地历史报告冒充远端 systemd/UFW/SSH E2E。

验收证据：计划任务和 release gate 都能产出可追溯报告；实例无论成功或失败都会安全清理，失败阻止发布。

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
