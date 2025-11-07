# Ansible Server Setup

这个 Ansible 配置用于快速设置 Ubuntu 服务器的开发环境。

## 📁 文件说明

- `playbook.yml` - 主要的 Ansible playbook 配置
- `host.ini` - 服务器清单文件（包含连接信息和密码配置）
- `ansible.cfg` - Ansible 运行配置
- `.zshrc.server` - 清理过的 zsh 配置文件（移除了敏感信息）

## 🚀 主要功能

### 安全配置

- ✅ 配置 SSH 密钥登录
- ✅ 禁用密码登录
- ✅ 禁用 root 用户 SSH 登录
- ✅ 修改 SSH 默认端口为 ansible_new_port（配置一里的端口）
- ✅ 配置防火墙规则 (UFW)
- ✅ 将用户添加到 sudo 组
- ✅ 自动清理配置文件中的敏感信息

### 开发环境

- ✅ 安装并配置 Zsh + Oh My Zsh
- ✅ 使用 agnoster 主题
- ✅ 安装 zsh-autosuggestions 插件
- ✅ 安装支持主题的字体（Powerline、FiraCode）
- ✅ 安装 Homebrew 包管理器
- ✅ 安装基础开发工具（git, curl, build-essential）
- ✅ 安装 Docker CE 及相关工具
- ✅ 配置 Docker 用户权限（免 sudo）
- ✅ 预设 Docker 常用别名和快捷命令
- ✅ 安装 Nginx Web 服务器
- ✅ 配置防火墙开放必要端口

### 智能特性

- ✅ 幂等性：可以多次运行而不重复安装
- ✅ 备份：会备份现有的 .zshrc 文件
- ✅ 自动清理：移除配置中的敏感信息
- ✅ 安全执行：防火墙配置不会导致 SSH 断连
- ✅ 错误预防：修复了任务依赖和执行顺序问题
- ✅ 现代化标准：使用最新的 GPG 密钥管理方式
- ✅ 智能端口检测：自动识别当前 SSH 连接端口并保护

## 🔧 使用方法

### 📋 前置要求

1. **本地环境**：
   - macOS 系统（已配置 SSH 密钥）
   - 已安装 Ansible：`brew install ansible`
   - 确保 `~/.ssh/id_rsa.pub` 公钥文件存在

2. **服务器要求**：
   - Ubuntu Server 系统
   - 可以通过 SSH 连接
   - 具有 sudo 权限的用户账户

### 🚀 快速开始

#### 步骤 1: 克隆或下载配置文件

```bash
# 如果是 git 仓库
git clone <repository-url>
cd ansible_server_setup

# 或者直接创建目录并复制文件
mkdir ansible_server_setup
cd ansible_server_setup
# 复制所有配置文件到此目录
```

#### 步骤 3: 配置服务器信息

编辑 `host.ini` 文件，更新你的服务器信息：

**情况 1: 服务器只有 root 用户**（新服务器常见情况）
编辑 `host.ini` 文件，替换服务器 IP 和密码：
```ini
[servers]
your_server_ip_here ansible_ssh_pass=server1_password ansible_become_pass=server1_password

[all:vars]
ansible_user=root  # 你的服务器登录用户名
ansible_new_user=username # 你想新创建的用户名 （目标用户）
ansible_new_port=6626 # 你想开的端口，后面都以 6626 举例，请以实际为准
```

**情况 2: 服务器已有普通用户**
```ini
[servers]
# 替换为你的服务器 IP 地址
your-server-ip-1  ansible_ssh_pass=server1_password ansible_become_pass=server1_password
your-server-ip-2  ansible_ssh_pass=server2_password ansible_become_pass=server2_password

[all:vars]
# 使用现有的普通用户登录
ansible_user=your-existing-username
```

#### 步骤 4: 配置目标用户

可以无需编辑 `playbook.yml` 文件

```yaml
  vars:
    # 这个用户名是你要为之配置 Zsh、Homebrew 的用户，自动取ansible_new_user和ansible_new_port
    target_user: "{{ ansible_new_user }}"
    target_port: "{{ ansible_new_port }}"
```

#### 步骤 5: 测试连接
验证 Ansible 可以连接到你的服务器：
```bash
ansible -i host.ini servers -m ping
```
预期输出：
```
your-server-ip | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
```

#### 步骤 6: 执行部署

运行 Ansible playbook：

```bash
ansible-playbook -i host.ini playbook.yml
```

