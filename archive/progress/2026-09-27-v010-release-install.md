# v0.1.10 正式资产安装与回滚

来源提交：`571a5fef119055470d33ff478c0f69ba0524b1c5`。
[正式 Release](https://github.com/sunpcm/DevOpsToolkit/releases/tag/v0.1.10)
与 [发布流程](https://github.com/sunpcm/DevOpsToolkit/actions/runs/36262562013) 已成功，
用户实际批准受保护的 release 审批，未由测试代理绕过审批。

## 可重复证据

- [验收脚本](2026-09-27-v010-install-acceptance.sh)：SHA256
  `e9a7ca8d5044e8210cdc5ba7ccc1c89e73666102ca25b03ca853b758335f6423`。
- [完整原始输出](2026-09-27-v010-install-output.txt)：SHA256
  `87215c4d012c4374341122ef05747077b9c2c529666bf0c7d222c86dcf4f694d`。
  逐字比对临时原件相同，日志末尾 `acceptance=passed`、`final_stage=complete exit_code=0`。
- 安装器来自上述干净源码，传输前后 SHA256
  `4cc4af56e1a6e828e5386f35488b7e89065b5182a0772951face51cea356101a`。

环境：Ubuntu 24.04.5 aarch64、Python 3.12.3，独立一次性 VM。
仅在 VM 安装 python3-venv 前置依赖，以普通 ubuntu 用户执行脚本；没有执行目标 Playbook
配置主机，只对 user-only Playbook 运行 syntax-check。脚本中的代理仅用于本次隔离环境，
重跑需替换为测试网络的无凭据代理或移除代理设置。

## 实际结果

1. 正式 v0.1.9 首次安装成功，SHA256 和 Sigstore 身份验证通过。
2. 正式 v0.1.10 升级、重复安装及回滚后的前滚安装均成功，复用 core 2.21.4 runtime。
3. `current/bin/ansible-playbook --version` 解析到隔离 runtime；
   `current/bin/user-only localhost, --syntax-check -c local` 成功，doctor 所有检查 pass。
4. 两版本目录存在，以临时相对符号链接及 `mv -Tf` 原子切回 v0.1.9，
   普通用户入口返回旧版；再运行固定 v0.1.10 安装器恢复新版，旧版目录保留。
5. 暂移 `.ready` 后 current 包装器退出 1，并明确拒绝 runtime 不完整；
   恢复后再次返回 core 2.21.4。此负例覆盖标记缺失，不声称真实 VM 已覆盖标记值不符。

执行结束后确认测试 VM 无挂载/快照，只停止并永久删除
`devops-toolkit-v010-install-test-20260927`；随后 `multipass list --format json` 返回空列表。
完整日志及脚本已保留，VM 磁盘不可恢复。

独立复核结论 APPROVED：实际读取脚本/完整日志、校验摘要、核对正式资产来源和
清理空列表；可以关闭本次 Ubuntu 普通用户交付与日志缺口。边界：不覆盖 macOS sudo --system、真实 WSL2、amd64、
标签/资产替换破坏性负例或暂缓的 ACME；也不把 syntax-check 当作新一轮完整 Playbook 配置。
