# 2026-09-22 ACME P0-1 事务 bundle 与恢复验证

本记录证明本地提交 `69ee2350aa609aa61a5ec214642a86dd22b73150` 的范围。
提交位于本地分支 `codex/devopstoolkit-hardening`，未 push、未发布，也未操作生产环境。
本轮没有使用真实域名、DNS Token 或外部 ACME CA。

## 实现边界

- 每个域名发布到 `/var/lib/acme/certs/<domain>/revisions/<32-hex>/`，包含
  `privkey.pem`、`fullchain.pem` 与 `ca.pem`；文件完整写入、校验并 `fsync` 后，才通过
  单个 `current` 相对符号链接执行原子切换。
- root 管理的 flock 串行化部署；`.activated` 记录已成功 reload 的 revision。reload 失败、
  指针切换后目录同步失败时保留请求，重跑不会创建重复 revision，只继续 reload。
- 相同证书材料不会切换 revision 或 reload。旧 revision 保留供恢复；管理器不自动清理，
  需要容量监控和明确的人工归档策略。
- 旧版 `<domain>.key/.crt/.ca` 平铺文件会阻止新 bundle 发布，避免消费者路径静默分叉。
- 该模型保证文件系统中的完整 revision 和单点命名空间切换；不能保证一个消费者在切换瞬间
  分两次独立 `open(2)` 时取得跨文件快照。消费者必须固定同一 revision，或在完成切换后 reload。

## 本地故障注入与质量门禁

在 macOS 宿主机执行：

```bash
PATH=/private/tmp/devopstoolkit-p03-runtime-check/bin:$PATH \
ANSIBLE_HOME=/private/tmp/devopstoolkit-p03-ansible-home \
ANSIBLE_COLLECTIONS_PATH=/private/tmp/devopstoolkit-p03-collections \
XDG_CACHE_HOME=/private/tmp/devopstoolkit-p03-cache \
REQUIRE_QUALITY_TOOLS=1 ./tests/verify-ansible.sh
actionlint
gitleaks detect --source . --redact --no-banner
git diff --check
```

结果全部退出 0。ACME 管理器共 19 项单测通过，新增覆盖：

- 指针切换前失败时旧 bundle 保持完整；
- revision 准备中断时清除未完成目录；
- 指针已切换但目录同步结果不确定时保留请求并可恢复；
- reload 失败后保留请求，重试复用同一 revision；
- 重复材料不 reload；多个活动消费者 reload、非活动消费者跳过；
- 旧平铺证书拒绝自动迁移。

Ruff、ShellCheck、Actionlint、gitleaks 与完整 `verify-ansible.sh` 均通过。

## Ubuntu 24.04 一次性 VM

- 实例：`devopstoolkit-acme-bundle-20260922`，Ubuntu 24.04 LTS，2 CPU / 2 GiB。
- 使用宿主机已有且再次校验 SHA256 的 acme.sh 3.1.6 固定提交归档：
  `ddbe1bcbd1a44a2623a2af167ebdc678669e6e2eb396742f2d1d28e02dc14220`。
- 首次 `acme-init.sh --archive` 成功；联网账户注册探测超时未降低固定归档校验门槛。
  随后用同一归档重跑初始化成功，证明 24.04 上本轮路径幂等。
- `AcmeConfig/tests/vm-smoke.sh` 两次通过。最终候选覆盖空队列、首次发布、重复材料、模拟续期、
  恶意 staging 符号链接，以及两个活动和一个非活动 systemd 消费者。
- 两个活动消费者仅在首次发布和材料变化时收到 reload；非活动消费者不 reload；恶意请求使
  `acme-deploy.service` 按预期失败、进入隔离目录，且没有发布或 reload。
- 当前 key/fullchain/CA 权限分别为 `root:ssl-cert 0640/0644/0644`；domain 与 revisions 目录为
  `root:ssl-cert 0750`，`.activated` 为 `root:ssl-cert 0600`。`acme` 不能读取已发布私钥，
  `www-data` 可以读取。
- `acme-check.sh` 为 0 failure；两个 warning 分别是未配置 DNS（本轮只测本地自签）和故意保留的
  失败攻击样本。`acme-renew.service` 与 `acme-deploy.service` 的
  `systemd-analyze security` 暴露评分均为 `2.9 OK`。

## 备份、隔离恢复与清理

在同一一次性 VM 先运行 cleanup dry-run，确认 bundle 仍存在；随后运行带 `--yes` 的清理：

- 创建的 `acme-state.tar.gz` 为 `root:root 0600`；
- 在 root-only 临时目录解包后，`current` 相对链接仍可解析到 revision；
- 恢复出的私钥和证书可由 OpenSSL 解析，私钥模式仍为 `0640`；
- 清理脚本停用 unit 并删除固定托管路径，未删除系统账户或组。

归档只存在于一次性 VM，包含测试私钥，未复制回仓库。验证后执行精确目标
`multipass delete --purge devopstoolkit-acme-bundle-20260922`；随后
`multipass list --format csv` 仅有表头，实例和测试归档不可恢复。

## 未完成门槛

1. 尚无受控测试域名和 DNS Token，因此没有证明真实首次签发、provider 日志脱敏、真实链、
   真实续期或真实服务配置兼容性。
2. 尚未在 Ubuntu 22.04 执行同等真实环境回归。
3. 备份已在隔离目录恢复并解析，但没有恢复到真实消费者或做业务流量切换。
4. 尚未 push、运行 GitHub CI、发布 Release 或部署生产；这些均是独立授权门槛。
