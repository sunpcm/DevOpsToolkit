# P1-1 SSH 负例补测：本地代码与待复跑 VM 边界

日期：2026-09-23。分支：`codex/devopstoolkit-hardening`。
代码提交：`89a6111`、`52a70db`。未推送、未发布，未触及生产主机。

## 新增覆盖

`tests/multipass-smoke.sh run --with-faults` 在两个一次性 Ubuntu VM 中新增：

- prepare 后带 `ssh_finalize_key_verified=false` 请求 finalize，必须在改端口前拒绝，
  并确认旧 root SSH 连接仍可达；之后再用已验证密钥从普通用户新端口 finalize。
- 已收敛后在另一个端口启动临时 HTTP 服务，再尝试把 SSH 迁往该端口；必须以
  `Refusing to move SSH to occupied port` 拒绝，并确认原 SSH 连接仍可达。

此处测试的是“密钥确认标记缺失”和“端口由别的服务占用”；不能替代真实错误密钥、
主机防火墙独立故障或生产控制台恢复演练。

## 本地验证和未完成项

- `shellcheck tests/multipass-smoke.sh`、`bash -n tests/multipass-smoke.sh`、
  `./tests/test-multipass-report.sh`、`actionlint`、`git diff --check` 通过。
- 使用 Python 3.14 的隔离 `ansible-core==2.21.4` 与通过
  `scripts/verify-collection-lock.py --installed` 校验的三项 collection 执行
  `./tests/verify-ansible.sh`，退出码 0。
- `multipass list --format json` 返回空列表；本轮没有新建 VM，也没有删除 VM。
- 宿主代理 `*.7897` 虽监听，但通过该代理访问 GitHub 与 Docker 官方 HTTPS URL
  均在约 5 秒 SSL 建连阶段超时。本轮未启动会依赖 Docker/apt 下载的完整 VM smoke。
  网络恢复后必须从干净提交重跑两版 `--with-faults`，报告需为 `result=passed`、
  `source_dirty=false`、`cleanup_status=passed`，并独立复查实例列表为空。

此前 `f40192f` 的双版本 E2E 证据仍有效，但运行在新增两个负例之前，不能证明它们已通过。
