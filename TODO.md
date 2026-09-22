# DevOpsToolkit TODO

> 更新日期：2026-09-22
>
> 原则：这里只保留尚未完成、能够独立验收的工作。完成项及历史证据移入
> [`archive/progress/`](archive/progress/)，不要让历史记录掩盖当前优先级。

## 当前基线与边界

- 2026-09-22 review 从干净的 `main@74ef67b`（与 `origin/main` 一致）开始；以下结论以该基线为准。
- 最新 GitHub Release 为 `v0.1.7`；Validate、Release 均成功，三个固定名称资产齐全。
- `./tests/verify-ansible.sh`、ShellCheck、Actionlint、gitleaks 在 2026-09-22 review 中通过。
- 唯一受支持的环境配置实现仍是 `ansible/`，受支持入口是 `bin/` 与 `install.sh`。
- `AcmeConfig/` 不属于主线 Release，但根 README 仍向用户公开它；在完成下列 P0 安全整改前，不应宣称其为生产级。
- 当前 GitHub 控制面尚未落实仓库文档要求：`main`/`v*` 无 ruleset，`release` Environment 无保护规则，
  Release 未启用 immutable，Actions 未强制 SHA pin，Dependabot alerts/security updates 未启用。
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

- [ ] 为 `main` 建立 branch ruleset：禁止 force push/deletion，要求 Validate 必需检查；有第二维护者时再要求 approval 和防自审。
- [ ] 为 `v*` 建立 tag ruleset：限制创建者，禁止更新和删除已发布 tag。
- [ ] 为 `release` Environment 配置允许的 tag、审批或等价发布约束；不能继续保持空保护规则。
- [ ] 启用 immutable releases。已有非 immutable Release 保留历史状态；后续使用新版本号发布，不复用旧 tag。
- [ ] 将 Actions 限制为 GitHub 官方和显式审核的 Action，并在仓库设置中强制完整 commit SHA pin。
- [ ] 启用 Dependabot alerts/security updates；另行使用 Renovate regex manager 或自有脚本维护非标准 YAML/Shell 版本与 SHA256。
- [ ] Release workflow 必须对待发布的同一 SHA 执行完整质量门禁，不能只依赖与 Release 并行运行的另一个 Validate workflow。
- [ ] 检查 tag commit 是 `origin/main` 的祖先，并在 Release 说明或 attestation 中记录精确 commit SHA。
- [ ] 为高安全安装提供固定 commit 或 immutable tag 的 bootstrap 方式；把可变 `main/install.sh` 明确标为便利入口，而非完整信任链。

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

### P1-1：把 SSH 改端口和加固改成两阶段事务

本地两阶段实现提交 `1bb5b8c`，阶段证据与未完成的最终 VM 门槛见
[`archive/progress/2026-09-22-ssh-p1-1-transition.md`](archive/progress/2026-09-22-ssh-p1-1-transition.md)。
最终候选的完整双版本故障注入回归仍需在 apt 网络可用时重跑；不得将定向 SSH role 测试
当作整套 Ubuntu bootstrap 验收。

- [ ] 第一阶段创建目标账户/密钥，同时放行旧端口与新端口，再修改并验证 SSH listener。
- [ ] 从控制端使用目标普通用户和新端口建立全新连接；不能只复用现有 root ControlMaster 会话。
- [ ] 第二阶段仅在新连接成功后关闭旧端口，并按显式选择禁用 root/password 登录。
- [ ] 将 `disable_root_login=true` 从当前 root 会话无法自证的单阶段流程中移出，或实现可靠的连接用户切换。
- [ ] 失败时保留旧端口和当前可用登录方式，输出恢复命令，不留下“UFW 已关旧端口但 SSH 未切换”的中间态。

验收证据：Ubuntu 22.04/24.04 各验证传统 `ssh.service` 与 `ssh.socket`；注入无效 sshd 配置、新端口占用和目标用户密钥失败，均不得锁死主机。

### P1-2：修正用户组件开关和依赖闭环

本地实现提交 `c22645e`，静态门禁与 16 组开关矩阵见
[`archive/progress/2026-09-22-user-profile-p1-2.md`](archive/progress/2026-09-22-user-profile-p1-2.md)。
干净 Ubuntu HOME 的两次收敛和新登录 Shell 验证尚未完成，以下条目继续保留为开放验收门槛。

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

- [ ] PR 阶段增加可快速运行的 role/向导组合测试；不得只测试少量辅助函数。
- [ ] 每周或发布前在一次性 VM 运行 `tests/multipass-smoke.sh`：首次收敛、二次 `changed=0`、SSH/UFW、Docker/Nginx 和故障恢复。
- [ ] 保持 Ubuntu 版本、Ansible 版本和测试实例严格隔离；测试报告记录镜像、SHA、结果和清理状态。
- [ ] 在没有安全可用 VM runner 时，明确保留手工 release gate，不能用容器 syntax check 冒充 systemd/UFW/SSH E2E。

验收证据：计划任务和 release gate 都能产出可追溯报告；实例无论成功或失败都会安全清理，失败阻止发布。

### P1-5：完成真实升级与回滚闭环

- [ ] 在真实临时 VM 从 `v0.1.4` 升级到 `v0.1.7` 或后续受保护版本。
- [ ] 验证 latest 与 `--version` 两条安装路径、SHA256、Sigstore 身份、三个 Release 资产和普通用户 `devops-toolkit --version`。
- [ ] 验证旧版本目录保留、相同版本重复安装幂等、不同版本原子切换，并按文档原子回滚后再次运行命令。
- [ ] 记录 macOS `sudo --system` 安装后普通用户解析 launcher 符号链接的真实结果。

验收证据：将命令、环境、版本、关键输出和失败边界写入 `archive/progress/`；不得包含 Token、私钥、密码或用户真实主机信息。

## P2：维护性与文档一致性

- [ ] 更新 README 和全部示例版本：`v0.1.7` 已发布，不再把 `v0.1.4` 写成当前基线，也不再使用“从下一版 v0.1.5 起”。
- [ ] 严格区分 WSL1/WSL2，并在任何 apt/system 变更前验证受支持的发行版、版本和架构。
- [ ] 为安装器、向导和 Playbook 定义稳定的机器可读版本/能力输出，便于批量审计已安装节点。
- [ ] 设计只读 `doctor`/preflight 命令：检查控制端 runtime、collections、SSH 配置、目标 OS、磁盘、网络和权限，不执行配置变更。
- [ ] 评估将 `AcmeConfig/` 独立成单独仓库或正式 Ansible role；在安全模型、发布节奏和测试矩阵不同的情况下，不继续用根 README 弱耦合维护。

## 完成规则

- 每个任务必须有可重复命令、精确 Git SHA、测试环境和结果证据。
- 静态检查、真实 VM、发布、安装、升级、回滚和生产使用是独立门槛，不得互相替代。
- 任何安全门槛失败都必须 fail closed；不得为了发布而放宽 host key、签名、checksum、权限或 root/user 边界。
- 完成项从本文件删除，并把必要证据移入 `archive/progress/`；本文件始终只表示当前未完成工作。
