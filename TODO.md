# DevOpsToolkit TODO

> 更新日期：2026-11-11
>
> 本文件只记录尚未完成、可以独立验收的事项，以及每次发布必须重跑的清单。完成项和完整证据
> 保留在 [`archive/progress/`](archive/progress/)；静态检查、真实 VM、发布、安装/回滚和生产使用
> 是不同门槛，不能互相替代。

## 当前基线

- 最新正式 Release 为 `v0.1.10`，来源提交是
  `571a5fef119055470d33ff478c0f69ba0524b1c5`。本文校准时的 `main` 为
  `1c316b84816a87e6b7b6a8dd3ecac58d30943697`，包含 Release 之后的改动；不能把
  `main` 当作 `v0.1.10` 的签名资产。
- `v0.1.8` 的 Release 曾取消，但标签已占用；`v0.1.9`、`v0.1.10` 已正式发布。
  `v0.1.2`–`v0.1.10` 均不得复用。
- Python 3.12–3.14、隔离 `ansible-core 2.21.4` runtime 及包内锁定 collections 的安装控制端迁移
  已随 `v0.1.9`、`v0.1.10` 正式发布；`v0.1.10` 补齐了 `current/bin/*` 包装入口修复。
- 唯一受支持的环境配置实现仍是 `ansible/`，受支持入口是 `bin/` 与 `install.sh`。
  `AcmeConfig/` 是实验组件，不进入主线 Release。
- 当前稳定化分支的 SSH 双栈本地代码交付已完成并通过独立 Review（APPROVED）：最终源码的
  `./scripts/verify-dev.sh`（Python 3.12 全门禁）与 `--ansible-only`
  （Python 3.14 / `ansible-core 2.21.4`）均退出 0。该交付尚未合并或发布，也不在 `v0.1.10`
  正式资产中。
- `v0.1.10` 签名资产仍包含 uv `0.9.18` 和旧 NVM 固定 commit，独立审计已确认其命中已知
  漏洞记录。当前候选源码已固定 uv `0.13.7`、NVM `v0.41.0`
  （commit `4e8758a801eea9479b32a904f31093e410ddaba4`）、Node `24.22.2` 和
  Go `1.27.3`。2026-11-11 已在两个一次性 Ubuntu 22.04/24.04 ARM64 VM 上完成限定的
  user-only 组件升级验收：旧 uv/NVM/Node/Go 升级后，第二次运行满足
  `changed=0`、`unreachable=0`、`failed=0`；严格主机指纹 SSH 后的新 Bash/Zsh 登录版本正确，
  旧 goenv v2 + Go `1.26.7`、插件及自定义 Go 策略 hash 未变，旧 Node `24.11.1` 和托管
  Go `1.27.1` 仍可运行，NVM 用户文件保留。该限定结果不替代完整候选或 Release 验收，
  修复尚未发布，也不能追溯修复已发布资产。

## 未完成事项

### SSH 双栈交付与验收

- [x] 完成本轮 SSH 双栈实现、静态/单元测试和独立评审（APPROVED）；当前仅代表未合并、未发布
      的本地代码交付。
- [ ] **正式 Release 发布前的必过门禁**：候选代码合并后、打 tag 和发布前，在隔离的一次性真实
      Ubuntu 目标上对将要发布的精确候选 SHA 验收 IPv4、IPv6 监听与登录、端口迁移、失败恢复
      和二次幂等；该 SSH 真实 VM 验收不得推迟到 Release 之后。
- [ ] 候选通过上述门禁并取得发布授权后，发布经过签名和校验的正式资产；随后在干净目标上完成
      签名安装、版本识别、runtime/包装入口和安装后可运行性验收。发布后的安装验收不能替代或
      追认发布前必须通过的候选 SSH 门禁。

### 依赖安全修复与发布

- [ ] 完成安全 pin 修复的发布闭环。uv `0.13.7` 的两种 Linux 架构摘要已完成官方归档、
      sidecar 与 API 三方核验，上述双 Ubuntu ARM64 user-only 升级验收也已完成；仍需随完整
      候选门禁完成独立评审、打包及签名 Release 安装验收。当前 OSV 查询在其声明覆盖范围内
      完成且未发现记录，但组件升级证据、单次零匹配和静态检查都不能替代完整候选与
      Release 验收，也不能描述为全面无漏洞。
- [ ] 只有包含新 pin 的签名 Release 实际发布并通过候选及安装门禁后，才能宣称旧依赖问题已对
      发布资产完成修复。`v0.1.10` 的现有签名资产不会因 `main` 源码更新而改变。

### 真实环境验收

Ubuntu 22.04/24.04 ARM64 一次性真实 VM 已覆盖“APT 报告成功但命令缺失”这一限定失败路径：
两者均得到退出码 2，并确认 APT 报告成功、命令缺失守卫命中、未进入 `user_profile`、HOME 普通
文件哈希不变，测试后已恢复 zsh。该证据不覆盖其他 APT 故障。

- [ ] 补齐 amd64 用户组件组合及复杂旧 Go 配置迁移的真实环境回归；现有 aarch64 证据不能替代。
- [ ] 记录 macOS `sudo --system` 安装后普通用户解析 launcher 链接的真实结果。
- [ ] 在真实 WSL2 Ubuntu 24.04 上验收安装器与 Playbook 的平台预检、首次及重复运行；
      模拟内核标记不能替代真实启动证据。

