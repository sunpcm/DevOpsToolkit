# P1-2：环境 loader 的 16 组实际 Shell 执行测试

日期：2026-09-23。范围：`tests/test-user-profile.py`；不修改 Ansible 实现、真实 HOME、宿主机软件或远端。

此前的 16 组矩阵只检查渲染模板是否包含预期字符串。本次在每个布尔组合下创建独立临时 HOME，放入无副作用的 uv、NVM、goenv 替身，用 `/bin/sh` 实际 source 渲染后的 `environment.sh`，再检查启用组件的可见性及未启用组件不会加载。缺失的共享 brew 仍由模板中的 `-x` 检查保护；其真实 VM 行为见 [`2026-09-23-user-profile-p1-2-vm-partial.md`](2026-09-23-user-profile-p1-2-vm-partial.md)。

验收命令：

```bash
python3 tests/test-user-profile.py
PATH=/private/tmp/devopstoolkit-p03-managed/runtime/ansible-core-2.21.4/bin:$PATH \
  ANSIBLE_COLLECTIONS_PATH=/private/tmp/devopstoolkit-p14.hcJpFA/collections \
  ANSIBLE_LOCAL_TEMP=/private/tmp/devopstoolkit-p1-2-verify \
  ./tests/verify-ansible.sh
git diff --check
```

`python3 tests/test-user-profile.py` 通过。完整门禁首次在普通沙箱中因 Ansible 本地 RPC 无法启动而中断；允许本地进程通信后用相同隔离 runtime 重跑，通过并输出“统一 Ansible 入口静态验证通过”。未安装 Ruff，因此没有声称单独的 Ruff 检查通过。

此测试验证的是 loader 的运行语义与开关独立性，不验证真实 Node/Go/uv 安装、新登录 Zsh、Ubuntu 22.04/24.04 的所有组合或第二次 Ansible `changed=0`；P1-2 仍开放。
