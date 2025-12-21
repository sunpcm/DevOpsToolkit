# DevOpsToolkit

> 🚀 Production-ready automation toolkit for WSL2 dev environment & Ubuntu servers

一键配置脚本集：WSL2 开发环境 + Ubuntu 生产服务器 + 自动化证书管理

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform: Linux](https://img.shields.io/badge/Platform-Linux-blue.svg)](https://www.linux.org/)
[![Automation: Ansible](https://img.shields.io/badge/Automation-Ansible-red.svg)](https://www.ansible.com/)

---

## 📋 目录

- [项目概述](#项目概述)
- [功能特性](#功能特性)
- [快速开始](#快速开始)
  - [WSL2 开发环境](#wsl2-开发环境)
  - [Ubuntu 服务器](#ubuntu-服务器)
- [项目结构](#项目结构)
- [技术栈](#技术栈)
- [文档](#文档)

---

## 项目概述

这是一个基于 **Ansible** 的自动化配置工具包，旨在帮助开发者快速配置开发和生产环境：

- **🖥️ WSL2 开发环境**：一键配置完整的 WSL2 开发环境，包括 Docker、多语言支持、现代 CLI 工具
- **🌐 Ubuntu 服务器**：生产级服务器配置，包括安全加固、开发工具、Docker、Nginx 等
- **🔒 ACME 证书管理**：自动化 HTTPS 证书申请和续期（即将推出）

---

## 功能特性

### 🖥️ WSL2 开发环境 ([wsl-dev](wsl-dev/))

#### ✨ 核心功能

- **环境校验**：自动检测 WSL2、Ubuntu 版本、Docker Desktop
- **包管理器**：Homebrew (Linuxbrew)
- **Shell 环境**：Zsh + Oh My Zsh + 插件（autosuggestions, syntax-highlighting）
- **编程语言**：
  - Python (uv)
  - Node.js (nvm)
  - Go (goenv)
- **容器化**：Docker CLI (WSL 模式)
- **Windows 集成**：剪贴板、文件互操作
- **现代 CLI 工具**：eza, bat, fzf, zoxide, lazygit, lazydocker, btop, dust, procs
- **Git 配置**：全局设置、Windows 凭据管理器集成

#### 📦 安装的工具

| 类别 | 工具 | 说明 |
|------|------|------|
| 包管理 | Homebrew | Linux 包管理器 |
| Shell | Zsh + Oh My Zsh | 现代化终端 |
| Python | uv | 快速 Python 环境管理 |
| Node.js | nvm | Node 版本管理 |
| Go | goenv | Go 版本管理 |
| 容器 | Docker CLI | 容器管理（使用 Docker Desktop） |
| CLI | eza, bat, fzf, zoxide | 现代化命令行工具 |
| Git TUI | lazygit | Git 终端界面 |
| Docker TUI | lazydocker | Docker 终端界面 |
| 监控 | btop | 系统资源监控 |
| 工具 | jq, yq, httpie, gh | JSON/YAML/HTTP/GitHub CLI |

#### 🎯 设计原则

- **系统级配置**：只负责开发工具，不涉及项目约定
- **环境检查**：前置验证，失败快速退出
- **幂等性**：可安全重复执行
- **备份机制**：自动备份现有配置

---

### 🌐 Ubuntu 服务器 ([ubuntu-server](ubuntu-server/))

#### 🔐 安全优先

- **用户管理**：创建普通用户、SSH 密钥认证、免密 sudo
- **SSH 加固**：修改端口、禁用 root、禁用密码认证
- **防火墙**：UFW 自动配置、端口白名单
- **最小权限**：遵循最佳安全实践

#### 🛠️ 开发环境

- **Docker**：Docker CE + Compose Plugin
- **Web 服务器**：Nginx
- **包管理器**：Homebrew (可选)
- **Shell 环境**：Zsh + Oh My Zsh (可选)
- **编程字体**：Powerline、FiraCode (可选)

#### 📦 系统优化

- **基础工具**：build-essential, git, vim, htop, net-tools
- **时区配置**：Asia/Shanghai
- **Locale 配置**：en_US.UTF-8
- **系统更新**：自动更新和清理

#### 🎛️ 模块化设计

9 个独立可配置的 Ansible 角色：

| 角色 | 功能 | 默认状态 |
|------|------|---------|
| base | 基础系统配置 | ✅ 启用 |
| user | 用户创建和配置 | ✅ 启用 |
| security | SSH 安全加固 | ✅ 启用 |
| firewall | UFW 防火墙 | ✅ 启用 |
| docker | Docker CE | ✅ 启用 |
| nginx | Nginx Web 服务器 | ✅ 启用 |
| brew | Homebrew | ✅ 启用 |
| shell | Zsh + Oh My Zsh | ✅ 启用 |
| fonts | 编程字体 | ✅ 启用 |

---

## 快速开始

### 🖥️ WSL2 开发环境

#### 前置要求

- Windows 10/11
- WSL2 已安装
- Ubuntu 22.04+ 发行版
- Docker Desktop for Windows

#### 安装步骤

```bash
# 1. 克隆仓库
git clone https://github.com/YOUR_USERNAME/DevOpsToolkit.git
cd DevOpsToolkit/wsl-dev

# 2. 运行 bootstrap
chmod +x bootstrap.sh
./bootstrap.sh
```

#### 配置（可选）

编辑 `ansible/group_vars/all.yml` 自定义安装：

```yaml
# 启用/禁用功能
enable_brew: true
enable_python: true
enable_node: true
enable_go: true
enable_docker: true

# Git 配置
git_user_name: "Your Name"
git_user_email: "you@example.com"

# Windows 集成
enable_windows_integration: true
```

#### 验证安装

```bash
# 启动 Zsh
exec zsh

# 验证工具
brew --version
uv --version
docker --version
```

**详细文档**：
- 📖 [完整 README](wsl-dev/readme.md)
- ⚙️ [配置指南](wsl-dev/CONFIGURATION.md)
- 📚 [快速参考](wsl-dev/QUICKREF.md)

---

### 🌐 Ubuntu 服务器

#### 前置要求

**控制机**（本地或跳板机）：
- 安装了 Ansible 2.9+
- SSH 客户端

**目标服务器**：
- Ubuntu 20.04 / 22.04 / 24.04
- Root 或 sudo 权限
- SSH 访问

#### 安装步骤

```bash
# 1. 进入目录
cd DevOpsToolkit/ubuntu-server

# 2. 配置清单
cp host.ini.example host.ini
vim host.ini
```

编辑 `host.ini`：
```ini
[ubuntu_servers]
my-server ansible_host=192.168.1.100 ansible_user=root ansible_port=22

[ubuntu_servers:vars]
ansible_python_interpreter=/usr/bin/python3
```

```bash
# 3. 配置变量
vim ansible/group_vars/all.yml
```

**必须配置**：
```yaml
# 用户名
username: "yourname"

# SSH 公钥（重要！）
ssh_authorized_keys:
  - "ssh-rsa AAAAB3NzaC1... your_email@example.com"

# SSH 端口（可选）
ssh_port: 2222
```

```bash
# 4. 测试连接
ansible -i host.ini ubuntu_servers -m ping

# 5. 运行配置
./bootstrap.sh
```

#### 配置后操作

⚠️ **重要**：在新终端测试连接，确认可用后再断开当前会话

```bash
# 使用新端口和新用户连接
ssh -p 2222 yourname@your_server_ip

# 验证服务
docker --version
docker compose version
sudo systemctl status nginx
sudo ufw status
```

#### 自定义配置

编辑 `ansible/group_vars/all.yml`：

```yaml
# 禁用不需要的组件
install_docker: true      # Docker CE
install_nginx: true       # Nginx
install_brew: false       # Homebrew（可选）
install_zsh: true         # Zsh + Oh My Zsh

# 防火墙端口
allowed_ports:
  - { port: "{{ ssh_port }}", proto: "tcp", comment: "SSH" }
  - { port: "80", proto: "tcp", comment: "HTTP" }
  - { port: "443", proto: "tcp", comment: "HTTPS" }
  - { port: "3000", proto: "tcp", comment: "Custom App" }
```

**详细文档**：
- 📖 [完整 README](ubuntu-server/README.md)
- ⚙️ [配置指南](ubuntu-server/CONFIGURATION.md)
- 📚 [快速参考](ubuntu-server/QUICKREF.md)
- 📝 [更新日志](ubuntu-server/CHANGELOG.md)

---

## 项目结构

```
DevOpsToolkit/
├── README.md                 # 本文件
├── wsl-dev/                  # WSL2 开发环境配置
│   ├── bootstrap.sh          # 主入口脚本
│   ├── update.sh             # 更新脚本
│   ├── uninstall.sh          # 卸载脚本
│   ├── Brewfile              # Homebrew 包列表
│   ├── readme.md             # WSL Dev 文档
│   ├── CONFIGURATION.md      # 配置指南
│   ├── QUICKREF.md           # 快速参考
│   ├── ansible/
│   │   ├── playbook.yml      # 主 Playbook
│   │   ├── group_vars/
│   │   │   └── all.yml       # 配置变量
│   │   └── roles/            # 12 个角色
│   │       ├── backup/
│   │       ├── base/
│   │       ├── brew/
│   │       ├── devtools/
│   │       ├── shell/
│   │       ├── git/
│   │       ├── python/
│   │       ├── node/
│   │       ├── go/
│   │       ├── docker/
│   │       ├── windows-integration/
│   │       └── sudo/
│   └── scripts/              # 工具脚本
│
├── ubuntu-server/            # Ubuntu 服务器配置
│   ├── bootstrap.sh          # 主入口脚本
│   ├── update.sh             # 更新脚本
│   ├── host.ini.example      # 清单模板
│   ├── README.md             # Ubuntu Server 文档
│   ├── CONFIGURATION.md      # 配置指南
│   ├── QUICKREF.md           # 快速参考
│   ├── CHANGELOG.md          # 更新日志
│   └── ansible/
│       ├── playbook.yml      # 主 Playbook
│       ├── group_vars/
│       │   └── all.yml       # 配置变量
│       └── roles/            # 9 个角色
│           ├── base/
│           ├── user/
│           ├── security/
│           ├── firewall/
│           ├── docker/
│           ├── nginx/
│           ├── brew/
│           ├── shell/
│           └── fonts/
│
└── AcmeConfig/               # ACME 证书管理（独立模块）
    ├── acme-init.sh          # 初始化脚本
    ├── acme-check.sh         # 证书检查
    ├── acme-cleanup.sh       # 清理脚本
    └── README.md             # ACME 文档
```

---

## 技术栈

### 自动化工具
- **Ansible** - 配置管理和自动化
- **Bash** - Shell 脚本

### WSL2 开发环境
- **Homebrew** - 包管理器
- **Oh My Zsh** - Zsh 框架
- **uv** - Python 环境管理
- **nvm** - Node.js 版本管理
- **goenv** - Go 版本管理
- **Docker Desktop** - 容器运行时

### Ubuntu 服务器
- **UFW** - 防火墙
- **Docker CE** - 容器引擎
- **Nginx** - Web 服务器
- **OpenSSH** - SSH 服务器

### 现代 CLI 工具
- **eza** - 现代化 ls 替代
- **bat** - cat 增强版
- **fzf** - 模糊查找
- **zoxide** - 智能 cd
- **lazygit** - Git TUI
- **lazydocker** - Docker TUI
- **btop** - 系统监控

---

## 文档

### WSL2 开发环境
- [完整文档](wsl-dev/readme.md) - 详细的安装和使用指南
- [配置指南](wsl-dev/CONFIGURATION.md) - 自定义配置说明
- [快速参考](wsl-dev/QUICKREF.md) - 常用命令速查

### Ubuntu 服务器
- [完整文档](ubuntu-server/README.md) - 服务器配置指南
- [配置指南](ubuntu-server/CONFIGURATION.md) - 角色和变量详解
- [快速参考](ubuntu-server/QUICKREF.md) - 运维命令速查
- [更新日志](ubuntu-server/CHANGELOG.md) - 版本历史

### ACME 证书管理
- [文档](AcmeConfig/README.md) - 证书管理使用说明

---

## 使用场景

### 🖥️ WSL2 开发环境适用于

- Windows 用户希望获得完整 Linux 开发体验
- 需要 Docker + 多语言开发环境
- 追求现代化命令行工具和高效工作流
- 需要与 Windows 文件系统无缝集成

### 🌐 Ubuntu 服务器适用于

- 全新服务器初始化和安全加固
- 开发/测试/生产环境标准化配置
- 多服务器批量部署
- CI/CD 流水线中的服务器配置

---

## 常见问题

### WSL2 开发环境

**Q: 为什么需要 Docker Desktop？**  
A: WSL2 中不运行 Docker daemon，Docker CLI 连接到 Windows 上的 Docker Desktop。

**Q: 可以不安装某些语言吗？**  
A: 可以，编辑 `ansible/group_vars/all.yml` 设置 `enable_python: false` 等。

**Q: 如何更新已安装的环境？**  
A: 运行 `./update.sh` 或重新执行 `./bootstrap.sh`。

### Ubuntu 服务器

**Q: 配置后无法 SSH 连接？**  
A: 确保防火墙放行了新的 SSH 端口，通过控制台登录检查。

**Q: Docker 命令提示权限不足？**  
A: 用户刚被添加到 docker 组，需要重新登录生效。

**Q: 如何只运行特定角色？**  
A: 使用 `ansible-playbook -i host.ini ansible/playbook.yml --tags docker`

---

## 最佳实践

### WSL2 开发环境
1. ✅ 安装前确保 Docker Desktop 正在运行
2. ✅ 定期运行 `./update.sh` 保持工具更新
3. ✅ 使用 `.zshrc` 自定义别名提高效率
4. ✅ 为不同项目创建独立的 Python/Node 环境

### Ubuntu 服务器
1. ✅ 首次运行前在测试服务器验证
2. ✅ 修改 SSH 配置时保持当前会话不断开
3. ✅ 配置完成后在新终端测试连接
4. ✅ 定期审查防火墙规则和系统更新
5. ✅ 使用 Ansible Vault 加密敏感信息

---

## 安全建议

### 服务器安全
- ✅ 使用 SSH 密钥认证，禁用密码登录
- ✅ 修改 SSH 默认端口
- ✅ 禁用 root 远程登录
- ✅ 启用防火墙，仅开放必要端口
- ✅ 使用非标准用户名
- ✅ 定期更新系统和软件包

### 凭据管理
- ✅ 不要在配置文件中存储明文密码
- ✅ 使用 Ansible Vault 加密敏感变量
- ✅ 使用 SSH Agent 管理密钥
- ✅ 定期轮换密码和密钥

---

## 贡献

欢迎提交 Issue 和 Pull Request！

### 贡献指南
1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 创建 Pull Request

---

## 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

---

## 致谢

本项目参考和借鉴了：
- Ansible 官方最佳实践
- Ubuntu Server 官方文档
- WSL2 开发社区经验
- 开源社区的各种优秀工具

---

## 联系方式

- 📧 Email: sunpcm@163.com
- 🐛 Issues: [GitHub Issues](https://github.com/YOUR_USERNAME/DevOpsToolkit/issues)

---

**⭐ 如果这个项目对你有帮助，请给个 Star！**

**🎉 享受自动化配置的便利吧！**
