# P1-5 系统安装所有权缺陷与修复

日期：2026-09-23

## 发现

在无快照、无挂载的一次性 Ubuntu 24.04.5/aarch64 VM（镜像 `7b682958a67f`）中，用当前
安装器从 GitHub 的真实 `v0.1.4` Release 安装到 `/opt/devops-toolkit`。三个资产齐全；
下载、SHA256、Sigstore GitHub Actions 身份校验及隔离 `ansible-core==2.21.4` runtime 创建通过，
普通 `ubuntu` 用户运行 `/usr/local/bin/devops-toolkit --version` 得到 `v0.1.4`。

但 `stat -c '%u:%g %a %n'` 显示 Release 目录及入口为 `1001:1001 755`，而不是 root 持有。
若目标主机上存在 UID 1001 用户，该用户可以改写系统安装的可执行代码，破坏签名验证之后的
安装完整性。因此暂停升级/回滚测试；该 VM 已核对无挂载/快照并删除，实例列表为空。

## 修复与验证边界

安装器现在忽略归档内 CI 的数字 UID/GID，把解压成员绑定到执行安装的用户，并移除 setuid、
setgid、sticky 与组/其他用户写权限。系统模式将 staging 统一改为 `0:0`，在复用既有版本时
拒绝非 root 所有、组/其他用户可写及符号链接内容；发布前再检查一次。系统安装根目录和
`releases` 目录也必须是非符号链接、root 所有且不可由组/其他用户写入。

`tests/test-installer.sh` 新增带 world-writable 归档成员的夹具，验证安装后写权限收敛；
仓库完整 `./tests/verify-ansible.sh` 与 ShellCheck 均通过。

尚需从修复后的干净提交重跑真实 VM：旧版安装、重复安装、latest 升级、固定版本安装、
普通用户入口、旧版本保留及手工原子回滚。当前本地单测不能代替这组证据。
