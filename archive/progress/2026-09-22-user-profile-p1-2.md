# P1-2 用户组件开关：本地实现与剩余 VM 门槛

日期：2026-09-22。实现提交：`c22645e6f1d79d9ffc10fc68a8f7f6f664a1572f`。
分支：`codex/devopstoolkit-hardening`。未推送、未发布，也未修改真实用户 HOME。

## 已实现

- 把基础 Zsh 管理与 Oh My Zsh 拆成 `configure_shell`、`install_oh_my_zsh` 两个开关；
  直接调用 Ansible 时拒绝 Oh My Zsh 开启而基础 Zsh 关闭的组合，向导则明确提示并自动关闭
  Oh My Zsh。
- 新增独立的 `environment.sh`。uv、NVM/Node、goenv/Go、共享 Linuxbrew 的 loader 同时接入
  `.profile` 与 `.zshrc`，不再依赖 `configure_shell=true`。
- `configure_homebrew_environment=true` 但共享 brew 不存在时选择“警告并跳过当前加载”：保留
  带可执行文件判断的 loader，使以后系统级安装完成后自动生效，且重复运行不产生变化。
- user-only 按启用组件检查 `git`、`zsh`、`curl`、`bash`、`tar`、`cc`、`make`；显式允许
  白名单 apt 安装后重新检查实际命令，仍缺失就 fail closed。
- `user-only-remove` 同时清理新旧 `.zshrc` marker 和 `.profile` 环境 marker，仍不删除用户原有
  文件或第三方工具目录。
- 向导单元测试覆盖远程已有账户、仅密钥新账户、Oh My Zsh 不兼容组合；模板矩阵测试覆盖
  uv、Node、Go、Linuxbrew 环境开关的全部 16 种组合。

## 验证结果

- `./tests/verify-ansible.sh`：通过。
- `ansible-lint ansible`：通过，0 warning；production profile passed。
- `yamllint .`：仅既有 Release workflow 的一条软性行长 warning。
- Ruff、ShellCheck、Actionlint、gitleaks、`git diff --check`：通过。
- `python3 tests/test-user-profile.py`：16 组环境矩阵及依赖重检顺序通过。

## 尚未完成

本地静态和模板矩阵不能替代干净 Linux HOME 的真实执行。网络可用后必须在一次性 Ubuntu
22.04/24.04 用户上覆盖关键组合，至少包括：基础 Zsh 开/关、Oh My Zsh 开/关、只启用
uv、只启用 Node、只启用 Go、只请求缺失的共享 brew、全部语言工具开启；每种组合执行两次，
第二次必须 `changed=0`，新登录 Shell 能找到所选工具，未选 loader 不出现。还要注入白名单
apt 返回成功但命令仍缺失的场景，证明重检会阻止角色继续。

因此 P1-2 暂不从 `TODO.md` 删除，当前报告只证明本地实现和静态门禁。
