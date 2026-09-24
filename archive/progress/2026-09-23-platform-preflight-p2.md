# P2 平台预检阶段证据

日期：2026-09-23

## 本地实现

- `install.sh` 在 Python、apt、下载及 `/opt` 写入之前检查控制端：Linux 仅支持
  x86_64/aarch64 Ubuntu 24.04，macOS 仅支持 x86_64/arm64；含 Microsoft 标记的 Linux
  内核必须同时有 WSL2 标记，WSL1 拒绝。`--help` 仍可在不满足平台要求时只读显示。
- `wsl-bootstrap.yml` 在 system role 之前检查 Ubuntu 24.04、架构及
  `/proc/sys/kernel/osrelease` 的 WSL2 标记，不再以泛泛的 `microsoft` 识别 WSL。
- `ubuntu-bootstrap.yml`、`ubuntu-ssh-finalize.yml` 在任何 apt/SSH/UFW 变更前验证
  Ubuntu 22.04/24.04 与 x86_64/aarch64。
- `user-only.yml` 仅在明确启用可选 sudo apt 依赖安装时执行同类目标平台检查；
  默认纯 HOME 模式不被不必要地限制。

## 已验证与未验证边界

- `tests/test-orchestration.py` 使用真实 Ansible assert 任务验证支持与拒绝矩阵，
  包括 WSL2、WSL1、普通 Linux 内核标记；并检查平台任务处于 pre_tasks 的前部。
- `tests/test-installer.sh` 注入平台事实，验证 Ubuntu 22.04、Debian、非支持架构、WSL1
  均被拒绝，且拒绝后不会进入依赖安装；macOS arm64 与 WSL2 Ubuntu 24.04 被接受。
- 固定 ansible-core 2.21.4 加锁定 collections 执行 `./tests/verify-ansible.sh` 通过；
  `ansible-lint ansible`、`yamllint .`、`ruff check tests/test-orchestration.py`、
  `shellcheck install.sh tests/test-installer.sh` 与 `git diff --check` 通过。
- 本机是 macOS；没有真实 WSL1/WSL2 Ubuntu 实例。本地断言与模拟内核标记不能替代
  WSL2 24.04 x86_64/aarch64 的真实启动、apt 前拒绝路径与重复运行验收，因此 TODO
  平台项仍保持开放。
