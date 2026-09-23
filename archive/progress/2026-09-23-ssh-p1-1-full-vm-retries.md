# P1-1 / P1-4 双版本完整 VM 复跑记录（2026-09-23）

## 范围与命令

控制端：macOS arm64、ansible-core 2.21.4；目标：Multipass Ubuntu 22.04.5 / 24.04.5
arm64 一次性 VM。使用 `tests/multipass-smoke.sh run --with-faults --report <临时报告路径>`，
并仅对 `ports.ubuntu.com`、`download.docker.com` 使用经官方 DNS 核对的临时公网 IPv4
覆盖。覆盖只存在于一次性 VM 内，不修改宿主 DNS。

每轮 `./tests/verify-ansible.sh`、ShellCheck、报告边界测试通过。测试实例在失败后均被
脚本清理；最终 `multipass list --format json` 返回空列表。没有推送或发布。

## 结果与修复

| 源 SHA | 双版本结果 | 最后阶段 / 证据 | 处理 |
| --- | --- | --- | --- |
| `15da9be` | 失败 | 22.04 `unverified-key`；旧 SSH 端口检查报 `Host key verification failed`，`cleanup_status=passed` | 测试扫描新端口时覆盖了旧端口 `known_hosts`，由 `420288f` 改为追加 |
| `420288f` | 失败 | 22.04 完整通过，包括首次收敛、二次 `changed=0`、普通用户新端口、SSH/UFW/Docker/Nginx 与全部故障注入；24.04 二次 `changed=0`、服务检查及前三项故障注入通过，在 `interrupted-bootstrap` 失败；`cleanup_status=passed` | 首次恢复执行原先吞掉输出；`0570b27` 增加有限诊断和细分阶段，尚未证明失败根因 |
| `0570b27` | 失败 | 22.04 首次收敛、二次 `changed=0`、普通用户新端口及服务检查通过，在 `firewall-recovery` 失败；`cleanup_status=passed`。未运行到 24.04 | 该恢复执行原先也吞掉输出；`61e2187` 增加 SSH/UFW 恢复失败时的有限日志摘要，尚未证明失败根因 |

三个报告分别位于：

- `/private/tmp/devops-toolkit-p11-rerun.76z9Z7/report.txt`
- `/private/tmp/devops-toolkit-p11-fixed.kjKTsp/report.txt`
- `/private/tmp/devops-toolkit-p11-diagnostic.AThof7/report.txt`

`61e2187` 的完整静态门禁通过，但尚未在该 SHA 上取得完整双版本 VM 通过报告。
复跑中 Docker 签名密钥下载曾短暂重试后成功；不能据此断定后续失败就是网络问题。
P1-1 的最终双版本故障注入门槛与 P1-4 的可重复 VM gate 继续保持开放。

## 下一步

在 apt / Docker 官方域名访问稳定时，使用干净提交重新运行完整命令。若失败，依据
`last_stage` 与新增的有限恢复日志定位具体 Ansible 任务；不得用早期一次成功的单版本
结果或静态检查代替最终双版本验收。
