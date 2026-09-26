# P1-2：Ubuntu 全新 HOME 真实验收与 Go 阻断

日期：2026-09-25。受测源码与已推送 `v0.1.8` 的解引用提交均为
`9d613e85b4adaae4c9c8a5a7231556d68960b07e`。本轮只在一次性 VM
安装 `zsh`、`build-essential`，没有在宿主机安装软件或变更生产环境。

## 环境与权限

- Ubuntu 22.04.5 LTS：`devops-toolkit-2204-test-20260925092000-1292`，镜像 hash
  `ab5fcc80611a98bf999018045119d87b3a0e7c78f3b43b254b93d5c22bae3ff6`。
- Ubuntu 24.04.5 LTS：`devops-toolkit-2404-test-20260925092000-1292`，镜像 hash
  `7b682958a67ff5de068e36de6af8b75fa645d296af5a70d6500527f6a33781db`。
- 两台都是 aarch64；使用隔离 `ansible-core 2.21.4`、已锁定的 collections、临时
  Ed25519 密钥和 `known_hosts`。网络扫描与 VM 内 Ed25519 host key 指纹一致。
- 各开关组合使用独立普通用户及全新 HOME。先尝试以窄 sudo 白名单测试 user-only
  的自动 apt 路径；Ansible 提权命令不匹配，报 `Missing sudo password`，HOME 未修改。
  扩大到 `NOPASSWD: ALL` 被安全审查拒绝，未实施。随后只由 Multipass 管理入口在
  这些一次性 VM 内运行 `apt-get update` 与 `apt-get install -y zsh build-essential`。

## 已验证组合

每行顺序为 Ubuntu 22.04 / 24.04 的第一次 `changed`，第二次均为 0，且
`unreachable=0 failed=0`：

| 全新 HOME 组合 | 首次 changed | 二次 changed | 新登录 Shell |
| --- | --- | --- | --- |
| 仅 Shell + Oh My Zsh | 6 / 6 | 0 / 0 | Zsh 成功加载；NVM/goenv 未加载 |
| 仅 uv | 11 / 11 | 0 / 0 | Bash 找到 `uv 0.9.18`；NVM/goenv 未加载 |
| 仅 Node | 7 / 7 | 0 / 0 | Bash 找到 `node v24.11.1`；goenv 未加载 |
| 共享 brew 缺失 | 5 / 5 | 0 / 0 | Bash 中 guarded loader 无副作用 |
| 共享 brew 存在（无副作用 fixture） | 5 / 5 | 0 / 0 | Bash 执行 `brew shellenv` fixture |

真实 uv、Node、Oh My Zsh 下载与安装均成功；共享 brew 的“存在”分支仅验证 loader
调用语义，不是安装真实 Linuxbrew 的证明。原始 Ansible 日志保留在本轮隔离测试目录。

## 发布阻断：仅 Go

在两版 Ubuntu 的独立全新 HOME 上，`configure_go=true`、其他组件关闭时，
`goenv` clone 成功，但 `Install and select the configured Go version` 均失败：

```text
/bin/bash: line 3: goenv: command not found
/bin/bash: line 4: goenv: command not found
u2204go: ok=28 changed=7 unreachable=0 failed=1
u2404go: ok=28 changed=7 unreachable=0 failed=1
```

实际 clone 的提交是 `66571a3851c83e1341dce284aba907964c3d6a48`，
即草稿 PR #4 把 `3.1.4` 标签改成不可变 SHA 所固定的同一提交。
该上游 v3 仓库**没有 `bin/goenv`**：v3 是 Go 原生 CLI，clone 源码后需要
已有 Go 编译，或使用经校验的预编译产物。当前 Playbook 却假设旧版 shell
布局并直接调用 `$GOENV_ROOT/bin/goenv`。因此 PR #4 单纯 pin SHA 不解决此失败。

`v0.1.8` 标签已推送，但 Release workflow 仍应停在人工审批；不要把原有
系统模式 VM smoke 通过误认为 user-only 默认 Go 路径通过。修复需要新源码提交、
独立复核、同 SHA VM 验收和**新 patch 标签**，不得移动既有标签。

## goenv v2 兼容实验（尚非修复门禁）

上游仍维护 v2 分支。读取其 `master@3d2e6a042f366ad02ea090101b4c92c91c6670da`
确认存在旧版 `bin/goenv` 和 `plugins/go-build`。在之前因 v3 失败的两个测试 HOME
中，先把已缓存源码切到该不可变提交，再覆盖 `goenv_version` 复跑 Playbook：
Go 1.22.1 实际安装成功，下一次均 `changed=0`，新登录 Bash 能执行
`go version go1.22.1 linux/arm64`。这说明 v2 与现有调用方式兼容。

另建两个**全新** `p1gov2` HOME，直接由 Playbook 安装同一 v2 commit；两个 VM
均在 GitHub Git HTTPS 请求时遇到 `GnuTLS recv error (-110)`，尚未走到 Go 安装。
因此本轮不能声称修复候选通过全新 HOME 首装，仍需网络可用时重新验收。

## 尚未通过/未覆盖

- 仅 Go、全部语言工具开启、Go 新登录加载与二次 `changed=0`：当前失败。
- user-only 自动 apt 成功后重检，以及注入“apt 成功但命令仍缺失”：本轮 sudo
  最小权限方案不兼容 Ansible 包装命令，未做扩大权限的绕过。
- 仅 x86_64 VM：本轮两台均为 aarch64。

本报告只记录观测到的事实；它不替代 release workflow 或新候选 SHA 的发布验收。
