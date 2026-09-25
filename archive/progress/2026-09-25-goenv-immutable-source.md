# goenv 来源锁定：标签改为不可变提交

> 历史阶段记录：随后在双版 Ubuntu 的全新 HOME 实测发现该提交对应的
> goenv v3 不再包含旧版 `bin/goenv`，仅固定 Git SHA 无法修复真实安装。
> 草稿 PR #4 已继续修改为校验官方 v3 二进制归档；本页的 Review 和验证
> 只适用于当时的旧提交，不代表后续改动已获复核。

日期：2026-09-25。基线：`main@9d613e85b4adaae4c9c8a5a7231556d68960b07e`。
修复提交：`0e0d3184eb2cccf9c9b5de10330d2324c6f446ed`；草稿 PR #4。

## 问题与修复

`ansible/group_vars/all.yml` 原先将 `goenv_version` 设为 `3.1.4`。这是上游 Git 标签，
不能提供与其余 Git 来源一致的不可变提交边界。此外，安装任务读取工作树的 `HEAD`
提交 SHA 却与字符串 `3.1.4` 比较，导致重复运行总会进入 Git 模块检查路径。

只读执行：

```bash
git ls-remote https://github.com/go-nv/goenv.git 'refs/tags/3.1.4' 'refs/tags/3.1.4^{}'
```

当时返回轻量标签 `3.1.4` 指向
`66571a3851c83e1341dce284aba907964c3d6a48`。配置现固定到该提交；
`tests/verify-ansible.sh` 与月度依赖审计都拒绝非 40 位 SHA 的 goenv 值，
前者同时保护现有 NVM 固定提交。配置文档与审计链接已同步。

## 验证

- 在隔离的 ansible-core 2.21.4 与已锁定 collections 下，
  `./tests/verify-ansible.sh` 完整通过，退出码 0。沙箱内首次尝试因 Ansible
  本机 RPC 无法启动而中断；在允许 RPC 的同一宿主环境重跑成功。针对本阶段
  `e5cc171b56c9db83e428ed90c72c99580a274b18` 的再次完整运行原始输出见
  [`2026-09-25-goenv-verify-ansible.report`](2026-09-25-goenv-verify-ansible.report)，
  SHA256 `86b8f3668ecce75e9d9422b89fe3a405b62587dc46ee699fa01ecfe2b1f3a4ff`，
  退出码 0。日志中的 ACME `[FAIL]` 为预期的负向权限测试，整体测试结论为通过。
- `shellcheck tests/verify-ansible.sh`、Python 语法编译、月度依赖审计与
  `git diff --check` 均通过；没有安装宿主机软件。
- 独立只读 Review 对提交 `0e0d318` 给出 APPROVED，并在临时副本中把 goenv
  改回 `3.1.4`，确认静态门禁与依赖审计都会拒绝。
- 草稿 PR #4 的 quality、Python 3.12/3.14 两组 push/PR 检查共六项均通过。

本次没有运行 goenv 的真实用户 HOME 安装与二次收敛；该门槛仍属于 P1-2 的
一次性 VM 组合验收。PR #4 保持草稿且不并入当前 `main@9d613e8` 发布候选；
若先合并，候选 SHA 改变，必须重新执行同 SHA VM 验收。未创建 tag 或 Release。
