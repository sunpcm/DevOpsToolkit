# WSL Dev 配置指南

## 📋 目录

- [核心配置](#核心配置)
- [自定义设置](#自定义设置)
- [角色说明](#角色说明)
- [常见问题](#常见问题)

---

## 核心配置

所有配置项都在 [`ansible/group_vars/all.yml`](ansible/group_vars/all.yml) 文件中：

```yaml
# ===== Core =====
enable_brew: true              # 是否安装 Homebrew
enable_zsh: true               # 是否配置 zsh

# ===== Backup =====
enable_backup: true            # 运行前备份现有配置

# ===== Languages =====
enable_python: true            # Python (uv)
enable_go: true                # Go (goenv)
enable_node: true              # Node.js (nvm)
node_version: "24.11.1"        # 默认安装的 Node 版本

# ===== Git Configuration =====
enable_git_config: true
git_user_name: "Your Name"           # Git 用户名
git_user_email: "you@example.com"    # Git 邮箱
git_editor: "nvim"                   # 默认编辑器
git_default_branch: "main"           # 默认分支名
git_pull_rebase: "false"             # pull 时是否 rebase
enable_windows_git_credential_helper: true  # 使用 Windows Git 凭据管理器

# ===== Containers =====
enable_docker: true            # Docker CLI 配置

# ===== Windows Integration =====
enable_windows_integration: true     # Windows 互操作功能
create_windows_symlinks: true        # 创建到 Windows 目录的符号链接

# ===== Privilege =====
enable_passwordless_sudo: true       # 免密码 sudo (可选)
```

---

## 自定义设置

### 1. 修改 Git 配置

编辑 `ansible/group_vars/all.yml`：

```yaml
git_user_name: "张三"
git_user_email: "zhangsan@company.com"
git_editor: "vim"              # 或 "code --wait" 使用 VS Code
git_default_branch: "master"   # 如果公司使用 master
```

### 2. 添加更多 Homebrew 包

编辑 [`Brewfile`](Brewfile)：

```ruby
# 添加你需要的包
brew "tmux"
brew "wget"
brew "tree"
```

### 3. 自定义 .zshrc

编辑 [`ansible/roles/shell/templates/zshrc.j2`](ansible/roles/shell/templates/zshrc.j2)：

```bash
# 在文件末尾添加自定义配置

# 自定义别名
alias ll='ls -lah'
alias myproject='cd ~/projects/myproject'

# 自定义环境变量
export MY_ENV_VAR="value"
```

### 4. 修改 Oh My Zsh 主题

编辑 `ansible/roles/shell/templates/zshrc.j2`：

```bash
# 修改这一行
ZSH_THEME="robbyrussell"  # 或其他主题：powerlevel10k, cloud, etc.
```

可用主题列表：https://github.com/ohmyzsh/ohmyzsh/wiki/Themes

### 5. 配置终端字体（Nerd Font）

现代 CLI 工具（如 `eza`、`btop`、`lazygit`）使用图标字符，需要安装 Nerd Font 才能正确显示。

#### 在 Windows 上安装 FiraCode Nerd Font

**使用 winget（推荐）：**

```powershell
winget install -e --id DEVCOM.FiraCodeNerdFont
```

**手动安装：**

1. 访问 https://github.com/ryanoasis/nerd-fonts/releases
2. 下载 `FiraCode.zip`
3. 解压后，右键字体文件 → **为所有用户安装**

#### 配置 Windows Terminal

1. 打开 Windows Terminal 设置（`Ctrl + ,`）
2. **配置文件** → **Ubuntu** → **外观**
3. **字体** → 选择 `FiraCode Nerd Font` 或 `FiraCode NF`
4. 保存并重启终端

**验证安装：**

```bash
ls   # 应显示文件/文件夹图标
eza --icons
btop
```

如果图标显示为乱码（如 󰂺 ），说明字体未正确配置。

### 6. 添加 zsh 插件

编辑 `ansible/roles/shell/templates/zshrc.j2`：

```bash
# 在 plugins 行添加
plugins=(git zsh-autosuggestions zsh-syntax-highlighting docker kubectl)
```

内置插件：https://github.com/ohmyzsh/ohmyzsh/wiki/Plugins

### 6. 禁用某些功能

如不需要某些组件，在 `group_vars/all.yml` 中设置为 `false`：

```yaml
enable_go: false                    # 不安装 Go
enable_windows_integration: false   # 不配置 Windows 互操作
enable_passwordless_sudo: false     # 不启用免密 sudo
```

---

## 角色说明

### backup

自动备份现有配置文件：
- `.zshrc`
- `.bashrc`
- `.gitconfig`
- `.profile`
- `.zprofile`

备份位置：`~/.wsl-dev-backup/`

### base

安装基础系统包：
- build-essential
- curl, wget, git
- 其他开发必需工具

### brew

安装 Homebrew (Linuxbrew) 包管理器

### devtools

通过 Homebrew 安装开发工具（参考 `Brewfile`）

### shell

配置 zsh 环境：
- 安装 Oh My Zsh
- 安装 zsh-autosuggestions
- 安装 zsh-syntax-highlighting
- 部署 `.zshrc` 配置

### git

配置 Git 全局设置：
- 用户名和邮箱
- 默认编辑器
- 默认分支
- 凭据管理（Windows）
- 其他 Git 选项

### python

安装 `uv` - 现代 Python 包和项目管理工具

### node

通过 `nvm` 安装和管理 Node.js

### go

通过 `goenv` 安装和管理 Go

### docker

配置 Docker CLI，连接到 Windows Docker Desktop

### windows-integration

增强 WSL 与 Windows 的互操作：
- `winopen` - 在 Windows 资源管理器打开
- `winstart` - 用默认应用打开文件
- `clip` - 复制到剪贴板
- `paste` - 从剪贴板粘贴
- 创建 Windows 目录快捷符号链接

### sudo

（可选）配置免密码 sudo

---

## 常见问题

### Q: 如何重新应用配置？

```bash
./bootstrap.sh
```

脚本是幂等的，可以安全重复执行。

### Q: 如何只更新某个组件？

运行 Ansible playbook 并指定 tag：

```bash
cd ansible
ansible-playbook playbook.yml --tags "shell"  # 只更新 shell 配置
ansible-playbook playbook.yml --tags "git"    # 只更新 git 配置
```

### Q: 配置文件被覆盖了怎么办？

检查备份目录：

```bash
ls -la ~/.wsl-dev-backup/
```

恢复需要的文件：

```bash
cp ~/.wsl-dev-backup/.zshrc.<timestamp> ~/.zshrc
```

### Q: 如何完全卸载？

```bash
./uninstall.sh
```

会删除所有安装的工具和配置，并在删除前创建最终备份。

### Q: 如何查看安装了什么？

```bash
# Homebrew 包
brew list

# Oh My Zsh 插件
ls ~/.oh-my-zsh/custom/plugins/

# Node 版本
nvm list

# Python
uv python list

# Go 版本
goenv versions
```

### Q: Windows 剪贴板不工作？

确保 WSL 的 Windows 互操作已启用：

```bash
# 检查
cat /proc/sys/fs/binfmt_misc/WSLInterop

# 如显示 disabled，编辑 /etc/wsl.conf
sudo nano /etc/wsl.conf
```

添加：

```ini
[interop]
enabled=true
```

然后在 PowerShell 中重启 WSL：

```powershell
wsl --shutdown
```

### Q: 如何更改 Node.js 版本？

编辑 `ansible/group_vars/all.yml`：

```yaml
node_version: "20.11.0"  # 改为你需要的版本
```

重新运行：

```bash
./bootstrap.sh
```

或手动：

```bash
nvm install 20.11.0
nvm use 20.11.0
nvm alias default 20.11.0
```

### Q: 如何使用 VS Code 作为 Git 编辑器？

确保在 Windows 上安装了 VS Code，然后：

编辑 `ansible/group_vars/all.yml`：

```yaml
git_editor: "code --wait"
```

或手动配置：

```bash
git config --global core.editor "code --wait"
```

---

## 高级定制

### 添加新的 Ansible 角色

1. 创建角色目录：

```bash
mkdir -p ansible/roles/myrole/tasks
```

2. 创建任务文件 `ansible/roles/myrole/tasks/main.yml`：

```yaml
---
- name: My custom task
  debug:
    msg: "Hello from my role"
```

3. 在 `ansible/playbook.yml` 中添加：

```yaml
roles:
  # ... 现有角色
  - { role: myrole, when: enable_myrole | default(false) }
```

4. 在 `ansible/group_vars/all.yml` 中添加开关：

```yaml
enable_myrole: true
```

### 使用其他 zsh 框架

如果想用 [Prezto](https://github.com/sorin-ionescu/prezto) 或 [Zinit](https://github.com/zdharma-continuum/zinit) 代替 Oh My Zsh：

1. 禁用 shell role：

```yaml
enable_zsh: false
```

2. 手动安装你喜欢的框架

3. 或修改 `ansible/roles/shell/tasks/main.yml` 实现自己的安装逻辑

---

## 参考资源

- [Oh My Zsh 文档](https://github.com/ohmyzsh/ohmyzsh/wiki)
- [Homebrew 文档](https://docs.brew.sh/)
- [uv 文档](https://github.com/astral-sh/uv)
- [nvm 文档](https://github.com/nvm-sh/nvm)
- [goenv 文档](https://github.com/syndbg/goenv)
- [WSL 最佳实践](https://learn.microsoft.com/en-us/windows/wsl/setup/environment)
- [Docker Desktop WSL 2 backend](https://docs.docker.com/desktop/windows/wsl/)
