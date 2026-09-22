# ACME 证书管理（安全重构中）

> [!WARNING]
> 当前实现已完成权限边界与供应链整改，但尚未通过临时 Ubuntu VM 的签发、续期、
> 回滚和卸载验收。在对应 TODO 完成前，请勿用于生产主机。

`AcmeConfig/` 是 DevOpsToolkit 的独立实验组件，不在主项目签名 Release 的资产中。
因此，根目录 `install.sh` 的 SHA256 与 Sigstore/Cosign 验证**不覆盖**这里的文件。
请从经过审核的仓库提交获取完整目录，不要直接执行可变 `main` 分支上的单个脚本。

## 支持边界

- 目标系统：使用 systemd 的 Ubuntu 22.04/24.04。
- 需要 root、Python 3、curl、OpenSSL、GNU tar、`runuser` 和 logrotate。
- 证书签发支持 webroot 与 acme.sh DNS provider。
- 当前固定 acme.sh `3.1.6` 的提交
  `807da6498377ee5e0cf43a78091f46f12dc59a89`，下载归档必须匹配脚本内 SHA256。
- 新签发证书显式固定为 ECDSA P-256；安装、查询和吊销均使用同一 ECC 证书槽位。
- 不支持从 `get.acme.sh` 或任意分支执行远程 shell，也不启用 acme.sh 自动升级。

## 安全模型

```text
root 管理命令
    │ 以参数数组调用，不拼接 shell
    ▼
acme 用户（nologin） ── 读取 DNS 密钥 ──> /etc/acme/dns-config
    │                                      root:acme-secrets 0640
    │ 签发/续期，只写 staging 与部署请求
    ▼
/var/lib/acme/staging + deploy-queue
    │
    │ root oneshot 校验 owner、文件类型、大小、PEM 和域名
    ▼
/var/lib/acme/certs
    ├── *.key  root:ssl-cert 0640
    └── *.crt  root:ssl-cert 0644
              │
              └── 仅配置的活动 service 执行 reload-or-restart
```

关键边界：

- `acme` 只属于 `acme` 与 `acme-secrets`，不属于 `ssl-cert`。
- Web 服务账户可属于 `ssl-cert`，但不得属于 `acme-secrets`。
- 续期服务以 `acme` 运行；只有独立的部署 oneshot 以 root 运行。
- 部署进程拒绝 staging 符号链接、错误 owner、异常大小和非 PEM 内容，并用 OpenSSL
  校验证书有效期、域名、链及私钥公钥匹配关系。
- 只有证书确实部署成功后，才会 reload 当前处于 active 状态的配置服务。
- DNS 配置使用受限的 `KEY=value` 解析器，不 `source` 文件。

## 初始化

先在可信工作站审核完整目录，再把它复制到临时 VM。初始化要求显式邮箱：

```bash
sudo ./acme-init.sh admin@example.com
sudo ./acme-check.sh
```

已由可信工作站下载并按仓库锁定值验证的归档，可用于无公网出口的主机；目标机仍会
再次执行 SHA256 校验：

```bash
sudo ./acme-init.sh --archive /root/acme.sh-pinned.tar.gz admin@example.com
```

脚本会安装：

- `/usr/local/libexec/devops-toolkit/acme-manager`
- `/usr/local/bin/acme-add`、`acme-list`、`acme-revoke`
- `acme-renew.timer/service`
- `acme-deploy.path/service`
- `/etc/logrotate.d/acme`

初始化是幂等的；只有 `/etc/acme/acme-source` 中的版本、提交、归档 SHA256 和已安装
程序 SHA256 全部匹配时，才会复用现有 acme.sh。初始化显式设置
`AUTO_UPGRADE='0'`。切换版本必须同时更新固定提交、归档哈希、健康检查与测试证据。

## DNS 密钥配置

不要在交互 shell 中导出生产密钥。创建严格格式的配置文件：

```bash
sudo install -d -o root -g acme-secrets -m 0750 /etc/acme
sudo install -o root -g acme-secrets -m 0640 /dev/null /etc/acme/dns-config
sudoedit /etc/acme/dns-config
```