#### 步骤 7: 验证安装
部署完成后，连接到服务器验证（注意使用新端口）：
```bash
# 使用新的 SSH 端口连接
ssh -p 6626 your-username@your-server-ip

# 验证 zsh 和主题
echo $SHELL
# 应该输出：/usr/bin/zsh

# 验证 Docker
docker --version
docker compose version

# 测试 Docker 别名
dps  # 等同于 docker ps
di   # 等同于 docker images

# 验证 Homebrew
brew --version

# 验证 Nginx
sudo systemctl status nginx

# 验证防火墙
sudo ufw status
```

### 🔍 故障排除

#### 常见问题

1. **SSH 连接失败**
   ```bash
   # 检查 SSH 密钥
   ssh-add -l
   
   # 手动测试连接
   ssh -v your-username@your-server-ip
   ```

2. **权限错误**
   ```bash
   # 确保用户有 sudo 权限
   ansible -i host.ini servers -m shell -a "sudo whoami" --ask-become-pass
   ```

3. **Docker 权限问题**
   ```bash
   # 重新登录后测试（组权限需要重新登录生效）
   ssh your-username@your-server-ip
   docker ps
   ```

4. **查看详细日志**
   ```bash
   # 使用 -v 参数获取详细输出
   ansible-playbook -i host.ini playbook.yml -v
   
   # 使用 -vvv 获取更详细的调试信息
   ansible-playbook -i host.ini playbook.yml -vvv
   ```

### 📊 执行统计

- **总任务数**: 30 个主要任务 + 验证任务
- **预计执行时间**: 8-12 分钟（取决于网络速度）
- **重启要求**: 无需重启（但建议重新登录以生效用户组权限）

## 🛡️ 安全性和可靠性保证

### 🔒 安全执行设计

本 playbook 经过专门优化，确保执行过程的安全性：

**防火墙配置安全**：
- ✅ 智能检测当前 SSH 连接端口并自动允许
- ✅ 配置所有必要端口规则后再启用防火墙
- ✅ 支持从任何端口运行 playbook 而不会被锁定
- ✅ 避免因防火墙配置导致 SSH 连接断开

**任务执行顺序优化**：
- ✅ 先安装 Oh My Zsh，再安装插件（避免目录不存在错误）
- ✅ 在 Oh My Zsh 安装后覆盖自定义配置（避免配置丢失）
- ✅ Docker 组权限添加后提供明确的重新登录提示

**现代化安全标准**：
- ✅ 使用 GPG keyring 替代已弃用的 apt_key
- ✅ 专用密钥目录 `/etc/apt/keyrings/`
- ✅ 签名验证确保软件包来源安全

### ⚠️ 重要安全提醒

1. **SSH 端口变更**：部署后 SSH 端口将改为 6626
   ```bash
   # 新的连接方式
   ssh -p 6626 your_user_name@your-server-ip
   ```

2. **用户权限生效**：Docker 组权限需要重新登录后生效
   ```bash
   # 部署完成后重新连接
   ssh -p 6626 your_user_name@your-server-ip
   docker ps  # 现在可以无需 sudo 使用
   ```

3. **防火墙状态**：部署后防火墙将自动启用
   ```bash
   # 检查防火墙状态
   sudo ufw status
   ```

### 🚨 故障排除增强

**连接问题**：
- 如果 SSH 连接失败，检查是否使用了新端口 6626
- 确保防火墙规则正确配置了必要端口

**权限问题**：
- Docker 命令权限被拒绝：重新登录以获得 docker 组权限
- sudo 权限问题：确认用户已正确添加到 sudo 组

**配置验证**：
```bash
# 验证关键服务状态
sudo systemctl status docker nginx ssh
sudo ufw status
```

### 🔧 进阶配置

#### 自定义配置
如果你需要添加自己的配置，可以修改 `.zshrc.server` 文件：

```bash
# 在文件末尾添加你的自定义配置
echo "# 我的自定义配置" >> .zshrc.server
echo "export MY_VAR=value" >> .zshrc.server
echo "alias myalias='command'" >> .zshrc.server
```

#### 选择性执行任务
如果只想执行特定任务，可以使用标签：

```bash
# 只安装 Docker（需要先在 playbook 中添加标签）
ansible-playbook -i host.ini playbook.yml --tags docker

# 跳过某些任务
ansible-playbook -i host.ini playbook.yml --skip-tags ssh
```

#### 批量服务器管理
对于大量服务器，可以使用 Ansible 的并行执行：

```bash
# 同时在 10 台服务器上执行（默认是 5 台）
ansible-playbook -i host.ini playbook.yml --forks 10

# 指定特定的服务器组
ansible-playbook -i host.ini playbook.yml --limit "192.168.1.100,192.168.1.101"
```

## ⚠️ 安全注意事项

