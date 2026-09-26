# goenv v3 二进制修复：一次性 VM 验收

日期：2026-09-25。此报告针对草稿 PR #4 的本轮修复工作树；旧的源码 SHA 固定方案及其独立 Review 不再适用于本轮变更。正式 Release `v0.1.8` 已取消执行，标签仍指向 `9d613e85b4adaae4c9c8a5a7231556d68960b07e`；不可复用本报告放行该标签。

## 修复边界

- goenv 3.1.4 改从官方 Linux amd64/arm64 Release 归档安装，并按架构核对固定 SHA256；不执行上游安装脚本，也不重建旧的 Go 数据目录。
- 新用户禁用 goenv v3 默认的 `@latest` 工具下载；已有 `default-tools.yaml` 不被覆盖，显式启用额外工具的配置需明确 opt-in。
- 仅 Go 模式的依赖收敛为 `tar`；不再要求源码构建工具链。
- 当前默认 `go_version: 1.22.1` 未在本轮升级，不能据此认定它仍受 Go 官方安全维护。

## 测试环境

| 系统 | 一次性 VM | 镜像 SHA256 |
|---|---|---|
| Ubuntu 22.04.5 aarch64 | `devops-toolkit-2204-test-20260925114500-5832` | `ab5fcc80611a98bf999018045119d87b3a0e7c78f3b43b254b93d5c22bae3ff6` |
| Ubuntu 24.04.5 aarch64 | `devops-toolkit-2404-test-20260925114500-5832` | `7b682958a67ff5de068e36de6af8b75fa645d296af5a70d6500527f6a33781db` |

两台 VM 分别启动并核对系统、地址与 SSH 主机指纹。使用隔离 ansible-core 2.21.4 和已锁定的 collections；仅在 VM 内安装测试依赖 `zsh`。VM 出网通过临时无凭据 HTTP 代理；这不是离线或无代理下载证明。测试用户各自拥有全新 HOME，未接触现有服务器或生产环境。

## 结果

| 场景 | 22.04 | 24.04 |
|---|---|---|
| 仅 Go，首次安装 goenv 3.1.4 + Go 1.22.1 | 通过 | 通过 |
| 仅 Go，第二次执行 | `changed=0`, `failed=0` | `changed=0`, `failed=0` |
| 全组件组合，首次执行 | `changed=27`, `failed=0` | `changed=27`, `failed=0` |
| 全组件组合，第二次执行 | `changed=0`, `failed=0` | `changed=0`, `failed=0` |
| 全组件，新登录 Bash/Zsh | uv 0.9.18、Node v24.11.1、goenv 3.1.4、Go 1.22.1 可用 | 同左 |

全组件组合含 Shell/Oh My Zsh、uv、Node、Go 与共享 Linuxbrew 环境开关；两台 VM 均无真实共享 brew 可执行文件，因此只验证缺失时的 guarded loader。首次安装后，新 HOME 的 `default-tools.yaml` 为 `enabled: false`，未自动安装 gopls。仅 Go 的新登录 Shell 未加载 NVM。

Ubuntu 24.04 的独立用户预置 `default-tools.yaml` 为 `enabled: true` 时，Playbook 在下载 goenv 前按预期失败，且保留原文件；这是预期的安全负例。

本轮完整 `./tests/verify-ansible.sh`、依赖审计与 `git diff --check` 通过。宿主机未安装额外 lint 工具；远端 CI 与新提交的独立 Review 仍需完成。

## 保留门槛

- 该轮只实测 aarch64；amd64 的官方归档 SHA256 已固定，但未在本轮真实 amd64 VM 验证。
- `user_only_allow_system_dependencies=true` 的“apt 报成功但命令仍缺失”注入负例尚未完成；窄 sudo 规则无法满足 Ansible become，不能为测试擅自扩大到 `NOPASSWD: ALL`。
- goenv v2 已有数据目录迁移兼容只做非破坏性路径设计，尚未在真实旧 HOME 上验证。
- 本轮代码必须以新的精确 SHA 重新接受独立 Review、同 SHA 一次性 VM 验收及受保护发布审批；不能沿用旧 PR Review 或 `v0.1.8` 的历史标签报告。
- 默认 Go 1.22.1 已退出官方当前支持窗口，应另立受控版本升级和回归门槛，发布前处理。