Cloudflare 示例（占位值不能直接使用）：

```text
CF_Token=replace-with-scoped-token
CF_Account_ID=replace-with-account-id
```

允许空行、`#` 注释、可选 `export ` 前缀以及成对的单/双引号。变量名必须符合 shell
标识符格式；`PATH`、`HOME`、`LD_PRELOAD`、`PYTHONPATH` 等执行环境变量会被拒绝。
应使用只允许目标 zone 的最小权限 token，并在日志或工单中隐藏值。

## 签发与查询

Webroot：

```bash
sudo acme-add example.com
sudo acme-add example.com www.example.com --method webroot --webroot /var/www/html
```

DNS 与通配符：

```bash
sudo acme-add example.com '*.example.com' --method dns --dns-provider dns_cf
```

查询与吊销：

```bash
sudo acme-list
sudo acme-list example.com
sudo acme-revoke example.com
```

兼容旧命令的末尾 `dns`/`webroot` 写法，但新自动化应使用显式选项。所有域名都会先
转为小写并校验；通配符只允许 DNS 验证。

## 证书消费者 reload

编辑 root 拥有的 allowlist，每行一个 systemd service：

```bash
sudoedit /etc/acme/reload-services
sudo chown root:root /etc/acme/reload-services
sudo chmod 0644 /etc/acme/reload-services
```

默认候选是 `nginx.service`、`openresty.service`、`xray.service`。不存在或 inactive 的
服务会跳过；成功部署证书后才会调用 `systemctl reload-or-restart`。不接受任意 shell
命令，也不会每日无条件重启服务。

## 运行状态与排障

```bash
sudo ./acme-check.sh
systemctl status acme-renew.timer acme-deploy.path
journalctl -u acme-renew.service -u acme-deploy.service --since today
sudo systemctl start acme-renew.service
```

失败的部署 marker 会移到 `/var/lib/acme/deploy-failed/`，不会覆盖当前证书。排查时只
记录域名、owner、mode、时间和错误类型，不要输出 `/etc/acme/dns-config` 或私钥内容。

健康检查会验证：账户组边界、目录与文件权限、上游来源 marker、systemd unit、证书
PEM、符号链接和队列状态。失败项返回非零；缺少可选 DNS 配置、待处理或失败 marker
属于警告。

## 安全卸载与回滚

清理脚本默认是 dry-run：

```bash
sudo ./acme-cleanup.sh
```

核对输出的固定路径后才执行：

```bash
sudo ./acme-cleanup.sh --yes
```

执行模式会先将 `/var/lib/acme` 和 `/etc/acme` 备份到
`/var/backups/devops-toolkit-acme/<UTC 时间>/`，归档权限为 root `0600`，然后停用 unit
并删除托管路径。备份包含账户密钥、DNS 密钥和证书私钥，应纳入敏感数据保管策略。
脚本不会自动删除用户和组，避免破坏共享的 `ssl-cert` 组。

恢复前先在隔离目录查看归档清单，不要覆盖一个正在工作的环境：

```bash
sudo tar -tzf /var/backups/devops-toolkit-acme/<UTC 时间>/acme-state.tar.gz
```

## 开发验收

仓库内的快速检查：

```bash
python3 AcmeConfig/tests/test_acme_manager.py -v
bash -n AcmeConfig/*.sh AcmeConfig/bin/*
shellcheck AcmeConfig/*.sh AcmeConfig/bin/*
./tests/verify-ansible.sh
```

`AcmeConfig/tests/vm-smoke.sh` 是具有写入和测试服务创建行为的隔离 VM 用例，必须先
在一次性 VM 上安装 `AcmeConfig/tests/throwaway-vm-marker.txt` 到
`/etc/devops-toolkit-acme-test-vm`；不得在真实主机运行。

这些检查不能替代真实 VM 验收。临时 VM 至少要覆盖初始化、webroot/DNS 测试证书、
强制续期、部署后 reload、staging/queue 攻击用例、备份卸载和恢复。生产启用还需要
单独审批、DNS 最小权限凭据以及消费者服务配置验证。
