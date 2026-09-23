# P1-5 真实 Release 升级与回滚：Ubuntu 24.04 本地 VM 通过

日期：2026-09-23
安装器提交：`c2132d5`（本地干净工作区）
VM：Ubuntu 24.04.5 LTS，aarch64，Multipass 镜像 `7b682958a67f`；仅有测试数据，
无快照和挂载，结束后已删除，`multipass list --format json` 为空。

## 前置核对

- GitHub latest 为 `v0.1.7`；`v0.1.4` 与 `v0.1.7` 各有
  `devops-toolkit.tar.gz`、`.sha256` 和 `.sigstore.json` 三个资产。
- 通过 Multipass 共享网关 `192.168.252.1:7897` 的临时测试代理下载；这是本机网络参数，
  重跑时须重新确认。未修改生产主机或 GitHub Release。
- `install.sh` 传入 VM 后与本地提交文件 SHA256 一致：
  `4ecf9c7dca0b28b413e23d2582f942639c364c6e927ae8824d90986698c29122`。

VM 中的完整安装命令（`VERSION` 分别设为 `v0.1.4`、`v0.1.7`；latest 路径删去最后两个参数）：

```bash
sudo env \
  http_proxy=http://192.168.252.1:7897 \
  https_proxy=http://192.168.252.1:7897 \
  HTTP_PROXY=http://192.168.252.1:7897 \
  HTTPS_PROXY=http://192.168.252.1:7897 \
  bash /tmp/devops-toolkit-install-v2.sh --system --no-run --version "$VERSION"
```

## 验收过程与结果

1. 在全新 VM 用上述命令固定 `v0.1.4`。
   输出 `SHA256 校验通过`、`Sigstore 身份验证通过`，建立隔离的
   `ansible-core==2.21.4` runtime，经旧版 Galaxy collection 兼容路径安装成功。
   普通 `ubuntu` 用户运行 `/usr/local/bin/devops-toolkit --version` 返回 `v0.1.4`。
   `/opt/devops-toolkit`、`releases`、版本目录与入口均为 `0:0`、`0755`。
2. 用同一 `--version v0.1.4` 重复安装。再次通过 SHA256/Sigstore，输出
   `复用隔离的 ansible-core==2.21.4 runtime`，版本仍为 `v0.1.4`。
3. 不传 `--version` 执行 latest 安装。真实 latest `v0.1.7` 的 SHA256 与 Sigstore 身份通过，
   runtime 复用；普通用户入口返回 `v0.1.7`，`current -> releases/v0.1.7`。
   `releases/v0.1.4` 与 `releases/v0.1.7` 同时存在，均为 root 所有。
4. 显式 `--version v0.1.7` 再安装，签名校验通过，runtime 和已安装版本复用。
5. 在核对旧/新版本目录均存在且 root 所有后，以临时相对符号链接加 `os.replace`
   原子切换 `current` 到 `releases/v0.1.4`；普通用户入口返回 `v0.1.4`，新版本目录仍保留。
6. 再执行固定 `--version v0.1.7` 安装，签名校验后前滚；普通用户入口重新返回
   `v0.1.7`，两版目录仍保留。

先前的系统安装目录 UID 1001 缺陷、第一次权限修复以及 Galaxy 内部链接兼容处理见
[`2026-09-23-installer-system-ownership.md`](2026-09-23-installer-system-ownership.md)。

## 未覆盖

本次是 Ubuntu VM，不证明 macOS `sudo --system` 安装后普通用户解析 launcher 的行为；
本机 `sudo -n true` 返回 `a password is required`，没有执行 macOS root 安装，也未索取密码。
因此该项需要用户在可控的 macOS 测试账户/主机中运行或提供临时受限 sudo 能力后再验收。
本次也不证明当前本地分支已推送、GitHub Validate、下一版 Release 或生产升级。
