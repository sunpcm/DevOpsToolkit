# P1-1 SSH 两阶段切换：本地实现与部分 VM 验证

日期：2026-09-22。实现提交：`1bb5b8c74611d6c483312826eeff9899b16b5bba`。
分支：`codex/devopstoolkit-hardening`。未推送、未发布，也未修改真实服务器。

## 实现边界

- `ubuntu-bootstrap` 在 prepare 阶段保留可信旧端口与目标新端口，SSH 配置通过 `sshd -t`
  校验后才重启；UFW 受管 profile 随后同时放行两个端口。首次连接可以是 root，后续可以是
  托管目标用户加 sudo。prepare 不新应用 root/password 禁用项。
- `ubuntu-ssh-finalize` 只接受目标普通用户从新端口进入；如需禁用密码认证，还要求显式的
  `ssh_finalize_key_verified=true`。它先收敛 SSH 到单端口，再移除 UFW 旧端口。
- 向导仅在连接私钥的公钥确实选择安装给目标用户、并选择 NOPASSWD sudo 时，自动建立第二条
  普通用户/新端口连接执行 finalize。其余路径停在可恢复的 prepare 状态。
- finalize 若在 SSH 已切换、UFW 尚未收敛时失败，不能声称旧端口仍可用；向导与文档已明确
  提醒检查实际状态和从新端口恢复。

## 验证结果

| 门槛 | 结果 |
| --- | --- |
| `./tests/verify-ansible.sh` | 通过；含 5 个 Playbook syntax check、向导、ACME、安装器和 Release 测试。 |
| `ansible-lint ansible`、`yamllint .`、Ruff、ShellCheck、Actionlint、gitleaks | 通过；仅原有软性行长 warning。 |
| Ubuntu 22.04 `ssh.service`、Ubuntu 24.04 `ssh.socket` | 本阶段早期候选在两版一次性 VM 验证 prepare→普通用户 finalize→二次 bootstrap `changed=0`；还验证 root 禁用后普通用户可重跑、端口占用拒绝和缺少密钥确认拒绝。随后收紧了 `ssh.socket` 端口归属判定，因此不能将该结果当成最终提交的完整双版本回归。 |
| 最终提交的 Ubuntu 24.04 定向回归 | Multipass Ubuntu 24.04.5 LTS，image hash `7b682958a67f`，aarch64；仅执行 SSH role。prepare 首次通过，重跑 `changed=0`；无效 `sshd` 指令在重启前失败，22/2222 仍监听，移除注入文件后再次 `changed=0`。 |
| 最终提交的完整 `multipass-smoke.sh --with-faults` | 未完成：新 VM 的 `system_base` apt cache 刷新在 5 次重试后超时；该运行尚未到达 SSH 角色。本机先前使用的测试代理端口无监听。不得将其记为功能通过。 |
| 清理 | 唯一最终测试实例 `devops-toolkit-2404-test-20260922153600-99123` 已按精确名称清理；`multipass list --format csv` 仅剩表头。 |

## 可重复验收与剩余门槛

网络恢复后，在可抛弃的 Ubuntu 22.04/24.04 VM 上执行：

```bash
./tests/multipass-smoke.sh run --with-faults
```

检查两个版本的首次收敛、普通用户新端口 finalize、二次 `changed=0`、无效 SSH 配置、端口占用、
密钥确认拒绝、UFW 与中断恢复，并记录实例名、镜像 hash、精确 Git SHA 和清理状态。当前
P1-1 仍未完整验收，`TODO.md` 保留未完成标记。生产切换仍需独立授权和备用控制台。
