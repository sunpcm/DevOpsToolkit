# 安装、升级与回滚

推荐通过 GitHub Release 安装固定构建产物。安装器会下载压缩包和 SHA256，验证包内路径与版本，再切换统一命令 `devops-toolkit`。

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
- SHA256 能发现下载损坏或资产与 checksum 不一致，但二者来自同一个 GitHub Release，不能抵御仓库、GitHub 账号或 Release 发布权限整体失陷。
- `raw.githubusercontent.com/.../main/install.sh` 本身是可变的 root 执行代码。高安全环境应先下载、审查并固定安装器提交，再执行固定 Release；后续版本应增加 Sigstore 或 GPG 签名验证。
- 首次 SSH 连接仍会正常校验主机指纹，安装方式不会关闭该保护。
