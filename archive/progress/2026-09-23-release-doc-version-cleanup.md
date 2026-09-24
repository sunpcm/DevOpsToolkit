# P2 版本示例与发布失败恢复文档收敛

日期：2026-09-23

基线：本地 `codex/devopstoolkit-hardening` 分支；已发布版本为 `v0.1.7`，
本地 `git tag -l 'v0.1.*'` 包含 `v0.1.5`、`v0.1.6` 和 `v0.1.7`。

README 与安装文档已把 `v0.1.7` 标为已发布版本；`v0.1.4` 仅用于旧版本兼容与升级示例，
“自 `v0.1.5` 起”表述的是已有 Release 的 collection 打包行为，不再称其为下一版。

本次修订 `docs/RELEASING.md`：新发布示例改用未占用版本，并在打 tag 前验证本地及远端
同名 tag 不存在；失败恢复不再建议删除 Release/tag 或复用版本号，而是保留现场、修复后
另发新 patch 版本。这与待落实的 tag ruleset 和 immutable releases 目标保持一致。

验证：`rg -n 'v0\.1\.[0-7]|下一版' README.md docs` 复核所有旧版本提及语境；
`git diff --check` 通过。GitHub 控制面尚未启用，文档修订不等于 ruleset 生效或完成发布。
