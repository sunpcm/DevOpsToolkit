# P1-1 SSH finalize 失败保活门槛：双版本 VM 验收

日期：2026-09-23。源码为干净提交 `ca1925c7c2b36372caeb512a8eadcd450de1bbcf`。
macOS arm64 控制端使用现有的 ansible-core 2.21.4 与已验证 collections，目标是
Multipass Ubuntu 22.04.5 `ssh.service` 和 Ubuntu 24.04.5 `ssh.socket` 的一次性
arm64 VM。未推送、未发布，也未操作生产主机。

执行 `tests/multipass-smoke.sh run --with-faults --report <临时路径>`；报告快照见
[`2026-09-23-ssh-p1-1-guard-final.report`](2026-09-23-ssh-p1-1-guard-final.report)，
原始报告为 `/private/tmp/devops-toolkit-p11-guard-close.FJdc7X/report.txt`。
运行前核对官方 DNS，临时 hosts 覆盖仅写入可抛弃 VM。

`scripts/verify-vm-evidence.py verify-report --report <原始报告> --sha ca1925c7c2b36372caeb512a8eadcd450de1bbcf`
退出码 0；测试脚本退出码 0。报告为 `result=passed`、`source_dirty=false`、
`last_stage=complete`、`cleanup_status=passed`。独立执行 `multipass list --format json`
返回空列表。

两版均在 SSH handler 完成、主 UFW profile 尚未更新时注入受控失败，并确认：

- 失败任务与可执行恢复提示出现，新的普通用户 SSH 连接由控制端重新建立且 `sudo` 可用；
- 实际 SSH 只监听新端口；有效设置为 `passwordauthentication no`；UFW 仍启用；
- 主 profile 尚保留旧端口，独立的 `DevOpsToolkitSSHFinalizeGuard` profile 与 allow
  规则保护新端口；
- 不带注入参数重跑 finalize 后，临时 profile 与规则均清理；第二次完整 bootstrap
  为 `changed=0`；其他 SSH/UFW/端口占用/中断恢复负例仍通过；
- 未确认密钥时，在任何 guard 写入前拒绝；最后显式禁用 root 登录，普通用户仍可管理。

实现选择的是 TODO 允许的“保持一个独立验证的新连接并给出恢复命令”，不是保证旧 root
端口在 SSH 收敛后仍能登录。若 guard 清理自身失败，主 profile 和新连接已先行验证；
不应声称 guard 一定仍存在。真实生产 SSH 切换、备用控制台、远端 PR runner 与
Release gate 需要单独授权和验收；本轮 `test_uv=0`。
