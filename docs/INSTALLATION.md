# 安装、升级与回滚

推荐通过 GitHub Release 安装固定构建产物。安装器会校验 SHA256、Sigstore 签名身份、包内路径与版本，再切换统一命令 `devops-toolkit`。

## 快速安装

新 Ubuntu 或 WSL 已经以 root 登录时：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/sunpcm/DevOpsToolkit/main/install.sh)"
```

root 模式会在 Ubuntu/WSL 上通过 apt 补齐白名单依赖，然后安装到：

- 版本：`/opt/devops-toolkit/releases/<version>`
- 当前版本：`/opt/devops-toolkit/current`
- 命令：`/usr/local/bin/devops-toolkit`

在交互终端执行上述命令时，安装完成后会直接启动向导。新服务器选择 `Ubuntu` → `当前服务器本地执行`。

普通用户执行同一命令时不会使用 sudo，安装位置为：

- 版本：`~/.local/share/devops-toolkit/releases/<version>`
- 当前版本：`~/.local/share/devops-toolkit/current`
- 命令：`~/.local/bin/devops-toolkit`

如果 `~/.local/bin` 不在 PATH：

```bash
printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >>"$HOME/.profile"
export PATH="$HOME/.local/bin:$PATH"
```

普通用户安装绝不提权。缺少 Python、Ansible、Git、curl 或 OpenSSL 时，安装器会停止，并给出需要管理员安装的依赖。

## 安装器验证顺序

安装器不会下载完成后立即解压到正式目录，而是按以下顺序处理：

1. 下载压缩包、SHA256 文件和 Sigstore bundle。
2. 验证压缩包 SHA256。
3. 在权限为 `0700` 的临时目录中检查 tar 路径并解包。
4. 核对包内 `VERSION` 与请求的版本。
5. 下载或复用固定版本 Cosign，并用安装器内置 SHA256 校验 Cosign 本身。
6. 验证 Release 的 OIDC issuer、仓库、workflow、tag ref 和触发事件。
7. 安装版本内 Ansible collections；全部成功后才原子切换 `current`。

任何一步失败，当前已安装版本都不会切换。Cosign 验证需要访问 Sigstore 信任根和透明日志服务；受限网络应显式放行，不要通过删除验证逻辑绕过。

## 固定版本和安装选项

生产环境推荐固定版本：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/sunpcm/DevOpsToolkit/main/install.sh)" -- --version v0.1.0
```

也可以通过环境变量指定：

```bash
DEVOPS_TOOLKIT_VERSION=v0.1.0 \
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/sunpcm/DevOpsToolkit/main/install.sh)"
```

只安装、不启动向导：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/sunpcm/DevOpsToolkit/main/install.sh)" -- --no-run
```

显式选择安装范围：

```bash
# root 也安装到自己的 ~/.local；不修改 /opt 和 /usr/local/bin
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/sunpcm/DevOpsToolkit/main/install.sh)" -- --user

# 必须以 root 执行
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/sunpcm/DevOpsToolkit/main/install.sh)" -- --system
```

`curl | bash` 的标准输入是管道，不会自动启动交互向导；因此文档统一使用 `bash -c "$(curl ...)"`。CI 中建议追加 `--no-run`。

## 升级

重新执行安装命令即可升级到 latest。安装器会保留旧版本目录；重复安装相同版本会复用已验证文件，并确保该版本的 Ansible collections 已安装。

升级到指定版本：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/sunpcm/DevOpsToolkit/main/install.sh)" -- --version v0.2.0 --no-run
devops-toolkit --version
```

同一版本号对应的 Release 资产被替换时，安装器会因 SHA256 变化而拒绝覆盖。这是有意的：发布后的版本应视为不可变。

安装器会缓存经过内置 SHA256 校验的 Cosign 二进制，升级时重新核对后复用：

- root：`/opt/devops-toolkit/tools/`
- 普通用户：`~/.local/share/devops-toolkit/tools/`

## 手工回滚

先确认旧版本可执行，再原子替换 `current`。root 安装示例：

```bash
test -x /opt/devops-toolkit/releases/v0.1.0/bin/devops-toolkit
python3 - <<'PY'
import os
from pathlib import Path

base = Path("/opt/devops-toolkit")
temporary = base / ".current.rollback"
temporary.unlink(missing_ok=True)
temporary.symlink_to("releases/v0.1.0")
os.replace(temporary, base / "current")
PY
devops-toolkit --version
```

普通用户把 `base` 改为 `Path.home() / ".local/share/devops-toolkit"`。回滚只切换链接，不删除任何版本。

## 从源码运行

CI、批量配置或需要审查 inventory 时仍推荐 clone：

```bash
git clone https://github.com/sunpcm/DevOpsToolkit.git
cd DevOpsToolkit
ansible-galaxy collection install -r ansible/requirements.yml
./bin/devops-toolkit
```

源码入口的 `devops-toolkit --version` 显示 `development`；Release 安装显示对应 tag。

## 安全边界

- 临时下载目录权限为 `0700`，资产文件为 `0600`。
- 安装器拒绝绝对路径、`..`、额外顶层目录、符号链接和设备文件，避免 tar 路径穿越。
- SHA256 用于完整性检查；Sigstore 进一步要求产物来自本仓库、指定 Release workflow 和对应 tag。
- Sigstore 验证失败时不会降级为只检查 SHA256。
- `raw.githubusercontent.com/.../main/install.sh` 本身仍是可变的 root 执行代码。高安全环境应先下载、审查并固定安装器提交，再执行固定 Release。
- 首次 SSH 连接仍会正常校验主机指纹，安装方式不会关闭该保护。

完整信任模型和 GitHub 手工加固清单见[发布供应链安全](SUPPLY_CHAIN_SECURITY.md)。

## 签名验证故障排查

### Release 缺少 `.sigstore.json`

通常表示该版本发布不完整或早于签名机制。不要手工伪造空 bundle，也不要改成只验证 SHA256；应重新发布新版本。

### Cosign SHA256 校验失败

不要执行已下载的 Cosign。先确认系统与架构：

```bash
uname -s
uname -m
```

然后检查网络代理是否返回了登录页、错误页或被替换的下载内容。安装器当前只支持 Linux/macOS 的 AMD64 与 ARM64。

### Sigstore 身份验证失败

这表示签名不存在、签名不绑定当前压缩包，或者证书身份不是本仓库的 Release workflow 和对应 tag。该错误不能通过重算 SHA256 修复，应检查 GitHub Actions 的 Release 运行记录和三个 Release 资产是否来自同一次发布。

### 网络或证书错误

确认系统时间、CA 证书和 HTTPS 代理正确：

```bash
date -u
curl -I https://github.com
curl -I https://tuf-repo-cdn.sigstore.dev
```

网络恢复后重新运行安装器即可；失败过程不会删除旧版本。
