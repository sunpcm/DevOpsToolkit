# P1-2：干净 HOME 的部分真实 VM 验证

日期：2026-09-23。源码提交：`5fc8fcc502fc8132dccb26ce92645dfaf31b56ff`。
本轮未修改 Ansible 实现、未推送、未发布，也未安装宿主机软件。

## 环境与边界

- 一次性 Multipass 实例：`devops-toolkit-2404-test-20260923191500-7319`，Ubuntu 24.04.5 LTS，镜像 hash `7b682958a67ff5de068e36de6af8b75fa645d296af5a70d6500527f6a33781db`。
- 宿主控制端：隔离 `ansible-core 2.21.4`；collection 路径 `/private/tmp/devopstoolkit-p14.hcJpFA/collections`。
- VM 中创建无 sudo 的 `p1brew`、`p1shell` 两个全新 HOME。SSH 使用本轮临时 Ed25519 密钥；通过 Multipass 内的主机公钥指纹核对 `ssh-keyscan` 结果后，使用独立 `known_hosts`，没有关闭 host-key checking。
- VM 基础镜像提供 `git`、`curl`、`bash`、`tar`，缺少 `zsh`、`cc`、`make`。本轮未运行 apt。
- 清理前 `multipass list --format json` 仅显示该实例；随后按精确名称执行 `multipass stop --force`、`multipass delete --purge`。清理后列表为空。

## 执行与结果

在临时 inventory 的 `[user_only]` 组中，分别连接 `p1brew`、`p1shell`。主机地址、私钥和 `known_hosts` 指向该次 VM；运行时环境为：

```bash
export PATH=/private/tmp/devopstoolkit-p03-managed/runtime/ansible-core-2.21.4/bin:$PATH
export ANSIBLE_COLLECTIONS_PATH=/private/tmp/devopstoolkit-p14.hcJpFA/collections
export ANSIBLE_CONFIG=/Users/sunpcm/code/DevOpsToolkit/ansible/ansible.cfg
export ANSIBLE_LOCAL_TEMP=/private/tmp/devopstoolkit-p1-2.DrM2Si/ansible-local
```

对 `p1brew` 的干净 HOME，`configure_shell=false`、`install_oh_my_zsh=false`、`configure_git=false`、`configure_uv=false`、`configure_node=false`、`configure_go=false`、`configure_homebrew_environment=true`：

```bash
ansible-playbook -i /private/tmp/devopstoolkit-p1-2.DrM2Si/inventory.ini \
  --limit p1brew ansible/playbooks/user-only.yml \
  -e '{"configure_shell":false,"install_oh_my_zsh":false,"configure_git":false,"configure_uv":false,"configure_node":false,"configure_go":false,"configure_homebrew_environment":true}'
```

首次 recap `ok=23 changed=5 unreachable=0 failed=0`；明确输出共享 brew 不存在、保留带可执行文件判断的 loader。第二次同命令 `ok=24 changed=0 unreachable=0 failed=0`。新登录 Bash 中确认 HOME 正确、受管 environment 文件可读、brew loader 存在且不会执行不存在的 brew，未选的 NVM、goenv、uv loader 不在模板中。

随后对同一账户关闭全部组件（将上条命令的 `configure_homebrew_environment` 改为 `false`）：首次 `ok=22 changed=3 failed=0`，再次 `ok=22 changed=0 failed=0`。新登录 Bash 中 `.profile` 和 `.zshrc` 仍存在；受管 environment 文件及两个文件中的受管 loader 均已移除。

对 `p1shell` 的干净 HOME，仅设置 `configure_shell=true`，其余组件关闭，且保持 `user_only_allow_system_dependencies=false`：

```bash
ansible-playbook -i /private/tmp/devopstoolkit-p1-2.DrM2Si/inventory.ini \
  --limit p1shell ansible/playbooks/user-only.yml \
  -e '{"configure_shell":true,"install_oh_my_zsh":false,"configure_git":false,"configure_uv":false,"configure_node":false,"configure_go":false,"configure_homebrew_environment":false}'
```

依赖重检后按预期因 `zsh` 缺失而失败：recap `changed=0 failed=1`，错误明确列出 `zsh`。SSH 只读检查证明受管配置目录与 `.zshrc` 均未产生，即依赖预检在修改 HOME 前 fail closed。

## 尚未证明

真实 uv 官方产物请求在 GitHub 302 重定向后于 20 秒超时；这只证明 VM 到 release asset 的当前网络路径不可用，不证明 uv 实现通过或失败。Node、Go、Oh My Zsh、共享 brew 存在时的加载、允许 apt 后的命令重检，以及 Ubuntu 22.04 干净 HOME 两次收敛，仍需独立验证。P1-2 继续保持开放，不以本轮局部结果替代完整组合矩阵。
