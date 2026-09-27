# 合并后检查与剩余验收条件

## 当前状态

`571a5fef119055470d33ff478c0f69ba0524b1c5` 的静态门禁、双版本 VM 与独立复核
均已通过；`v0.1.10` 已授权推送并经用户批准 release 审批后正式发布，Ubuntu 普通用户
安装/升级/回滚及 current 入口交付已独立复核通过；其他平台与保护负例仍开放。
临时 runtime 安装已获授权并完成。本文下列各阶段段落按时间顺序保留当时快照，
其中“尚未”“待授权”“运行中”描述的是该阶段当时状态，不代表当前状态。

## 已核实

- PR #10 合并提交：`c9b7328c1279308e9c68830f592b1ff25581c17f`。
- PR #11 合并提交：`571a5fef119055470d33ff478c0f69ba0524b1c5`。
- [主线 Validate](https://github.com/sunpcm/DevOpsToolkit/actions/runs/36260854347)
  已完成且成功，包含 quality、Python 3.12/3.14 验证。
- 这不是正式 Release 或同 SHA 双版本 VM 验收证据。

## macOS 系统安装前置条件（只读检查）

检查命令：

```sh
uname -s
uname -m
/usr/bin/python3 --version
python3 --version
stat -f '%Su %Sp %N' /opt /opt/homebrew /opt/homebrew/bin /opt/homebrew/bin/python3 /usr/bin/python3
sudo -n true
multipass list
```

结果：Darwin arm64；系统 Python 3.9.6，不符合控制端 3.12–3.14。
Homebrew Python 3.14.6 的目录及链接由普通用户持有，不能作为 root 系统安装的
可信解释器；安装器会拒绝该路径，不能通过修改信任检查绕过。
非交互 sudo 返回需要密码；Multipass 无实例。

本次没有安装软件、修改权限或系统目录。应另行授权准备受控 Mac 与 root 持有、
普通用户不可写的受支持 Python；不应为了测试更改 Homebrew 的所有权。

## 初次检查时尚缺的授权与环境（历史快照）

- 新标签发布授权：拟使用 `v0.1.10`，来源 SHA 为上述 PR #11 合并提交；
  必须先完成当次双版本 VM、独立复核及完整日志归档，再走受保护发布审批。
- 真实 WSL2 Ubuntu 24.04 环境。
- 标签更新/删除、Release 资产替换的破坏性负例授权与隔离测试目标。
- 正式资产安装、升级、回滚完整原始日志及退出码；历史输出摘要不能替代原件。

ACME 真实 CA 与独立仓库迁移继续按约定暂缓。这些条件未满足时，目标不能标记完成。

## 新候选验收中止记录（历史快照）

已获授权在验收和独立复核通过后对 `571a5fef119055470d33ff478c0f69ba0524b1c5`
创建并推送 `v0.1.10`。本次尚未创建标签。

2026-09-26T18:04:13Z 至 18:06:19Z 的 VM 测试因控制端环境漂移主动中止：
旧临时 runtime 不完整，PATH 查找实际落到系统 ansible-core 2.21.2，
不符合要求的 2.21.4。该轮不得作为发布通过证据。
报告 `result=failed`、`source_dirty=false`、`ansible_core=2.21.2`、
`cleanup_status=passed`；测试进程退出码 143，之后 `multipass list` 确认无实例。

原始文件保留于 `/private/tmp/devopstoolkit-v010-571a5fe-evidence/`：
`vm.report`、`vm.log`、`verify.log`。临时目录不是长期归档。
本地静态门禁退出码 1，原因是所选 Python 环境缺少 PyYAML，
不能记为完整门禁通过，也未据此判定产品代码失败。

随后在隔离文档工作区补充 VM 启动前版本校验（尚未提交）：
版本从安装器锁定常量读取，不一致时在创建实例前拒绝；
报告边界回归、ShellCheck 和 `git diff --check` 均退出码 0。
这项本地改动不改变已授权的候选 SHA。重新验收前需要用户批准
在新建临时 venv 中安装 ansible-core 2.21.4；不得擅自修改系统 Python 或 Homebrew。

## 授权恢复与静态门禁通过（阶段快照与后续结果）

用户随后明确授权安装临时测试 runtime。新环境位于
`/private/tmp/devopstoolkit-v010-runtime.ZoSPMq/runtime`，使用 Python 3.14.6，
已实际确认 ansible-core 2.21.4、PyYAML 6.0.3；安装不使用 sudo，未修改系统 Python 或 Homebrew。
安装输出保留于同级 `install.log`。

在干净的已授权 SHA 上，执行：

```sh
env PATH=/private/tmp/devopstoolkit-v010-runtime.ZoSPMq/runtime/bin:$PATH \
  ANSIBLE_COLLECTIONS_PATH=/private/tmp/devopstoolkit-p14.hcJpFA/collections \
  ./tests/verify-ansible.sh
```

退出码 0；完整输出保留于 `evidence/verify.log`。测试后源码仍干净。
以该新 runtime 重启双版本 VM 验收，报告路径为 `evidence/vm.report`，
日志路径为 `evidence/vm.log`；此记录时仍运行中，不构成 VM 通过或 Release 完成。

阶段性输出确认：Ubuntu 22.04 主路径二次运行 `ok=73 changed=0 unreachable=0 failed=0`；
旧 Docker APT 源/UFW 冲突恢复、被占用端口拒绝及部分账户状态后的完整重跑通过，
恢复后的再次运行同样 `changed=0 failed=0`。此时仍在执行禁用 root 登录检查，
Ubuntu 24.04 和最终清理未完成，不能将部分结果记为双版本验收通过。

后续输出已确认流程完成 22.04 最后的 root 登录禁用检查并进入 Ubuntu 24.04.5 LTS
（aarch64，镜像摘要前缀 `7b682958a67f`）首次配置；24.04 与清理门槛仍开放。
静态门禁完整日志 SHA256：
`a9fd411f6606f97be3ed03bdad02f67344b96fbfe9c4b33d719b96625bc2afd0`。
临时 runtime 的 `pip check` 退出码 0（No broken requirements found）。

最终 VM 测试退出码 0，运行时间为 2026-09-26T18:12:03Z 至 18:25:12Z。
最终报告 `result=passed`、`last_stage=complete`、`cleanup_status=passed`，
来源精确 SHA、干净状态、core 2.21.4、双实例和 uv/故障开关均匹配。
报告校验脚本退出码 0；结束后重新运行 `multipass list --format json` 确认空列表。
最终报告 SHA256：`3a671d6d4634866a7792f7abd84f14121544d3fd1bf04b9e1ad4df1fd15da64c`。
24.04 主路径和故障恢复后二次运行均为 `ok=75 changed=0 unreachable=0 failed=0`。
已交由现有独立复核任务只读复核，尚未收到结论，尚未创建标签。

最终报告已逐字归档为
[`2026-09-27-release-vm-571a5fe.report`](2026-09-27-release-vm-571a5fe.report)，
`cmp` 与临时原件完全相同，SHA256 如上。完整运行日志 SHA256：
`5395aa93f2817e19070d42b06be184b816fe34bcfd3d5fc9bf5b54048322aaff`。
归档尚未提交，独立复核仍须读取原始日志，不能仅依赖此摘要。

后续独立复核结论为 APPROVED：复核者实际读取日志、校验报告、核对干净源码、
双版本系统、core 2.21.4、零变更与故障恢复，并查询实例为空；批准范围仅限该精确 SHA
的发布前证据，不关闭正式资产安装/回滚门槛。
随后按用户授权创建 annotated tag `v0.1.10` 并通过临时 HTTPS 凭据助手推送成功，
未修改全局 Git 认证设置。尚待发布 workflow 和受保护审批，不代表 Release 已完成。

2026-09-27 用户明确表示已批准 release；只读核查
[Release run 36262562013](https://github.com/sunpcm/DevOpsToolkit/actions/runs/36262562013)
全部五项任务成功，正式 Release 非 draft、非 prerelease，发布时间 2026-09-27T11:54:39Z，
正文 Source commit 与精确候选 SHA 一致。三个正式资产已生成，正在独立下载校验。
这些结果不关闭正式资产安装/回滚或其他平台验收门槛。

正式资产已独立下载，三项 SHA256 与 GitHub digest 一致：

- tar.gz：`87bf4ed567f27fa38830f112c4562c22f1a9716e1d3fba1fd99832eed36cca96`
- sha256：`665a28f46dc1085186ed54ed63ac3e50dd9dd739e67da60d4e0d6fc1e02d280e`
- sigstore.json：`69be405136a8c516408ff342eff5f198d391e5927429dd1e33c48b7a815e17d7`

校验文件检查退出码 0，发布日志 Verify Sigstore identity 显示 Verified OK。
独立安装测试 VM `devops-toolkit-v010-install-test-20260927` 已启动，
Ubuntu 24.04.5 aarch64、无挂载/快照，VM 内 python3-venv 前置依赖安装退出码 0。
从精确候选源码传入安装器，传输前后 SHA256 均为
`4cc4af56e1a6e828e5386f35488b7e89065b5182a0772951face51cea356101a`。
验收脚本通过 bash syntax/ShellCheck，开始以普通用户执行正式升级/回滚；
脚本和完整日志位于 `/private/tmp/devopstoolkit-v010-runtime.ZoSPMq/`，
当前未完成，VM 尚未清理，不作为通过证据。
