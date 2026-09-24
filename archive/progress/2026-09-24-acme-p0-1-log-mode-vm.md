# P0-1：当前与轮替日志权限检查，Ubuntu 24.04 VM 阶段

日期：2026-09-24。起始 HEAD：`1fdb35639be3a7727b7815683f4f055eed1652c8`。
本轮未使用真实 DNS 凭据、域名或 CA，未修改远端或操作生产。未执行 apt：
一次性 VM 已自带本项所需命令。ACME 初始化只在该 VM 中安装固定 acme.sh 与托管资产。

`acme-check.sh` 增加只读检查：遍历 `/var/lib/acme/config` 与 `/var/lib/acme/logs`
下的当前和轮替 `*.log*`，要求普通文件、非符号链接、`acme:acme 0600`、
硬链接数为 1；同时检查 `logs/` 目录为 `acme:acme 0700`。
这使权限漂移在健康检查中失败，而不读取或打印日志内容。
审查轮替配置时发现 `config/` 为 `acme:acme 0700`，但原规则没有 `su`；
根据 [logrotate 上游手册](https://github.com/logrotate/logrotate/blob/main/logrotate.8.in)，
root 在由非特权账户控制的目录轮替日志应指定 `su`。
现已在 `logrotate/acme` 加入 `su acme acme`，并在静态门禁中防止回退。
上游手册还说明 `copytruncate` 下 `create` 不生效，因此删去原先会给人
`create 0600` 可控制轮替权限这一错误印象的配置；当前日志权限依靠 acme.sh 子进程
`umask 0077`；轮替产物的实际权限在下述 Ubuntu VM 中验证。
为让该门槛可重复，新增 `AcmeConfig/tests/vm-logrotate-smoke.sh`：仅在带明确标记的
一次性 VM 上运行；复制已安装轮替规则并只替换日志目标为临时合成目录，使用独立
logrotate 状态文件，两次强制轮替后检查当前、`.1` 与 `.2.gz` 文件均为
`acme:acme 0600` 且只有一个硬链接。脚本失败会清理临时文件，不操作真实日志。
该脚本在下述 Ubuntu VM 执行通过。

本地 `AcmeConfig/tests/test-log-permissions.sh` 使用临时合成日志验证：合规当前日志和
`.log.1.gz` 通过；owner 不符、轮替日志改为 `0644`、符号链接、硬链接或目录缺失时触发失败。
owner 负例使用不可能匹配的测试值，避免测试以 root 身份运行时出现假阴性。
扫描汇总使用中性计数，不再在存在失败项时输出误导性的 `[PASS]`。
测试在 macOS 上只对 GNU `stat` 输出做测试用适配，不改产品脚本的 Ubuntu 命令。

已执行：

```bash
bash AcmeConfig/tests/test-log-permissions.sh
python3 AcmeConfig/tests/test_acme_manager.py
bash -n AcmeConfig/acme-check.sh AcmeConfig/tests/test-log-permissions.sh AcmeConfig/tests/vm-logrotate-smoke.sh tests/verify-ansible.sh
shellcheck AcmeConfig/acme-check.sh AcmeConfig/tests/test-log-permissions.sh AcmeConfig/tests/vm-logrotate-smoke.sh tests/verify-ansible.sh
git diff --check
```

上述针对性检查均通过，Python ACME 管理器测试为 23 项通过。在默认沙箱，
Ansible 本地 RPC 和 Multipass socket 曾被拒绝；这不是代码测试结果。恢复适当权限后，
使用隔离 `ansible-core 2.21.4` 与已锁定 collections 运行完整门禁，退出码 0：

```bash
PATH=/private/tmp/devopstoolkit-p03-managed/runtime/ansible-core-2.21.4/bin:$PATH \
ANSIBLE_COLLECTIONS_PATH=/private/tmp/devopstoolkit-p14.hcJpFA/collections \
./tests/verify-ansible.sh
```

## 一次性 VM 验收

- 精确实例：`devopstoolkit-acme-log-test-20260924`；Ubuntu 24.04.5 LTS，
  Multipass 镜像 SHA256 `7b682958a67ff5de068e36de6af8b75fa645d296af5a70d6500527f6a33781db`。
  创建前 `multipass list --format json` 为空，实例只有 2 CPU、2 GiB RAM、8 GiB disk。
- 本机既有 acme.sh 归档的 SHA256 为
  `ddbe1bcbd1a44a2623a2af167ebdc678669e6e2eb396742f2d1d28e02dc14220`；
  复制进 VM 后独立复核相同。复制当前 `AcmeConfig/` 快照，用仓库测试标记限制危险 smoke 脚本。
- 在 VM 内执行 `sudo bash /home/ubuntu/AcmeConfig/acme-init.sh --archive /tmp/acme.sh.tar.gz acme-test@example.invalid`，
  固定来源校验及初始化通过。随后 `sudo bash /home/ubuntu/AcmeConfig/acme-check.sh` 为
  `0` 个失败、`1` 个警告（未配置可选 DNS 凭据）。
- 执行 `sudo bash /home/ubuntu/AcmeConfig/tests/vm-logrotate-smoke.sh` 退出码 0：
  合成日志双轮替、压缩及 `acme:acme 0600` 单硬链接边界通过。
- 另通过产品的 `run_as_acme` 路径对 acme.sh 执行离线 `--list --log`，生成
  `offline-list-smoke.log`；元数据为 `acme:acme 600 1`，大小 1198 bytes，
  未读取或输出日志内容。确认 `/var/lib/acme/config` 顶层只有该合成 `*.log` 后，
  使用已安装的原始 `/etc/logrotate.d/acme` 和独立状态文件强制轮替两次。当前、`.1`、
  `.2.gz` 均为 `acme:acme 600 1`；二次轮替后的健康检查仍是 0 失败、1 警告。

此次只证明离线客户端日志和轮替权限；不证明真实 CA/DNS 签发、续期、provider 响应或
日志内容绝不含凭据。清理前 `multipass list --format json` 只列出上述实例，VM 标记
内容为 `throwaway-multipass-only`；按精确名称执行 `multipass stop --force` 与
`multipass delete --purge` 后，实例列表为空。VM 内合成日志与初始化状态已删除，
不可恢复。本报告与候选代码作为同一变更提交；具体提交 SHA 以 Git 记录为准。
