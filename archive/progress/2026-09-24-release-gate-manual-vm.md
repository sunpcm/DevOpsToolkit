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
| `release` Environment | required reviewer 为 `sunpcm`，`prevent_self_review=false`；仅 `v*` tag 可部署；这是人工暂停点，不是第二人独立复核。 |
| Immutable releases | `enabled=true`，不追溯改变历史 Release。 |
| Actions | `allowed_actions=selected`、`sha_pinning_required=true`；仅 GitHub-owned Action，非 GitHub verified 和自定义 pattern 均关闭。 |
| Dependabot | vulnerability-alerts 返回 HTTP 204；security updates `enabled=true, paused=false`。 |

未创建 tag、Release、PR，也未推送分支。远端尚未运行新 workflow，因此审批 UI、同 SHA
Python 3.12/3.14、签名构建、不可变资产和安装/回滚仍待新版本真实验收。审批人不得以本文
替代每次发布时新生成的同 SHA VM 报告。
