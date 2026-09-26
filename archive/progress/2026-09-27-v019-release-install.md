# v0.1.9 正式 Release 与普通用户升级回滚验收

验收发生于 2026-09-26，归档于 2026-09-27。
正式标签指向 `86466259d3632d224e655b66be56e65240a252f0`；
[Release 工作流](https://github.com/sunpcm/DevOpsToolkit/actions/runs/36249900289)
包含 quality、Python 3.12/3.14、发布专用 validate 与 release，均成功。
发布前实际观察到 release Environment 的 waiting 状态及 sunpcm 审批人；
随后工作流完成。此记录不声称对资产替换或标签删除进行了破坏性试验。

## 正式资产

[v0.1.9](https://github.com/sunpcm/DevOpsToolkit/releases/tag/v0.1.9)
为非草稿、非预发布，发布时间 `2026-09-26T15:02:31Z`，说明包含精确 Source commit。
下载的三份资产与 GitHub 公布 digest 一致：

- tar.gz：`b03cf59e52a938f3617487a79182e25641da0918fdacdeff496b1a0a10d84861`
- sha256：`8a5b3d2c20f58a2ef5d663e27a367c144c9339eb2b0b2eedd274402a649c8faa`
- sigstore.json：`a839f7f2968339e11c76fe3f82e7b524171f2e6b3545ddece2a1a8577e1abd14`

`shasum -a 256 -c` 通过；包内 VERSION 为 v0.1.9。三项 bundled collections 为
ansible.posix 2.2.2、community.general 13.4.0、community.library_inventory_filtering_v1 1.1.5。
安装器、向导及 ubuntu/user-only/wsl 包装入口的能力输出均返回 schema 1 和正确基线；
安装器 version 为 null，包内向导及包装入口 version 为 v0.1.9。

## 一次性 VM 安装与回滚

证据限制：下述过程依据本线程逐条命令执行输出整理，未另存完整原始安装日志。
VM 已清理，独立复核无法回查该实例；本摘要不应单独用于关闭要求独立原始日志的门槛。
后续交付验收必须在运行时归档完整日志及退出码，不能事后以摘要替代。

用户明确许可后创建独立 Ubuntu 24.04.5 aarch64 VM，Python 3.12.3；
镜像 hash 为 `7b682958a67ff5de068e36de6af8b75fa645d296af5a70d6500527f6a33781db`。
只在 VM 中安装 python3-venv 及其依赖，未在 macOS 安装软件。
从正式包传入的 install.sh SHA256 为
`4cc4af56e1a6e828e5386f35488b7e89065b5182a0772951face51cea356101a`，传输后相同。
安装命令为 `bash /home/ubuntu/devops-toolkit-install.sh --user --no-run --version VERSION`，
通过临时代理访问上游；VERSION 先 v0.1.7 后 v0.1.9。

1. v0.1.7 首次安装退出 0，SHA256 和 Sigstore 身份验证通过（Verified OK），
   创建隔离 ansible-core 2.21.4；普通用户入口返回 v0.1.7。
2. 升级 v0.1.9 退出 0，同样验签通过并复用 runtime；current 指向 releases/v0.1.9，
   两版目录均保留且由 ubuntu 持有。
3. 重复固定安装 v0.1.9 退出 0，验签通过并复用 runtime。
4. 检查两版目录后，以临时相对符号链接和 os.replace 原子切回 v0.1.7；
   普通用户入口返回 v0.1.7，v0.1.9 目录仍可读回新版。
5. 固定安装 v0.1.9 再次验签通过，完成前滚；入口与 current 均恢复新版，旧版保留。
6. 向导 doctor --json 返回 pass；实际 release 目录的 Ansible 包装器返回 core 2.21.4。

结束后仅删除本次命名 VM `devops-toolkit-v019-install-20260926`，无挂载或快照；
`multipass list --format json` 返回空列表。该临时测试磁盘已永久清理。

## 实测发现与未完成边界

v0.1.9 经 current/bin/user-only 调用 syntax-check 退出 127，因 Ansible 包装器
将逻辑路径 current 误判为源码 checkout，回退查找系统 Ansible；
从 releases/v0.1.9/bin/user-only 调用相同 syntax-check 则退出 0。
向导入口使用 Python resolve，因此本次普通用户安装和版本切换通过，不应扩大为全部包装入口通过。

[PR #11](https://github.com/sunpcm/DevOpsToolkit/pull/11) 使用物理路径解析修复该问题，
新增 current 入口及损坏 runtime 标记的正反向测试。独立代码 Review APPROVED，
完整静态门禁通过；VM 独立测试目录的修复包装器返回 core 2.21.4。
该修复尚不在不可变 v0.1.9 资产中，不能宣称正式 Release 已修复。

未覆盖 macOS sudo --system、真实 WSL2、amd64、暂缓 ACME 真实 CA；
未执行生产部署、已发布资产替换、标签更新或删除。
