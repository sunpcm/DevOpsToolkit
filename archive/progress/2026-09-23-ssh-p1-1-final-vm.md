# P1-1 两阶段 SSH 主路径本地 VM 验收

日期：2026-09-23。源码：干净提交 `0704fbb8fd297bce4b98c8685bca37b669539bc9`，
macOS arm64 控制端、ansible-core 2.21.4、Multipass Ubuntu 22.04.5 / 24.04.5
arm64 一次性实例。未推送、未发布、未触及生产主机。

机器可读报告快照：
[`2026-09-23-ssh-p1-1-final-vm.report`](2026-09-23-ssh-p1-1-final-vm.report)。
原始本地报告：`/private/tmp/devops-toolkit-p11-pinned.yz7pxs/report.txt`。

执行命令（`PATH` 与 `ANSIBLE_COLLECTIONS_PATH` 指向已存在、已验证的隔离 runtime 与
collections；未在宿主安装新组件）：

```bash
MULTIPASS_TEST_HOSTS='ports.ubuntu.com=91.189.92.19,download.docker.com=3.169.231.109' \
  ./tests/multipass-smoke.sh run --with-faults --report /private/tmp/devops-toolkit-p11-pinned.yz7pxs/report.txt
python3 scripts/verify-vm-evidence.py verify-report \
  --report /private/tmp/devops-toolkit-p11-pinned.yz7pxs/report.txt \
  --sha 0704fbb8fd297bce4b98c8685bca37b669539bc9
multipass list --format json
```

官方域名 IP 在运行前由官方域名的公共 DNS 结果复核，只作用于一次性 VM 的 hosts 文件，
不修改宿主 DNS。报告校验器退出码 0；测试脚本退出码 0；结束后实例列表为空。

两版均通过：首次配置、错误私钥的真实认证拒绝且旧 root 端口仍可达、未确认密钥标记被
拒绝、从目标普通用户新端口执行 finalize、二次 bootstrap `changed=0`、SSH/UFW/
Docker/Nginx 检查、无效 sshd 配置、新端口占用、陈旧 UFW profile 与旧 Docker APT 源
恢复、部分账户状态后的完整重跑与再次 `changed=0`。最后显式禁用 root 登录，验证
`sshd -T` 的有效设置、root 密钥登录被拒及普通用户仍可 `sudo`。22.04 走传统
`ssh.service`，24.04 走 `ssh.socket`。

本轮还验证 Docker Ubuntu APT 公钥首次下载与固定 SHA256 `1500c1f56fa9e26b9b8f42452a553675796ade0807cdce11975eb98170b3a570`
一致，随后本地文件摘要匹配时重复运行不再因公钥下载站偶发断连而失败。摘要从
Docker 官方 HTTPS URL 两次独立获取相同字节，公钥指纹为
`9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88`。轮换时须重新核对并更新固定摘要。

边界：本次 `test_uv=0`；不是 PR runner、GitHub Release、真实生产主机或生产
SSH/防火墙回滚演练。尤其没有在 finalize 已切换 SSH、随后 UFW 更新之前注入失败；
该窗口的旧端口/认证方式回退尚未验证，P1-1 仍开放。P1-4 远端计划任务和 Release gate
也需独立验收。
