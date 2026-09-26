# P1-2 最小补测记录

受测干净 SHA：`89e4a7a4e5510c5a54c7a82d77261c28aceea4ff`。
与主线 `58cc9a2` 的 `ansible/` 无差异。使用已有隔离 ansible-core 2.21.4
与锁定 collections；宿主未安装软件。下列结果仅限 aarch64。

## 已完成

- Ubuntu 22.04.5，实例 `devops-toolkit-2204-test-20260926130000-2601`：
  Shell 开启／Oh My Zsh 关闭首次 `changed=4`，二次 `changed=0`，均 failed=0；
  新登录 Zsh 的串行 `&&` 断言验证 NVM_DIR／GOENV_ROOT 为空且未安装 Oh My Zsh。
  Bash 输出成功标记，但早期命令未启用失败传播，不能证明全部负向断言通过，仍需补回。
  仅 uv 和仅 Node 的独立新 HOME 安装成功；Bash/Zsh 能发现所选工具，
  未选 loader 的环境变量没有出现。该实例已清理，数据不可恢复。
- Ubuntu 24.04.5，实例 `devops-toolkit-2404-test-20260926130000-2601`：
  Shell-only 首次 `changed=4`，二次 `changed=0`，均 failed=0；
  Bash/Zsh 的 Shell-only、仅 uv、仅 Node、仅 Go 登录断言均通过。
  单组件首次 changed 分别为 uv=11、Node=7、Go=15，均 failed=0。
  所选版本为 uv 0.9.18、Node v24.11.1、goenv 3.1.4／Go 1.27.1。
  未选 NVM/goenv 的变量和命令显式检查为空／不存在；Node/Go HOME 未安装 uv。
  该实例已清理，随后实例列表为空。

## 环境异常与修正

首次并行创建两个实例出现相同 MAC/IP，指定24.04时实际连接22.04；
身份核对发现异常后停止验收，隔离实例并改为逐台执行，未将错误连接记为双系统结果。
24.04随后经 hostname、os-release 与 SSH 主机指纹交叉核对身份。

22.04 的仅 Go 安装成功，但最初 sudo 切换用户后未进入该用户 HOME，
Go 因当前目录权限拒绝运行。该失败不能作为登录断言通过；原实例清理过早，
已用新的 `devops-toolkit-2204-test-20260926140000-2602` 补回此项：
真实安装成功，首次 `ok=42 changed=15 failed=0`；Bash/Zsh 精确版本与
未选 loader 断言均输出 `LOGIN_go_PASS`。测试后实例已清理，列表为空。

统一断言已改为先 `cd "$HOME"`，检查精确所选版本、未选变量及命令；
所有负向命令检查使用显式 `if ...; then exit 1; fi`，不依赖 `!` 的 errexit 语义。
串行执行在任一步失败时停止，保留现场。当前等待独立复核，再决定 P1-2 TODO 收敛。

## 复验与摘要

仅在一次性 VM 使用已有隔离运行时执行 user-only Playbook，各组件启用一个开关，
其他组件关闭，Shell-only 额外关闭 Oh My Zsh。登录检查在普通目标账号中运行：
`bash -lc` 与 `zsh -lic`，先 `cd "$HOME"`，再核对精确版本及未选变量／命令。
Shell-only 无工具安装；仅 uv 检查 uv 0.9.18 且 NVM_DIR／GOENV_ROOT 为空；
仅 Node 检查 v24.11.1 且 GOENV_ROOT 为空；仅 Go 检查 goenv 3.1.4 和
`go version go1.27.1 linux/arm64` 且 NVM_DIR 为空。不要在长期主机创建测试账号。

原始日志暂存在宿主临时目录，不保证永久保存。24.04 与补回22.04的
每对 Bash/Zsh 登录日志 SHA256 相同：

- uv：`5dd0af0815d3370d8da58c7366422f10af9eeec113ea9d1107f48f24f5a4cf35`（24.04）。
- Node：`dc3fc65d61991148ea0f6588b2d2a14f850036dcda1db30a2345d279224c731d`（24.04）。
- Go：`e06d5a9478fc8f60b294114a49a443feffdd8bbb0b0634ab3d4712be6288471b`（两版）。

各文件内容为对应 `LOGIN_<组件>_PASS`，摘要用于核对原件，不替代重新执行。
22.04早期 Shell/uv/Node 登录结果来自执行输出，未独立保存登录日志；
相关首次／重复 Ansible 日志仍保留。本报告明确区分此证据保存边界。

这不是正式 Release 的同 SHA 完整 VM 报告，亦不证明 amd64、真实 WSL2
或复杂旧 Go 配置迁移。历史组合两次收敛报告仍单独保留。
