# DevOpsToolkit TODO

> 更新日期：2026-09-23
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

## P0：安全与发布阻塞项

### P0-1：先隔离并重构 `AcmeConfig/`

已完成的本地实现、静态检查与 Ubuntu 24.04 一次性 VM 证据见
[`archive/progress/2026-09-22-acme-p0-1-vm.md`](archive/progress/2026-09-22-acme-p0-1-vm.md)。
整组证书原子发布、故障恢复及多消费者复测见
[`archive/progress/2026-09-22-acme-p0-1-bundle.md`](archive/progress/2026-09-22-acme-p0-1-bundle.md)。
这不是生产验收：VM 仅使用自签证书模拟部署，未通过真实 CA 签发。

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

本地实现提交 `c22645e`，静态门禁与 16 组开关矩阵见
[`archive/progress/2026-09-22-user-profile-p1-2.md`](archive/progress/2026-09-22-user-profile-p1-2.md)。
干净 Ubuntu HOME 的两次收敛和新登录 Shell 验证尚未完成，以下条目继续保留为开放验收门槛。
Ubuntu 24.04 对“仅请求缺失的共享 brew”、关闭 loader、缺少 zsh 时的 fail-closed
进行了部分真实 HOME 验证；结果与网络边界见
[`archive/progress/2026-09-23-user-profile-p1-2-vm-partial.md`](archive/progress/2026-09-23-user-profile-p1-2-vm-partial.md)。
环境 loader 的 16 组实际 `/bin/sh` 加载测试见
[`archive/progress/2026-09-23-user-profile-p1-2-shell-matrix.md`](archive/progress/2026-09-23-user-profile-p1-2-shell-matrix.md)。
Shell 关闭但语言工具开启、Oh My Zsh 约束及 user-only 依赖例外的向导链路测试见
[`archive/progress/2026-09-23-user-profile-p1-2-wizard-paths.md`](archive/progress/2026-09-23-user-profile-p1-2-wizard-paths.md)。

- [ ] 拆分“管理基础 Shell 环境”与“安装 Oh My Zsh”；Node、Go、uv、Linuxbrew 环境加载不得隐式依赖 `configure_shell=true`。
- [ ] 向导对不兼容组合给出约束或明确说明，并为全部关键开关组合增加测试。
- [ ] user-only 按启用组件检查 `curl`/`wget` 等实际下载依赖；白名单安装后重新检查命令，不能直接假设 apt 成功等于依赖可用。
- [ ] 明确 `configure_homebrew_environment=true` 但共享 brew 不存在时是跳过、警告还是失败，并保持幂等。
- [ ] 为远程已有账户、仅密钥新账户、Shell 关闭但语言工具开启等路径增加向导单元测试。

验收证据：每种受支持组合在干净 HOME 中执行两次，第二次 `changed=0`；新登录 Shell 能找到所选工具，未选工具不会被意外加载或删除。

### P1-3：补齐第三方依赖完整性锁定

- [x] 为 `ansible.posix`、`community.general` 等 collection 保存下载产物 SHA256；构建前验证 tarball，不只读取可被伪造的 `MANIFEST.json` 版本。
- [x] 建立单一 lock manifest，生成或校验 `requirements.yml`、Release marker、安装器检查和测试夹具，删除多处手工重复版本。
- [x] 明确 apt、Docker、Homebrew formula 属于滚动更新还是可复现安装；文档不得把“Git source 固定”表述成整个系统 bit-for-bit 可复现。
- [x] 建立月度依赖审计：Ansible、collections、Cosign、uv、NVM、goenv、Go、Node LTS、Actions；更新必须走 PR、校验值复核和 VM smoke。

验收证据：篡改 collection tarball、marker、manifest 或 checksum 任一项都会在发布前失败；依赖审计能生成只读报告，不自动合并高风险更新。

本地实现提交 `306b1d4`；官方归档 SHA256、离线安装复核、篡改矩阵、完整静态门禁及未执行的
远端边界见 [`archive/progress/2026-09-22-supply-chain-p1-3.md`](archive/progress/2026-09-22-supply-chain-p1-3.md)。

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
以下验收项在远端 runner、PR 与 Release gate 实际运行前保持开放。

- [ ] PR 阶段增加可快速运行的 role/向导组合测试；不得只测试少量辅助函数。
- [ ] 每周或发布前在一次性 VM 运行 `tests/multipass-smoke.sh`：首次收敛、二次 `changed=0`、SSH/UFW、Docker/Nginx 和故障恢复。
- [ ] 保持 Ubuntu 版本、Ansible 版本和测试实例严格隔离；测试报告记录镜像、SHA、结果和清理状态。
- [ ] 在没有安全可用 VM runner 时，明确保留手工 release gate，不能用容器 syntax check 冒充 systemd/UFW/SSH E2E。

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

- [ ] 严格区分 WSL1/WSL2，并在任何 apt/system 变更前验证受支持的发行版、版本和架构。
- [ ] 在新签名 Release 中验证安装器、向导和 Playbook 的 `--capabilities-json` 协议；本地实现与包测试不能证明远端资产已更新。
- [ ] 在 P0-1 真实环境门槛通过后，将 `AcmeConfig/` 迁入受保护的独立仓库与签名 Release，迁移主线 CI/README 引用；不把证书生命周期塞进主线 Ansible role。

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