### GitHub 发布保护负例

- [ ] 在隔离测试目标和另行取得的操作授权下，验证 `v*` 标签更新/删除被拒绝、
      Release 资产不可替换、非 `v*` 来源不能进入 `release` Environment，以及管理员不能绕过审批。
      禁止用真实 `v0.1.10` 资产做破坏性测试。

### ACME（暂缓）

- [ ] 恢复推进时，以受控域名完成真实 CA 首次签发、DNS/webroot 挑战、模拟续期、真实
      DNS provider 日志审计、Ubuntu 22.04 回归和真实消费者恢复。自签或离线测试不能替代。
- [ ] 上述真实环境门槛完成后，再评估将 `AcmeConfig/` 迁入受保护的独立仓库与签名 Release。

真实 CA 签发和独立仓库迁移按现决定暂缓，不阻塞主线开发与发布；迁移未执行，
组件仍不得宣称生产就绪。边界与未来执行顺序见 [ACME 维护边界](docs/ACME_BOUNDARY.md)。

### 开发验证入口

- [ ] 完成 `scripts/verify-dev.sh`、`requirements-dev.txt` 与新增测试的并行工作流验收及
      独立复核。当前源码接口与 CI 共享 `requirements-dev.txt` 中的精确 pin；在整体门禁完成前
      不宣称该工具链已合并或已发布。

## 每次发布清单

- [ ] 候选代码已合并；工作树干净，tag 将指向待发布的精确 `main` 来源 SHA，并已取得明确发布授权。
- [ ] 同一 tag SHA 的 quality、Python 3.12、Python 3.14 及完整静态门禁通过；其他 push/PR
      运行不能替代 Release workflow 内的同 SHA 门禁。
- [ ] 针对该精确 SHA 在隔离主机运行 Ubuntu 22.04/24.04 一次性 VM 验收，覆盖首次收敛、
      二次 `changed=0`、SSH/UFW/Docker/Nginx、故障恢复和清理；报告在 8 天内，原件与 SHA256 可核对。
      本轮 SSH 双栈候选还必须单独覆盖 IPv4、IPv6 的监听与登录、端口迁移和失败恢复，未通过时
      禁止进入 tag 和 Release 审批。
- [ ] collections 中间产物 `retention-days` 为 `8`，审批时仍未过期；过期后不得绕过审批窗口继续发布。
- [ ] 核对目标 SHA 中实际进入产物的依赖 pin 和本次依赖安全结论，确认不是仅有源码更新；
      运行 `python3 scripts/dependency-audit.py --check-security --output dependency-audit.md`，
      并保留报告。退出码非零可能表示发现漏洞、固定值不一致或任一 OSV 查询未完成；退出 0
      也只表示当前声明覆盖范围完成且未匹配，不代表全面安全。
- [ ] 执行 `git fetch --tags origin` 并检查目标版本不存在；使用新授权且未占用的版本号，
      禁止复用 `v0.1.8`、`v0.1.9`、`v0.1.10` 或任何历史 tag。
- [ ] 受保护的 `release` Environment 审批人核对 tag SHA、来源 SHA、当次 VM 报告原件及摘要；
      缺证据、证据过期或失败时拒绝发布，不能强制绕过。
- [ ] 发布后核对三个资产、Sigstore 身份、source commit 说明和包内 `VERSION`，并完成当次
      安装、重复安装、升级、回滚/前滚及必要的平台验收；这些结果不能替代发布前的精确 SHA
      VM 门禁。

完整命令和审批操作见 [发布流程](docs/RELEASING.md)，供应链边界见
[发布供应链安全](docs/SUPPLY_CHAIN_SECURITY.md)。

## 已归档的关键证据

以下证据只证明其记录的精确范围，不关闭上面仍未执行的平台、保护负例或真实 CA 门槛：

- `v0.1.10` 正式资产的安装、升级、回滚/前滚、runtime 缺失负例及清理见
  [`archive/progress/2026-09-27-v010-release-install.md`](archive/progress/2026-09-27-v010-release-install.md)。
- 已安装 runtime 的断网复用见
  [`archive/progress/2026-09-27-v010-offline-runtime.md`](archive/progress/2026-09-27-v010-offline-runtime.md)。
- GitHub 控制面的首次只读审计和正向发布门禁见
  [`archive/progress/2026-09-24-release-gate-manual-vm.md`](archive/progress/2026-09-24-release-gate-manual-vm.md)。
- ACME 的本地实现、权限检查及自签/离线 VM 证据见
  [`archive/progress/2026-09-24-acme-p0-1-log-mode-vm.md`](archive/progress/2026-09-24-acme-p0-1-log-mode-vm.md)。
- `v0.1.9` 的原始日志缺口及其边界见
  [`archive/progress/2026-09-27-v019-release-install.md`](archive/progress/2026-09-27-v019-release-install.md)；
  `v0.1.10` 的完整原件已补足该次安装/回滚交付缺口，但不替代未来候选的验收。

## 完成规则

- 每个事项必须有可重复命令、精确 Git SHA、测试环境和结果证据。
- 安全门槛失败必须 fail closed；不得为了发布而放宽 host key、签名、checksum、权限或 root/user 边界。
- 完成项从本文件移出，必要历史证据保留在 `archive/progress/`。
