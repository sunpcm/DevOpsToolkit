# P2 机器可读版本与能力：本地实现证据

日期：2026-09-23。代码提交：`1d54e74`。分支：`codex/devopstoolkit-hardening`。
仅本地代码、测试和文档；未推送、未发布，也未探测生产节点。

## 协议

- `install.sh --capabilities-json` 在平台、权限、下载及安装动作前输出 `schema=1`
  JSON。独立脚本没有已安装版本，故 `version=null`；报告安装模式、控制端范围、固定
  ansible-core 和资产校验方式。
- `bin/devops-toolkit --capabilities-json` 与五个 Playbook 包装入口输出同一 schema；
  源码版本为 `development`，Release 包从 `VERSION` 读取 tag。固定 collection 版本从
  `ansible/collections.lock.json` 读取。包装入口额外标明具体 `entrypoint`。
- 该协议是声明的支持范围，不是目标节点健康检查。未把平台预检、runtime 状态或实际
  软件安装结果伪装为已验证；这些属于后续只读 doctor 和真实 VM/Release 门槛。

## 验证

- `python3 tests/test-capabilities.py`：所有入口、schema、字段一致性和非法参数拒绝通过。
- `./tests/test-release.sh`：本地构建的测试 Release 解包后，向导与 Ubuntu 包装入口均报告
  `v0.1.0`，而非 `development`。
- `./tests/test-installer.sh`、ShellCheck、Ruff 0.9.10、Actionlint、Yamllint、
  `git diff --check` 均通过。
- 使用隔离的 `ansible-core==2.21.4` 与经 lock 验证的 collections 执行
  `./tests/verify-ansible.sh`，退出码 0。

正式 GitHub Release 资产尚未包含本提交；`TODO.md` 中的远端版本输出验收保持开放。
