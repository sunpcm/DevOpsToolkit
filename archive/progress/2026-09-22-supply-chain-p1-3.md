# P1-3 第三方依赖完整性锁定验收

日期：2026-09-22

分支：`codex/devopstoolkit-hardening`

实现提交：`306b1d4`（`Lock collection artifacts and audit dependencies`）

## 实现结果

- 新增 `ansible/collections.lock.json`，以名称、版本、原始归档文件名和 SHA256 作为三项
  Ansible collection 的单一锁定来源。
- Release 的无发布权限 job 先下载原始 tarball，校验精确文件集合、SHA256 和归档内
  `MANIFEST.json`，再从校验后的 tarball 安装并复核安装目录。
- 签名 job 只恢复上一 job 的原始归档与安装目录；`build-release.sh` 在打包前再次校验，
  并生成包含 lock SHA256 的 `.bundled-collections` marker。
- 安装器用 marker 中的 lock 摘要绑定包内 lock，再核对精确 collection manifest；旧版不含
  lock 摘要的已签名 bundle 仍走严格的 marker/manifest 一致性兼容路径。
- `requirements.yml` 必须与 lock 生成格式完全一致；Release 构建器、安装器夹具和发布夹具
  不再维护独立的生产版本字典。
- 新增月度只读 `dependency-audit.yml`：权限仅 `contents: read`，报告 Ansible、collections、
  Cosign、uv、NVM、goenv、Go、Node LTS 和 Actions 固定值，写入 job summary 并保留 artifact；
  不修改依赖、不创建 PR、不自动合并。
- 文档明确 apt、Docker APT 仓库与 Homebrew formula/bottle 是滚动输入；固定 Git source
  不等价于整机 bit-for-bit 可复现。

## 锁定的官方归档

通过 `ansible-galaxy collection download -r ansible/requirements.yml --no-deps` 获取归档，
随后由仓库校验器复核归档集合、SHA256 和内部 manifest：

| 归档 | SHA256 |
|---|---|
| `ansible-posix-2.2.2.tar.gz` | `00a58c5d804c9adc99c3c3dc1b9f2246f4bb5f7337941440e0956f0e31c3b82b` |
| `community-general-13.4.0.tar.gz` | `efd1c0b5dc6f89b9667e4bd77f2426c30545861910dba188593871095ede1804` |
| `community-library_inventory_filtering_v1-1.1.5.tar.gz` | `cbb9e86c5b1720df21e940cedcd2f3e1226c38262623e090a883712610733851` |

实物离线链路还执行了：从上述三个本地 tarball 安装到独立临时目录，再用 lock 对安装后的
`ansible_collections/*/*/MANIFEST.json` 做完整集合与版本复核，结果通过。

## 负向验收

自动测试确认以下任一项变化都会 fail closed，且安装器不会发布版本或切换 `current`：

- collection tarball 内容变化，但 lock SHA256 不变；
- lock 中 checksum 被替换；
- 安装后 collection manifest 版本被替换；
- `requirements.yml` 与 lock 版本不一致；
- Release marker 中 lock 摘要被替换；
- 包内 lock 字节变化，但 marker 摘要不变；
- 包内 manifest 与 lock/marker 不一致。

## 本地门禁结果

- `./tests/verify-ansible.sh`：通过；包含 playbook syntax、向导/用户环境矩阵、ACME、安装器、
  Release 及新增供应链负向测试。
- `ansible-lint==26.8.0` + `ansible-core==2.21.4`：`0 failure(s), 0 warning(s)`，production profile。
- `ruff==0.9.10`、`yamllint==1.38.0`、ShellCheck、Actionlint：通过。
- Gitleaks：77 个提交，无泄漏。
- `scripts/dependency-audit.py --output <report>`：成功生成只读报告，一致性检查通过。

## 边界与剩余风险

- 本阶段只完成本地代码、文档、测试与提交；没有 push、创建 GitHub Release、修改仓库规则或
  在 GitHub 上手工触发月度 workflow。远端首次运行需在分支推送并合并后观察。
- collection SHA256 保护“以后下载内容不得静默变化”，但初次取得校验值仍属于信任首次获取；
  每次升级必须由维护者从官方来源独立复核归档、变更日志与 checksum，再走 PR 和 VM smoke。
- 月度报告只列出当前固定值与官方复核入口，不自动判断或升级到“最新”版本，避免无人审核的
  高风险供应链变更；版本是否应升级仍是维护者决策。
