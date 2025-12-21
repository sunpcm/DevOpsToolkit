# WSL Dev Bootstrap

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
- Homebrew（Linuxbrew）
- Python 环境（via `uv`）
- Node.js 环境（via `nvm`）
- Go
- Docker CLI（WSL 模式，不运行 daemon）
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

### 4. 注意事项

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
| Python | uv | Fast, modern Python manager |
| Node.js | nvm | Node version manager |
| Go | go | Official distribution |
| Container | Docker CLI | Uses Docker Desktop on Windows |

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
# or: exec bash
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
- WSL 中仅使用 `docker` CLI

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
├── ansible/            # Environment provisioning
│   ├── playbook.yml
│   └── roles/
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
