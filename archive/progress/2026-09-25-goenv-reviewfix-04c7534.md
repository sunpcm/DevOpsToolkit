# goenv SHA 复核修复与 Go 1.27.1：双版本一次性 VM

日期：2026-09-25。受测代码提交：`04c7534889b40eb5440e33ca8843fbef9948fedd`；执行全组件验收时 Git 工作树干净。该提交修复了草稿 PR #4 首轮独立 Review 的 `CHANGES REQUESTED`：旧逻辑只凭 `--version` 子串判断现有 goenv 是否可信，可能跳过固定 SHA 安装。此次在执行现有文件之前核对其固定 SHA256；不匹配就从按 SHA256 验证的官方归档重新安装，随后再核对新文件 SHA 和精确版本。默认 Go 从已退出官方支持窗口的 1.22.1 升到 1.27.1。
上游依据：[goenv 3.1.4 Release](https://github.com/go-nv/goenv/releases/tag/3.1.4)、[Go 官方下载及 Linux 架构 SHA256](https://go.dev/dl/)、[Go 支持政策](https://go.dev/doc/devel/release)。

## 环境

| 系统 | 一次性 VM | 镜像 SHA256 |
|---|---|---|
| Ubuntu 22.04.5 aarch64 | `devops-toolkit-2204-test-20260925121000-7391` | `ab5fcc80611a98bf999018045119d87b3a0e7c78f3b43b254b93d5c22bae3ff6` |
| Ubuntu 24.04.5 aarch64 | `devops-toolkit-2404-test-20260925121000-7391` | `7b682958a67ff5de068e36de6af8b75fa645d296af5a70d6500527f6a33781db` |

两台顺序启动，核对 VM 内 SSH Ed25519 指纹与网络扫描一致。使用既有隔离 ansible-core 2.21.4 和锁定的 collections；宿主机未安装软件。仅在 VM 内安装测试依赖 `zsh`，并在备份 `/etc/environment` 后设置无凭据临时代理 `192.168.252.1:7897`。Go 1.27.1 官方下载文件和 goenv 3.1.4 Release 文件均经真实网络获取；这不是无代理或离线安装的证明。
验收后使用 `./tests/multipass-smoke.sh cleanup` 对两个精确名称清理，随后 `multipass list --format json` 返回空列表；VM 内测试用户、代理配置和数据已随实例删除，不可恢复。

## 结果

| 场景 | Ubuntu 22.04 | Ubuntu 24.04 |
|---|---|---|
| 全新 HOME，仅 Go 首次 | `ok=42 changed=15 failed=0` | `ok=42 changed=15 failed=0` |
| 仅 Go 第二次 | `changed=0 failed=0` | `changed=0 failed=0` |
| 全新 HOME，全组件首次 | `ok=62 changed=27 failed=0` | `ok=62 changed=27 failed=0` |
| 全组件第二次 | `ok=47 changed=0 failed=0` | `ok=47 changed=0 failed=0` |
| Bash/Zsh 新登录 | uv 0.9.18、Node v24.11.1、goenv 3.1.4、Go 1.27.1 | 同左 |

全组件包含基础 Shell、Oh My Zsh、uv、Node、Go 与 Linuxbrew 环境开关；两台没有真实共享 brew，故只验证缺失时 guarded loader。仅 Go 的 Bash 新登录没有加载 NVM。两台新 HOME 的 `default-tools.yaml` 均为 `enabled: false`，没有隐式安装 `@latest` 工具。

Ubuntu 22.04 负例：先备份正确二进制，再放入 `--version` 会输出 `goenv 13.1.4` 且执行时会创建标记文件的假 goenv。Playbook 重新下载并安装固定 SHA 文件，`changed=5 failed=0`；标记文件未出现，证明假文件未被执行。恢复后 SHA256 为 `a25cb3515c70c71a0be23539522a7d96009d332a558d82f008f3313eb966b81a`，Bash 新登录仍报告 `goenv 3.1.4` 和 `go version go1.27.1 linux/arm64`。

Ubuntu 24.04 迁移样本：在另一全新用户 HOME 中先克隆官方 goenv `2.2.46` 的真实 Git checkout，提交为 `3d2e6a042f366ad02ea090101b4c92c91c6670da`，其 `bin/goenv` 存在。新 Playbook 首次 `changed=15 failed=0`，第二次 `changed=0 failed=0`。原 checkout 提交与旧 `bin/goenv` 均保留；新 Bash 登录运行 goenv 3.1.4 与 Go 1.27.1。该测试覆盖旧 checkout 与新 v3 共存，不等于覆盖所有可能的旧用户自定义配置。

官方 goenv 两份归档 SHA256 与仓库固定值一致；从归档中提取的 Linux amd64/arm64 可执行文件摘要也与新固定值一致。完整 `./tests/verify-ansible.sh`、依赖审计及 `git diff --check` 通过。

## 尚未关闭

- 这是 aarch64 真实 VM 验收；amd64 只核对官方归档及解包文件摘要，未做真实 VM 安装。
- 真实 v2 checkout 的基本共存路径已在 24.04 验收；自定义插件、复杂旧配置与已有 Go 版本的迁移仍未全面覆盖。
- `user_only_allow_system_dependencies=true` 的“apt 成功但命令仍缺失”故障注入负例尚未完成，不为测试擅自放宽 sudo 边界。
- 旧 `v0.1.8` tag 仍指向失败的 `9d613e8`，Release 流程已取消；本报告不授权复用该标签。新代码仍需独立复审、PR CI、合并后的同 SHA 发布前 VM 报告、受保护审批、正式签名 Release 与安装/回滚验收。
