# DevOpsToolkit

基于 Ansible 的 Linux 环境配置工具，明确区分系统配置、root 配置和普通用户配置。

## 选择你的场景

| 场景 | 登录/执行身份 | 会修改系统 | 会创建用户 | 用户配置范围 | 入口 |
|---|---|---:|---:|---|---|
| WSL2 初始化 | WSL 内 root | 是 | 是 | root 最小配置 + 目标用户完整配置 | `bin/wsl-bootstrap` |
| Ubuntu 服务器初始化 | 首次 root，后续目标用户 + sudo | 是 | 是 | root 最小配置 + 目标用户完整配置 | `bin/ubuntu-bootstrap` |
| Ubuntu SSH 第二阶段 | 目标用户的新端口连接 | 是 | 否 | 收紧 SSH/UFW | `bin/ubuntu-ssh-finalize` |
| 已有用户配置 | 普通用户密码或密钥 | 默认否 | 否 | 只修改当前用户 HOME | `bin/user-only` |

如果不确定该选哪个：

- 新装 WSL2，需要创建开发用户：选择 WSL2 初始化。
- 新买 Ubuntu VPS，需要初始化系统和创建运维用户：选择 Ubuntu 服务器初始化。
- 公司服务器已有账号，只想配置自己的 Shell 和开发工具：选择 user-only。

## 快速开始

### 便捷入口：Release 一行安装

新 Ubuntu/WSL 已经以 root 登录时：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/sunpcm/DevOpsToolkit/main/install.sh)"
```

安装完成后会在交互终端自动启动向导。选择 `Ubuntu` → `当前服务器本地执行`，即可创建目标用户并配置系统；普通用户执行同一命令时只安装到 `~/.local`，且绝不提权。

安装器会同时验证 Release 的 SHA256 和 Sigstore 身份，要求产物来自本仓库的 Release workflow 与对应 tag；验证失败不会降级安装。首次运行会下载并缓存固定版本 Cosign。
但上面的 `main/install.sh` 本身是可变的，不能视为完整的供应链信任链；高安全环境应先审查并固定安装器提交。

自 `v0.1.5` 起，签名 Release 内置固定版本的 Ansible collections，目标服务器安装阶段不再
依赖 Ansible Galaxy；从源码运行仍需按下节安装 collections。
Release 构建会依据 `ansible/collections.lock.json` 校验原始 tarball SHA256。该锁不覆盖 apt、Docker
仓库或 Homebrew formula 等滚动输入，不能把它理解为整机 bit-for-bit 可复现；完整边界见
[发布供应链安全](docs/SUPPLY_CHAIN_SECURITY.md)。

生产环境建议固定版本：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/sunpcm/DevOpsToolkit/main/install.sh)" -- --version v0.1.7
```

`v0.1.7` 是 2026-09-22 review 时的最新已发布版本；固定版本时应替换为你已审查的实际 tag。
注意：这里只固定了 Release，未固定安装器本身。完整的安装位置、
`--no-run`、受限网络镜像、升级、回滚和供应链边界见
[安装、升级与回滚](docs/INSTALLATION.md)。

### 从源码运行（CI 与高级用户）

```bash
git clone https://github.com/sunpcm/DevOpsToolkit.git
cd DevOpsToolkit

# Ubuntu 24.04 / WSL2 Ubuntu 24.04 控制端；Ubuntu 22.04 只作为远程受管目标
sudo apt update
sudo apt install -y python3 python3-venv git

python3 -m venv .venv
.venv/bin/python -m pip install 'ansible-core==2.21.4'

# 仅密码 SSH 登录需要
sudo apt install -y sshpass

# 安装项目需要的 Ansible collection
.venv/bin/ansible-galaxy collection install -r ansible/requirements.yml
export PATH="${PWD}/.venv/bin:${PATH}"
```

Linux 控制端仅支持 x86_64/aarch64 的 Ubuntu 24.04；WSL 初始化还要求可验证的 WSL2 内核，
WSL1 会在任何 apt/系统配置前被拒绝。远程受管 Ubuntu 22.04/24.04 也只支持这两种架构。

macOS 源码控制端同样使用隔离 runtime；先确认 `python3 --version` 为 3.12–3.14：

```bash
python3 -m venv .venv
.venv/bin/python -m pip install 'ansible-core==2.21.4'
.venv/bin/ansible-galaxy collection install -r ansible/requirements.yml
export PATH="${PWD}/.venv/bin:${PATH}"
# macOS 控制端推荐使用 SSH 私钥认证
```

### 使用交互式向导

```bash
./bin/devops-toolkit
```

向导会依次选择：

- WSL2、Ubuntu 或 user-only 模式。
- 密码或私钥认证。
- 目标用户，以及密码、公钥、两者或保留已有凭据。
- 批量选择 Shell、Git、uv、Node.js、Go、Linuxbrew、Docker、Nginx、UFW 等组件。
- Node.js 和 Go 的精确版本。

无需编辑 inventory 或变量文件。密码只用于内存中生成 SHA-512 哈希；inventory 和变量写入权限为 `0600` 的临时目录，执行结束自动删除。成功执行后只记住组件、Git 身份和工具版本等非敏感选择，高风险选项仍会逐次确认。

WSL2 模式需要：

```bash
sudo ./bin/devops-toolkit
```

如果已经以 root 登录一台全新 Ubuntu 服务器，也可以 clone 本项目后直接运行 `./bin/devops-toolkit`，选择 `Ubuntu` → `当前服务器本地执行`，无需创建 inventory。

