# 新版 Release 禁止回退到 Galaxy

日期：2026-09-24。基线：`be010d0275dfe38ad2387554aa5d5ede99fc498c`。
草稿 PR #2 的最终 head 与 CI SHA 以推送后的 GitHub 记录为准。

## 边界和修复

原安装器以“找不到 `.bundled-collections`”作为旧版判定，任何未来版本如果
丢失该标记，也会静默回退到在线 Galaxy 安装。GitHub Release 清单在本次只读核对时
只有 `v0.1.2`、`v0.1.3`、`v0.1.4`、`v0.1.5`、`v0.1.7` 五个正式旧版本。

现在只允许这五个精确版本进入缺标记兼容路径；其余版本缺标记时在切换
`current` 前失败，且不调用 Galaxy。有标记的包在新装及复用现有安装时都重新校验
lock 摘要、标记与 manifest。新版本的签名、构建、真实安装与回滚仍须单独验收。

## 本地复现

```bash
./tests/test-installer.sh
shellcheck install.sh tests/test-installer.sh
PATH="/opt/homebrew/Cellar/ansible/14.2.0_1/libexec/bin:$PATH" ./tests/verify-ansible.sh
git diff --check
```

安装器测试覆盖：历史 `v0.1.7` 缺标记仍走兼容路径、未来 `v0.1.8` 缺标记失败且
不访问 Galaxy/不切换 `current`，原有签名与 bundle 失败路径继续保持 fail closed。
此记录只证明本地夹具与静态门禁，不宣称正式新 Release 已通过验收。
