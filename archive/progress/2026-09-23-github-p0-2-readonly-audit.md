# P0-2 GitHub 发布控制面只读复核

日期：2026-09-23
仓库：`sunpcm/DevOpsToolkit`（公开；默认分支 `main`）
性质：只读 API 查询；未修改 GitHub 设置、tag 或 Release。

## 当前远端状态

| 控制项 | 只读查询结果 |
| --- | --- |
| Repository rulesets | `GET /repos/sunpcm/DevOpsToolkit/rulesets` 返回空列表；`main` 和 `v*` 均未受规则集保护。 |
| `release` Environment | `protection_rules=[]`，`deployment_branch_policy=null`。 |
| Actions 限制 | `allowed_actions=all`，`sha_pinning_required=false`。 |
| Actions 默认权限 | `default_workflow_permissions=read`，`can_approve_pull_request_reviews=false`；这两项已经符合最小权限。 |
| Immutable releases | 官方 `GET /repos/sunpcm/DevOpsToolkit/immutable-releases` 返回 `enabled=false`、`enforced_by_owner=false`。 |
| Dependabot alerts | 官方 `GET /repos/sunpcm/DevOpsToolkit/vulnerability-alerts` 返回 404 `Vulnerability alerts are disabled`；仓库 `dependabot_security_updates.status=disabled`。 |
| 维护者 | Collaborators API 只返回 `sunpcm` 一名管理员；不能直接启用“第二人批准”而锁死日常合并。 |
| `main` 当前 checks | 仍是旧矩阵的 `validate (3.10, 2.12.10)`、`validate (3.12, 2.18.6)`、`quality` 等；本地新矩阵 Python 3.12/3.14 + core 2.21.4 尚未推送，不能现在要求其检查名。 |

## 激活顺序与风险

1. 先把新代码经独立复核和远端 Validate 跑通，再以实际 GitHub check 名称配置 `main` 必需检查。单维护者阶段不强制他人 approval。
2. 为 `release` Environment 限定 `v*` tag；独立核实是否有可用的第二名审批者，再决定是否配置 required reviewers。仅限 tag 本身不等于人工审批。
3. 开启 immutable releases 前确认 Release workflow 适配：当前 `gh release create` 同时带三个资产；GitHub CLI 文档说明它先建 draft、上传资产再发布，因此流程方向正确，但仍须在新版本真实发布中验证。历史 Release 不会追溯变为 immutable。
4. `v*` tag ruleset 要避免“禁止创建 + 无可用 bypass”使新 tag 永远无法发布，也要避免给单一管理员全量 bypass 后虚化更新/删除保护。具体 actor/规则需在得到远端设置授权后，以只读预检和小步启用验证。
5. Actions 的 allowed-actions 政策必须覆盖当前仓库使用的非 GitHub 官方 Action；强制 SHA pin 前先复核所有 `uses:` 为完整 SHA，避免 CI 一起失效。

本地 Release workflow 已增加同 SHA quality/VM evidence、`origin/main` 祖先校验和 Source commit 记录，
但这些代码尚未推送；不能把本地实现当成 GitHub 控制面已生效。

参考：[GitHub immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)、
[GitHub CLI release create](https://cli.github.com/manual/gh_release_create)、
[GitHub rulesets API](https://docs.github.com/en/rest/repos/rules)。
