# P0-3 Ansible 控制端迁移：本地实现与一次性 VM 验证

日期：2026-09-22。实现提交：`92f3421b4821c7c52e600f40e619926f3f7eb01e`，
基于此前本地发布门禁提交 `251f71d44dde281300a83200f67b1b752e780a86`。
本报告只证明本地代码与下述一次性 VM 行为；没有推送分支、运行远端 GitHub CI、创建 Release 或更改生产主机。

## 决策与实现

- 固定控制端 `ansible-core==2.21.4`，要求 Python 3.12–3.14；Ubuntu 22.04/Python 3.10
  继续作为受管目标，但不作为本机或 WSL 控制端。依据：[Ansible 支持矩阵](https://docs.ansible.com/projects/ansible/latest/reference_appendices/release_and_maintenance.html)、
  [ansible-core 2.21.4](https://pypi.org/project/ansible-core/2.21.4/)。
- 安装器在自有 `runtime/ansible-core-2.21.4` 创建 venv，验证精确版本后复用；不再对系统 Python
  执行 `pip --break-system-packages`。正式 Release 的向导和 Bash wrapper 只调用自有 Ansible 启动器；
  运行时缺失会失败，不回退到环境 PATH。
- 固定 `ansible.posix 2.2.2`、`community.general 13.4.0` 和真实 Galaxy 解析出的传递依赖
  `community.library_inventory_filtering_v1 1.1.5`。Release 包、安装器和夹具均校验这三项。
  lint 工具同步升到 `ansible-lint 26.8.0`、`yamllint 1.38.0`；旧 lint 25.1.3
  对 core 2.21.4 导入失败。

## 可重复验收与结果

控制端本地：macOS Apple Silicon、Python 3.14.6。使用临时 venv 安装 2.21.4 和三项 collections，
在隔离 `ANSIBLE_HOME` / `ANSIBLE_COLLECTIONS_PATH` 下执行：

```bash
./tests/verify-ansible.sh
ansible-lint ansible
yamllint .
ruff check bin/devops-toolkit tests/test-wizard.py AcmeConfig/libexec/acme-manager AcmeConfig/tests/test_acme_manager.py
actionlint .github/workflows/env-check.yml .github/workflows/release.yml
shellcheck install.sh scripts/build-release.sh tests/*.sh bin/ansible-playbook bin/wsl-bootstrap bin/ubuntu-bootstrap bin/user-only bin/user-only-remove
gitleaks detect --source . --redact --no-banner
git diff --check
```

以上命令退出码均为 0；`ansible-lint`/`yamllint` 仅有已有的长行 warning。
使用真实 Galaxy 下载目录执行 `DEVOPS_TOOLKIT_COLLECTIONS_SOURCE=<临时目录>
./scripts/build-release.sh v0.1.8 <临时目录>` 成功；这是本地测试 tarball，**不是** GitHub Release。
安装器 `ensure_managed_runtime` 在临时目录真实创建 venv，重复执行未改变 `.ready` 时间戳。

一次性 Multipass：Ubuntu 22.04.5 LTS 与 24.04.5 LTS，均为 arm64；控制端使用
`ansible-core 2.21.4`。VM 经无凭据的宿主机临时 HTTP 代理访问 Ubuntu/Docker 源。
命令形态：

```bash
MULTIPASS_TEST_PROXY=http://<宿主机在 VM 中可达的地址>:<端口> \
  ./tests/multipass-smoke.sh run --instance <2204-test-实例名> --instance <2404-test-实例名>
```

22.04 首次配置通过、二次 `ok=59 changed=0 unreachable=0 failed=0`；
24.04 首次 `ok=63 changed=24 failed=0`、二次 `ok=61 changed=0 unreachable=0 failed=0`。
两者的普通用户 SSH、UFW、Docker、Nginx 结果检查通过。22.04 上调用安装器的
`check_controller_python` 按预期拒绝 Python 3.10。24.04 上安装器从缺少 `ensurepip`
的系统 Python 3.12 出发，经 apt 补充 venv、sshpass 等白名单前提，在 `/opt/devops-toolkit-p03-test/runtime/`
建立 2.21.4，重复执行复用 runtime；系统 PATH 未出现全局 `ansible-playbook`。

首次 VM 尝试曾先后遇到不可写的默认 ControlPath、Mac Unix socket 长路径、VM 直连 Ubuntu 源超时；
修正为测试专用短路径和一次性 VM 代理后，上述完整 smoke 通过。最终仅对这两个精确命名测试实例执行
`multipass delete --purge <name>`，`multipass list --format csv` 只剩表头。测试 VM 数据已永久删除；
测试完成后清理了四个仅含本次测试密钥、inventory、变量和日志的临时工作目录；
这些 SSH 私钥未纳入本报告或仓库，也不可恢复。

## 尚未通过的独立门槛

- 分支未推送；GitHub Validate 在 Python 3.12 与 3.14 上的真实 CI 结果尚不存在，不能把本地验证当作远端绿灯。
- 没有新 Release、Sigstore 签名或安装升级回滚验收。当前已发布 `v0.1.7` 仍遵循其自身签名包内行为；
  本次迁移只在上述本地提交中。
- 依赖 tarball 的 SHA256 锁定属于 P1-3，当前只有精确版本和打包后 manifest 校验，不能宣称供应链完整锁定。
