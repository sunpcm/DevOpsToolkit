# P2 只读 doctor：本地实现与远端验收边界

日期：2026-09-23。实现提交：`98012c2`。分支：`codex/devopstoolkit-hardening`。
未推送、未发布，未连接真实远端主机。
后续发现此提交漏传远端探针参数，已在 `7b1ca5c` 修复并完成真实双版本 VM 验收；
见 [`2026-09-23-doctor-p2-vm.md`](2026-09-23-doctor-p2-vm.md)。本页保留初始本地证据。

## 已实现

- `devops-toolkit doctor` 检查控制端平台/Python、隔离 runtime、锁定 collections 的
  marker/manifest 元数据、Ansible host-key/全局提权设置、磁盘与直连 TCP/443。
- 只有同时显式传入 `--host`、`--user` 才发起远程检查；要求已有且非组/其他用户可写的
  `known_hosts`，强制 `StrictHostKeyChecking=yes`、`BatchMode=yes`、独立连接、
  `UpdateHostKeys=no`。远端只运行 Python 标准库读取探针、`sudo -n true` 和 `sshd -t`，
  不执行 Playbook 或修改目标配置。
- 报告区分 `pass`、`warn`、`fail`；普通用户的 `sudo -n true` 只能证明非交互 sudo
  可用，不能证明完整 bootstrap 权限，因此保持 warning。`--no-network` 亦为 warning。

## 本地验证

- `python3 tests/test-doctor.py`：严格 SSH 参数、非法目标/不安全 known_hosts 拒绝、
  collection 多路径与缺失路径、无远端时本地 JSON 报告通过；SSH 响应为模拟数据。
- `./tests/test-release.sh`：本地测试包内的 `devops-toolkit doctor --help` 通过。
- macOS arm64/Python 3.14 控制端，隔离 Ansible 2.21.4 与经 lock 校验的三项 collections：
  `./bin/devops-toolkit doctor --no-network --json` 返回 runtime、collections、SSH 配置、
  磁盘为 pass，网络显式跳过为 warn，进程退出码 0。
- `./tests/verify-ansible.sh`、Ruff 0.9.10、Yamllint、Actionlint、ShellCheck、
  `git diff --check` 全部通过。

## 尚未验收

真实 Ubuntu 22.04/24.04 目标的 strict host-key 行为、root/普通用户权限、
`sshd -t`、目标 OS/磁盘/网络报告未验证；不能将模拟 SSH 视为真实目标 E2E。
本地测试 Release 不等于 GitHub 签名 Release，正式资产也尚未包含本提交。
网络探针仅检查直连 TCP/443，不证明代理、TLS 或资产下载成功。
