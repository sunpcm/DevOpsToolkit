# [已归档] WSL Dev Bootstrap

> `wsl-dev/bootstrap.sh` 已进入兼容维护阶段。新部署请在仓库根目录运行
> `sudo ./bin/wsl-bootstrap <target_user>`。

> One‑command setup for a clean, consistent WSL2 development environment.

这是一个 **独立的一键初始化脚本**，用于在 **WSL2 + Ubuntu** 中快速配置统一、可重复的开发环境。

- ✅ 不是项目模板
- ✅ 不包含业务代码
- ✅ 不强制开发规范
- ✅ 只做一件事：**把 WSL 环境装好**

---

## ✅ Features

本脚本会自动完成以下工作：

- WSL2 / Ubuntu 环境校验（失败前置）
- 基础系统依赖安装
- **自动备份现有配置文件**
- Homebrew（Linuxbrew）
- **Oh My Zsh** + 常用插件
- **Git 全局配置**
- Python 环境（via `uv`）
- Node.js 环境（via `nvm`）
- Go 环境（via `goenv`）
- Docker CLI（WSL 模式，不运行 daemon）
- **Windows 互操作增强**（剪贴板、文件打开等）
- **现代 CLI 工具**（eza, lazygit, lazydocker, btop 等）
- 可重复执行（idempotent）
- 安装完成摘要 & 下一步指引

---

## 🖥️ System Requirements

**官方支持环境：**

| Item | Requirement |
|---|---|
| OS | Windows 10 / 11 |
| WSL | **WSL2** |
| Distro | **Ubuntu 22.04+** |
| Shell | bash / zsh |

> ❗ 其他 Linux 发行版、WSL1 不在支持范围内  
> ❗ 如果环境不符合要求，脚本会直接退出并给出明确提示

---

## Prerequisites（Windows 11 + WSL）

本项目运行在 **Windows 11 + WSL2 + Ubuntu** 环境中。  
Docker **由 Windows 侧的 Docker Desktop 提供**，**不会**在 WSL 内通过 `apt` 安装。

---

### 1. WSL2 + Ubuntu

```powershell
wsl --install
wsl -l -v   # VERSION 必须是 2
```

---

### 2. Docker Desktop for Windows

下载并安装：  
👉 https://www.docker.com/products/docker-desktop/

安装 / 设置要求：

- ✅ **Use WSL 2 based engine**
- ✅ Settings → **Resources → WSL Integration**
  - Enable integration
  - 勾选当前 Ubuntu 发行版

安装完成后 **重启 Windows**，并确保 Docker Desktop 处于 **Running** 状态。

---

### 3. 在 WSL 中验证 Docker（必须）

```bash
docker version
docker compose version
```

两条命令都成功后，才能继续执行本项目脚本。

---

### 4. Nerd Font（字体）

本项目使用的现代 CLI 工具（如 `eza`、`btop`）会在终端显示图标。  
要正确显示这些图标，需要在 **Windows 侧安装 Nerd Font** 并配置 Windows Terminal。

#### 安装 FiraCode Nerd Font（推荐）

**方法 1：使用 winget（推荐）**

在 **Windows PowerShell** 中执行：

```powershell
winget install -e --id DEVCOM.FiraCodeNerdFont
```

**方法 2：手动下载安装**

1. 访问：https://github.com/ryanoasis/nerd-fonts/releases
2. 下载 `FiraCode.zip`
3. 解压后右键字体文件 → **为所有用户安装**

#### 配置 Windows Terminal

1. 打开 **Windows Terminal 设置**（`Ctrl + ,`）
2. 导航到 **配置文件 → Ubuntu → 外观**
3. **字体**：选择 `FiraCode Nerd Font` 或 `FiraCode NF`
4. 保存设置

> ✅ 配置完成后，重启 Windows Terminal，图标即可正常显示  
> ⚠️ 如果 Windows Terminal 中看不到该字体选项，可能需要重启系统

**其他推荐字体：**
- Cascadia Code Nerd Font
- JetBrains Mono Nerd Font
- Meslo Nerd Font

---

### 5. 注意事项

- ❌ 不要在 WSL 内安装 `docker / docker-ce / docker-compose`
- ✅ Docker CLI 与 Compose 由 Docker Desktop 统一提供
- ✅ 建议开启 Docker Desktop 开机自启

如曾安装过 Linux 版 Docker，建议卸载：

```bash
sudo apt remove docker docker.io docker-ce docker-ce-cli
```

---

完成以上步骤后，执行：

```bash
./bootstrap.sh
```

---


## 🚀 Quick Start

### 1️⃣ Clone repository

```bash
git clone <your-repo-url>
cd wsl-dev-bootstrap
```

### 2️⃣ Run bootstrap