- `.zshrc.server` 文件已经移除了以下敏感信息：
  - Cloudflare API Token
  - Cloudflare Account ID
  - 个人路径引用（如 acme.sh）

- 原始的 `.zshrc` 文件保留在本地，不会被部署到服务器

## 🎨 配置的主题和插件

- **主题**: agnoster（需要支持 Powerline 的字体）
- **插件**:
  - git（默认）
  - zsh-autosuggestions（自动建议历史命令）

## 📦 安装的软件包

- zsh - 现代化 Shell
- git - 版本控制
- curl - 网络工具
- build-essential - 编译工具
- ufw - 防火墙管理
- nginx - Web 服务器
- fonts-powerline - 支持主题的字体
- fonts-firacode - FiraCode 字体
- Oh My Zsh - Zsh 框架
- Homebrew - 包管理器
- Docker CE - 容器化平台
- Docker Compose - 容器编排工具
- Docker Buildx - 扩展构建功能
- Nginx - Web 服务器
- UFW - 防火墙工具

## 🐳 Docker 功能

### 预设别名

- `dps` - 查看运行中的容器 (docker ps)
- `dpsa` - 查看所有容器 (docker ps -a)
- `di` - 查看镜像 (docker images)
- `dlog` - 查看容器日志 (docker logs)
- `dexec` - 进入容器 (docker exec -it)
- `dstop` - 停止所有运行的容器
- `drm` - 删除所有容器
- `drmi` - 删除所有镜像
- `dprune` - 清理系统 (docker system prune -af)

### Docker Compose 别名

- `dc` - docker compose
- `dcup` - 启动服务 (docker compose up -d)
- `dcdown` - 停止服务 (docker compose down)
- `dclog` - 查看日志 (docker compose logs -f)
- `dcps` - 查看服务状态 (docker compose ps)

### 用户权限

- 自动将用户添加到 docker 组，无需 sudo 即可使用 Docker

## 🌐 Web 服务器功能

### Nginx 配置
- ✅ 自动安装 Nginx
- ✅ 启用并自动启动服务
- ✅ 默认配置文件位置：`/etc/nginx/`
- ✅ 网站根目录：`/var/www/html/`

### 基础使用
```bash
# 检查 Nginx 状态
sudo systemctl status nginx

# 重启 Nginx
sudo systemctl restart nginx

# 重新加载配置
sudo nginx -s reload

# 测试配置文件语法
sudo nginx -t
```

## 🔥 防火墙配置

### 开放的端口

- ✅ **SSH**: 当前连接端口 (自动检测) + 6626 (新端口)
- ✅ **HTTP**: 80 (Web 服务)
- ✅ **HTTPS**: 443 (SSL Web 服务)
- ✅ **开发端口**: 8000-8999 (应用开发)

### UFW 防火墙管理
```bash
# 查看防火墙状态
sudo ufw status

# 查看详细规则
sudo ufw status verbose

# 添加新规则
sudo ufw allow 3000/tcp

# 删除规则
sudo ufw delete allow 3000/tcp

# 重置防火墙（谨慎使用）
sudo ufw --force reset
```

### ⚠️ 重要提醒
- SSH 端口已改为 **6626**，请使用: `ssh -p 6626 user@server`
- 确保在防火墙配置完成前保持 SSH 连接，避免被锁定
- Root 用户已禁用 SSH 登录，只能使用配置的普通用户

## 🔄 更新配置

如果你需要更新服务器上的 zsh 配置：

1. 修改 `.zshrc.server` 文件
2. 重新运行 ansible playbook

配置会自动更新，并保留 Homebrew 设置。

## 📚 快速参考

### 🚀 一键部署命令
```bash
# 标准部署
ansible-playbook -i host.ini playbook.yml

# 详细日志
ansible-playbook -i host.ini playbook.yml -v

# 检查模式（不实际执行）
ansible-playbook -i host.ini playbook.yml --check
```

### 🐳 常用 Docker 命令（部署后可用）
```bash
# 基础操作
dps          # 查看运行容器
di           # 查看镜像  
dlog <name>  # 查看日志
dexec <name> # 进入容器

# 清理操作
dstop        # 停止所有容器
drm          # 删除所有容器
dprune       # 清理系统

# Compose 操作
dcup         # 启动服务
dcdown       # 停止服务
dclog        # 查看日志
```

### 🔧 常见维护命令
```bash
# 更新系统包
sudo apt update && sudo apt upgrade

# 更新 Homebrew
brew update && brew upgrade

# 查看 Zsh 插件
ls ~/.oh-my-zsh/custom/plugins/

# 重新加载 Zsh 配置
source ~/.zshrc
```

---

**🎉 享受你的现代化服务器开发环境！**
