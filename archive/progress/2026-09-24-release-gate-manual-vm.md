# 发布门禁改为一次性 VM + 人工审批

日期：2026-09-24。修改前本地 HEAD：`edbffb4`，工作树干净；远端仓库为公开的
`sunpcm/DevOpsToolkit`。用户决定放弃每周自托管 Multipass runner，改为每次发布前手工
一次性 VM 验收，再由受保护的 GitHub `release` Environment 审批。

## 本地实现与验证

- 删除 `.github/workflows/vm-smoke.yml`；Release 不再查询同 SHA runner artifact。
- Release 仍在 tag SHA 上执行完整 Validate、main 祖先检查、锁定 collection 验证和签名；
  `release` job 在获得写权限与 OIDC 签名身份前须等待 Environment 审批。
- `scripts/verify-vm-evidence.py verify-report --report REPORT --sha SHA` 检查手工报告的
  同 SHA、8 天内时间、双 Ubuntu 镜像、Ansible 版本、故障覆盖、干净来源和成功清理。
- `docs/RELEASING.md` 给出每次发布的手工命令、原始报告与 SHA256 保存及审批核对项。
  GitHub 无法自动证明本地报告真实性，这是单维护者人工验收的明示边界。
- 预装的 Ansible Python 环境运行 `./tests/verify-ansible.sh` 通过；原始命令在沙箱内先因
  Python 缺 PyYAML、后因 Ansible 临时 RPC socket 受限失败，均非代码失败；未安装新组件。
- `actionlint .github/workflows/release.yml`、`shellcheck tests/verify-ansible.sh
  tests/test-release.sh`、`tests/test-vm-evidence.py` 和 `git diff --check` 通过。

## GitHub 控制面（只读回查）

使用用户已重新认证的 `gh`，先只读确认无 ruleset、空 `release` Environment、immutable
关闭、Actions `allowed_actions=all` 且未强制 SHA pin。随后小步配置并回查：

| 控制项 | 2026-09-24 回查结果 |
| --- | --- |
| `main` ruleset | ID `23913370`，active，`refs/heads/main`，禁止 deletion/non-fast-forward，无 bypass；必需 CI 检查待新矩阵远端运行后配置。 |
| `v*` tag ruleset | ID `23913374`，active，`refs/tags/v*`，禁止 update/deletion，无 bypass；单维护者仓库当前只有管理员可写，新 tag 创建未另设阻断规则。 |
| `release` Environment | required reviewer 为 `sunpcm`，`prevent_self_review=false`、`can_admins_bypass=false`；仅 `v*` tag 可部署；这是不可强制绕过的人工暂停点，不是第二人独立复核。 |
| Immutable releases | `enabled=true`，不追溯改变历史 Release。 |
| Actions | `allowed_actions=selected`、`sha_pinning_required=true`；仅 GitHub-owned Action，非 GitHub verified 和自定义 pattern 均关闭。 |
| Dependabot | vulnerability-alerts 返回 HTTP 204；security updates `enabled=true, paused=false`。 |

未创建 tag、Release、PR，也未推送分支。远端尚未运行新 workflow，因此审批 UI、同 SHA
Python 3.12/3.14、签名构建、不可变资产和安装/回滚仍待新版本真实验收。审批人不得以本文
替代每次发布时新生成的同 SHA VM 报告。

## 后续远端 CI 与规则更新

上述“未推送”的描述仅是首次配置完成时的快照。随后推送了开发分支并创建
[草稿 PR #2](https://github.com/sunpcm/DevOpsToolkit/pull/2)，未合并、未创建 tag 或 Release。
首个 `232bd2c` 的双 Python 验证通过，但 quality 因 `tests/multipass-smoke.sh` 的
ShellCheck `SC2119/SC2120` 失败；修正调用方式后，`ec06cc4abaa6918c44026b6f4c76e254285d954a`
的 [push Validate](https://github.com/sunpcm/DevOpsToolkit/actions/runs/35946546136) 与
[PR Validate](https://github.com/sunpcm/DevOpsToolkit/actions/runs/35946597109) 均成功，
包括 quality、Python 3.12/3.14 + core 2.21.4。修复后本地完整
`./tests/verify-ansible.sh` 与全部活跃 Shell 脚本的 ShellCheck 亦通过。

确认真实 check 名称及来源 GitHub Actions App ID `15368` 后，更新 `main` ruleset
`23913370`：要求 `quality`、`validate (3.12, 2.21.4)`、
`validate (3.14, 2.21.4)`，启用 strict latest-code policy，保留 deletion/non-fast-forward
保护且无 bypass。该规则尚未通过真实合并验证，不能把 API 回查等同于实际阻断测试。
另一次只读回查发现 `release` Environment 起初允许管理员强制绕过；随后通过 API 将
`can_admins_bypass` 设为 `false` 并再次读回确认。该设置不等于完成了真实 tag 发布审批验收。