```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

> ⏳ 首次运行需要几分钟，取决于网络情况  
> ✅ 可安全重复执行

---

## 🔍 What This Script Does

### ✅ Environment sanity checks (before install)

- 是否运行在 WSL
- 是否为 WSL2
- 是否为 Ubuntu
- Ubuntu 版本是否 ≥ 22.04

如果不满足条件，**不会继续安装**。

---

### ✅ Tools Installed

| Category | Tool | Notes |
|---|---|---|
| Package Manager | Homebrew | Linuxbrew |
| Shell | Oh My Zsh | With autosuggestions & syntax highlighting |
| Python | uv | Fast, modern Python manager |
| Node.js | nvm | Node version manager |
| Go | goenv | Go version manager |
| Container | Docker CLI | Uses Docker Desktop on Windows |
| Modern CLI | eza, bat, fzf | Modern replacements for ls, cat, find |
| Git TUI | lazygit | Terminal UI for git commands |
| Docker TUI | lazydocker | Terminal UI for docker management |
| Monitoring | btop | Resource monitor |
| Utilities | jq, yq, httpie, gh | JSON/YAML processors, HTTP client, GitHub CLI |

---

## 🧠 Design Principles

本仓库遵循以下原则：

- **System‑level only**  
  只负责系统与开发工具，不涉及项目约定

- **No opinion on project setup**  
  不包含 `.nvmrc`、`pre-commit`、示例项目等

- **Fail fast**  
  环境不对，立即退出

- **Safe & repeatable**  
  可多次运行，不破坏已有环境

---

## ✅ After Installation

脚本结束后，你会看到一份 **安装完成摘要**。

### 建议的下一步：

#### Reload shell

```bash
exec zsh
# or: source ~/.zshrc
```

#### 配置 Git（如未在 group_vars 中设置）

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

#### Python (uv)

```bash
uv python install 3.12
uv venv
```

#### Node.js (nvm)

```bash
nvm install --lts
nvm use --lts
```

#### Docker

- 启动 **Docker Desktop (Windows)**
- WSL 中使用 `docker` CLI 或 `lazydocker` TUI

#### Windows 互操作功能

```bash
# 在 Windows 资源管理器中打开当前目录
explorer

# 复制内容到 Windows 剪贴板
echo "hello" | clip

# 从 Windows 剪贴板粘贴
paste

# 快捷目录访问
cdwin         # Windows 用户目录
cddownloads   # Downloads 目录
cddesktop     # Desktop 目录
```

---

## 🐳 Docker (WSL Best Practice)

- ✅ Docker daemon 运行在 **Windows**
- ✅ WSL 中只安装 Docker CLI
- ❌ 不在 WSL 内运行 `dockerd`

这是官方推荐且最稳定的模式。

---

## 🔁 Re‑running the Script

你可以在以下情况 **安全地重新运行** `bootstrap.sh`：

- 新增或修改 Brewfile
- 更新 Ansible roles
- 换新机器 / 新 WSL 实例
- 修复部分安装失败

**脚本会自动备份现有配置到 `~/.wsl-dev-backup/`**

---

## 🔄 Maintenance Scripts

### 更新环境

```bash
./update.sh
```

更新以下组件：
- 系统包
- Homebrew 及其安装的包
- Oh My Zsh 及插件
- nvm, goenv
- 重新运行 Ansible 配置

### 完全卸载

```bash
./uninstall.sh
```

**警告**：此脚本会删除所有已安装的开发工具和配置。  
卸载前会创建备份到 `~/.wsl-dev-backup/uninstall-<timestamp>/`

---

## ❓ What This Repo Is NOT

- ❌ 项目模板
- ❌ mono‑repo
- ❌ CI / code quality setup
- ❌ 开发规范约束

如果你需要这些，请在 **项目仓库中单独处理**。

---

## 📂 Repository Structure

```text
.
├── bootstrap.sh        # Entry point
├── update.sh           # Update all components
├── uninstall.sh        # Complete uninstallation
├── ansible/            # Environment provisioning
│   ├── playbook.yml
│   ├── group_vars/     # Configuration variables
│   └── roles/
│       ├── backup/           # Backup existing configs
│       ├── base/             # Base system packages
│       ├── brew/             # Homebrew installation
│       ├── devtools/         # Development tools
│       ├── shell/            # Oh My Zsh setup
│       ├── git/              # Git configuration
│       ├── python/           # Python (uv)
│       ├── node/             # Node.js (nvm)
│       ├── go/               # Go (goenv)
│       ├── docker/           # Docker CLI setup
│       ├── windows-integration/  # Windows interop features
│       └── sudo/             # Passwordless sudo (optional)
├── Brewfile            # Homebrew packages
├── scripts/            # Helper / assertion scripts
└── README.md
```

---

## 🛠️ Troubleshooting

### Script exits immediately

请检查提示信息，常见原因：

- WSL1
- Ubuntu 版本过低
- 非 Ubuntu 发行版

---

### Docker not working

- 确认 Windows 端 Docker Desktop 正在运行
- 确认 Docker Desktop 中启用了 WSL integration

---

### Git 配置问题

如需修改 Git 配置，编辑 [`wsl-dev/ansible/group_vars/all.yml`](wsl-dev/ansible/group_vars/all.yml):

```yaml
enable_git_config: true
git_user_name: "Your Name"
git_user_email: "you@example.com"
```

然后重新运行 `./bootstrap.sh`

---

### Oh My Zsh 主题或插件问题

编辑 [`wsl-dev/ansible/roles/shell/templates/zshrc.j2`](wsl-dev/ansible/roles/shell/templates/zshrc.j2) 自定义配置

---

### 恢复备份的配置

备份文件位于 `~/.wsl-dev-backup/`，按时间戳命名：

```bash
ls -la ~/.wsl-dev-backup/
cp ~/.wsl-dev-backup/.zshrc.<timestamp> ~/.zshrc
```

---

## 📜 License

MIT License

---

## ✅ Summary

> **This repository is a bootstrap tool, not a project template.**  
> One command. One responsibility. Clean WSL dev environment.
```

---

如果你愿意，**下一步我只会建议一种事**（仍然不加功能）：

- ✅ 帮你把 README 里的 **repo name / clone 地址** 替换成你真实的
- ✅ 或帮你写一段 **公司内部用的“使用说明版” README**

你随时可以说一句：  
👉 **“帮我定制成公司版 README”**