### 手工配置（适合 CI 和长期自动化）

修改前先备份：

```bash
cp ansible/group_vars/all.yml "ansible/group_vars/all.yml.bak.$(date +%Y%m%d_%H%M%S)"
vim ansible/group_vars/all.yml
```

新建目标用户时，至少提供一种登录凭据：

```yaml
target_authorized_keys:
  - "ssh-ed25519 AAAA... your-device"

# 或使用 openssl passwd -6 生成的密码哈希
target_password_hash: "$6$..."
```

### 执行对应入口

WSL2：

```bash
sudo ./bin/wsl-bootstrap developer
```

Ubuntu 服务器：

```bash
cp ansible/inventories/ubuntu.ini.example ansible/inventories/ubuntu.ini
vim ansible/inventories/ubuntu.ini

# root 密钥登录
./bin/ubuntu-bootstrap ansible/inventories/ubuntu.ini developer \
  --private-key ~/.ssh/id_ed25519

# root 密码登录则使用 --ask-pass
```

若修改 SSH 端口，`ubuntu-bootstrap` 只执行安全准备阶段：SSH 与 UFW 同时保留当前端口和新端口。
从控制端确认目标普通用户能通过新端口登录并使用 sudo 后，改用该普通用户的新端口 inventory 执行：

```bash
./bin/ubuntu-ssh-finalize ansible/inventories/ubuntu-finalize.ini developer \
  --private-key ~/.ssh/id_ed25519 \
  -e @ansible/your-vars.yml \
  -e ssh_finalize_key_verified=true
```

只有 finalize 成功后才会应用 `disable_root_login` / `disable_password_auth` 并从受管 UFW profile
移除旧端口。交互式向导仅在“连接私钥对应的公钥已写入目标用户且目标用户有免密 sudo”时自动执行第二阶段；
否则停在可恢复的双端口准备态。

已有普通用户：

```bash
cp ansible/inventories/user-only.ini.example ansible/inventories/user-only.ini
vim ansible/inventories/user-only.ini

# 用户密钥登录
./bin/user-only ansible/inventories/user-only.ini \
  --private-key ~/.ssh/id_ed25519

# 用户密码登录则使用 --ask-pass
```

## 默认安装内容

- Zsh、Oh My Zsh 和常用插件
- Git 用户配置
- uv、NVM、Node.js、goenv/Go
- 系统托管的 Linuxbrew 和现代 CLI 工具
- WSL2 Windows 目录与剪贴板集成
- Ubuntu 可选 Docker、Nginx、UFW 和 SSH 加固

所有功能均由 [公共变量](ansible/group_vars/all.yml) 控制。Docker 和 Nginx 默认关闭；SSH 禁用 root/密码登录默认关闭。

## 安全边界

- user-only 拒绝 root，且要求登录用户、目标用户和 HOME 所有者一致。
- user-only 默认不使用 sudo；它会按所选组件检查 `git`、`zsh`、`curl`、`bash`、`tar`、`cc`、`make`。
- 显式允许白名单 apt 安装后会重新检查实际命令；依赖仍缺失时会 fail closed，不把 apt 成功当成工具可用。
- Oh My Zsh、插件、Linuxbrew 和语言工具使用集中版本配置，重复执行不会自动跟随上游分支。
- 设置 `user_only_allow_system_dependencies=true` 后，只允许通过 sudo 安装上述白名单依赖。
- 不在 inventory 中保存 SSH 密码或 sudo 密码。
- 默认开启 SSH 主机指纹校验。
- Release 同时执行 SHA256 与 Sigstore/Cosign 身份验证，任一失败都不会切换已安装版本。
- 基础 Zsh 配置写入 `~/.config/devops-toolkit/shell.zsh`；语言工具环境写入独立的
  `environment.sh` 并由 `.profile`/`.zshrc` 托管区块加载，因此关闭基础 Shell 管理不会让已选工具从 PATH 消失。

## 文档

- [安装、升级与回滚](docs/INSTALLATION.md)
- [发布流程](docs/RELEASING.md)
- [发布供应链安全与 GitHub 加固](docs/SUPPLY_CHAIN_SECURITY.md)
- [三个场景完整使用指南](docs/GETTING_STARTED.md)
- [交互式向导说明](docs/INTERACTIVE.md)
- [配置、安全与故障排查](docs/CONFIGURATION.md)
- [Multipass 真实环境测试](docs/MULTIPASS_TESTING.md)
- [ACME 证书管理（安全重构中，暂勿用于生产）](AcmeConfig/README.md)
- [历史文档](archive/README.md)

## 验证代码

```bash
./tests/verify-ansible.sh
```

该检查覆盖新旧入口的 Bash 语法、全部 Playbook 的 Ansible 语法、安装器失败边界、Release 包内容、Sigstore 身份参数、Action 固定引用，以及全局提权、主机指纹和弃用模块检查。

Ubuntu 22.04/24.04 系统级验证使用严格命名的一次性实例，详见
[Multipass 真实环境测试](docs/MULTIPASS_TESTING.md)。不要在长期保留的 Multipass 实例上测试 SSH 端口切换。

## 历史实现

统一实现已完成 22.04/24.04 真实 VM 验证，旧 `wsl-dev/`、`ubuntu-server/` 入口和根目录
兼容 Playbook 已全部移入 `archive/`。它们仅用于追溯，不能执行、不能作为配置来源，也不会进入
Release 包。当前只支持 `bin/` 与 `ansible/` 下的入口和实现。
