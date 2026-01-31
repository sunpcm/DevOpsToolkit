# Ubuntu Server 自动化配置工具

基于 Ansible 的 Ubuntu 服务器一键配置方案，模块化设计，开箱即用。

---

## 目录

- [功能概览](#功能概览)
- [快速开始](#快速开始)
- [配置说明](#配置说明)
- [模块详解](#模块详解)
- [最佳实践](#最佳实践)
- [常用命令](#常用命令)
- [故障排除](#故障排除)

---

## 功能概览

| 模块 | 功能 | 默认状态 | 服务器推荐 |
|------|------|----------|------------|
| **base** | 基础软件包、时区、语言环境 | ✅ 启用 | ✅ 必需 |
| **user** | 创建普通用户、SSH 密钥、sudo 配置 | ✅ 启用 | ✅ 必需 |
| **security** | SSH 安全加固（端口、禁用 root、密钥认证） | ✅ 启用 | ✅ 强烈推荐 |
| **firewall** | UFW 防火墙规则配置 | ✅ 启用 | ✅ 强烈推荐 |
| **docker** | Docker CE + Compose 安装 | ❌ 禁用 | ⚡ 按需启用 |
| **nginx** | Nginx Web 服务器 | ❌ 禁用 | ⚡ 按需启用 |
| **brew** | Homebrew 包管理器 | ❌ 禁用 | ❌ 不推荐 |
| **fonts** | 开发字体（Powerline、FiraCode） | ❌ 禁用 | ❌ 不推荐 |
| **shell** | Zsh + Oh My Zsh + 插件 | ❌ 禁用 | ⚡ 可选 |

---

## 快速开始

### 前置条件

**控制机（你的本地电脑）：**
- 已安装 Ansible（`brew install ansible` 或 `apt install ansible`）
- 已生成 SSH 密钥对

**目标服务器：**
- Ubuntu 20.04 / 22.04 / 24.04
- 可通过 SSH 以 root 身份连接

### Step 1: 配置 SSH 密钥认证

```bash
# 生成 SSH 密钥（如果还没有）
ssh-keygen -t ed25519 -C "your_email@example.com"

# 将公钥复制到服务器 可以省略，如果ini配置中使用密码登录
ssh-copy-id root@your_server_ip

# 测试连接（应该不需要密码）
ssh root@your_server_ip
```

### Step 2: 配置主机清单

```bash
# 复制示例文件
cp host.ini.example host.ini

# 编辑清单
vim host.ini
```

配置示例：
```ini
[ubuntu_servers]
# 依赖 SSH 密钥认证
my-server ansible_host=192.168.1.100 ansible_user=root ansible_port=22 ansible_become_password=your_root_password

# 这样写最简单，登录和提权都用密码，就不用给 root传密钥了
# my-server ansible_host=192.168.1.100 ansible_user=root ansible_port=22 ansible_ssh_pass=your_ansible_user_login_password ansible_become_password=your_root_password

[ubuntu_servers:vars]
ansible_python_interpreter=/usr/bin/python3
```

### Step 3: 配置变量

编辑 `ansible/group_vars/all.yml`：

```yaml
# 必须配置
username: "your_username"          # 要创建的用户名

ssh_authorized_keys:               # SSH 公钥（重要！）
  - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... your_email@example.com"

# 按需启用模块
install_docker: true               # 需要 Docker 时启用
install_nginx: true                # 需要 Nginx 时启用
install_brew: false                # 服务器环境不推荐
install_fonts: false               # 服务器环境不推荐
install_zsh: false                 # 可选
```

### Step 4: 测试连接

```bash
ansible -i host.ini ubuntu_servers -m ping
```

期望输出：
```
my-server | SUCCESS => {
    "ping": "pong"
}
```

### Step 5: 执行配置

```bash
./bootstrap.sh
```

### Step 6: 验证新连接

**重要！在关闭当前 SSH 会话之前：**

```bash
# 打开新终端，测试用新用户连接
ssh -p 22 your_username@your_server_ip

# 如果修改了 SSH 端口
ssh -p 2222 your_username@your_server_ip
```

---

## 配置说明

### 配置文件位置

```
ubuntu-server/
├── host.ini                      # 主机清单（需要创建）
├── ansible/
│   ├── group_vars/
│   │   └── all.yml              # 所有变量配置
│   └── playbook.yml             # 主 playbook
```

### 核心变量

#### 用户管理
```yaml
create_user: true                 # 是否创建用户
username: "niu"                   # 用户名
user_password: ""                 # 密码（留空使用密钥）
user_shell: "/bin/zsh"            # 默认 shell
enable_passwordless_sudo: true    # 免密 sudo
```

#### SSH 安全
```yaml
enable_ssh_security: true         # 启用 SSH 加固
ssh_port: 22                      # SSH 端口
disable_root_login: true          # 禁用 root 登录
disable_password_auth: true       # 禁用密码登录
ssh_authorized_keys: []           # SSH 公钥列表
```

#### 防火墙
```yaml
enable_firewall: true             # 启用防火墙
allowed_ports:                    # 允许的端口
  - { port: "22", proto: "tcp", comment: "SSH" }
  - { port: "80", proto: "tcp", comment: "HTTP" }
  - { port: "443", proto: "tcp", comment: "HTTPS" }
```

#### 模块开关
```yaml
install_base_packages: true       # 基础包
install_docker: false             # Docker
install_nginx: false              # Nginx
install_brew: false               # Homebrew
install_zsh: false                # Zsh
install_fonts: false              # 字体
```

---

## 模块详解

### base（基础配置）

**功能：**
- 更新 apt 缓存
- 安装基础软件包（curl、wget、git、vim、htop 等）
- 设置时区为 Asia/Shanghai
- 配置系统语言为 en_US.UTF-8

**安装的软件包：**
```
curl, wget, git, vim, htop, net-tools, build-essential,
software-properties-common, apt-transport-https, ca-certificates,
gnupg, lsb-release
```

### user（用户管理）

**功能：**
- 创建普通用户并加入 sudo 组
- 配置 SSH 公钥认证
- 设置免密 sudo（可选）

**执行流程：**
1. 创建用户组
2. 创建用户账户
3. 创建 `.ssh` 目录
4. 添加 SSH 公钥
5. 配置 sudoers

### security（SSH 安全）

**功能：**
- 备份原始 sshd_config
- 修改 SSH 端口（可选）
- 禁用 root 登录
- 禁用密码认证
- 启用公钥认证
- 配置会话保活

**修改的配置项：**
```
Port 22
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
ClientAliveInterval 300
ClientAliveCountMax 2
```

### firewall（防火墙）

**功能：**
- 安装 UFW
- 设置默认策略（入站拒绝、出站允许）
- 放行指定端口
- 启用防火墙

### docker（Docker）

**功能：**
- 卸载旧版本 Docker
- 添加 Docker 官方源
- 安装 Docker CE、CLI、Compose 插件
- 将用户加入 docker 组

### nginx（Nginx）

**功能：**
- 安装 Nginx
- 启动并设置开机自启

### brew（Homebrew）

**功能：**
- 安装 Homebrew（Linux 版本）
- 配置环境变量

> ⚠️ **注意：** 服务器环境不推荐使用 Homebrew，建议使用 apt。

### shell（Zsh）

**功能：**
- 安装 Zsh
- 安装 Oh My Zsh
- 安装插件（autosuggestions、syntax-highlighting）
- 配置 .zshrc

---

## 最佳实践

### 服务器环境推荐配置

对于**生产服务器**，建议使用以下配置：

```yaml
# ansible/group_vars/all.yml

# 必须启用
install_base_packages: true
create_user: true
enable_ssh_security: true
enable_firewall: true

# 按需启用
install_docker: true              # 需要容器时启用
install_nginx: true               # 需要 Web 服务时启用

# 不推荐启用
install_brew: false               # 服务器用 apt 足够
install_fonts: false              # 服务器不需要字体
install_zsh: false                # 可选，bash 足够
```

### 为什么服务器不推荐 Homebrew？

1. **冗余**：Ubuntu 的 apt 已经足够强大
2. **权限问题**：Homebrew 不能以 root 运行，增加复杂性
3. **维护成本**：多一个包管理器，多一份维护工作
4. **资源占用**：Homebrew 会占用额外磁盘空间

### SSH 安全建议

1. **必须配置 SSH 公钥**后再启用 `disable_password_auth`
2. **测试新连接**后再关闭当前会话
3. 考虑修改默认 SSH 端口（如 2222）
4. 定期更新 SSH 密钥

### 防火墙配置建议

只开放必要的端口：
```yaml
allowed_ports:
  - { port: "{{ ssh_port }}", proto: "tcp", comment: "SSH" }
  - { port: "80", proto: "tcp", comment: "HTTP" }
  - { port: "443", proto: "tcp", comment: "HTTPS" }
  # 开发端口不要暴露在生产环境
```

---

## 常用命令

### 基本操作

```bash
# 测试连接
ansible -i host.ini ubuntu_servers -m ping

# 运行完整配置
./bootstrap.sh

# 更新配置
./update.sh
```

### 运行特定模块

```bash
# 只运行 Docker 配置
ansible-playbook -i host.ini ansible/playbook.yml --tags docker

# 只运行防火墙配置
ansible-playbook -i host.ini ansible/playbook.yml --tags firewall

# 跳过某些模块
ansible-playbook -i host.ini ansible/playbook.yml --skip-tags brew,fonts
```

### 调试模式

```bash
# 详细输出
ansible-playbook -i host.ini ansible/playbook.yml -v

# 更详细
ansible-playbook -i host.ini ansible/playbook.yml -vvv

# 检查模式（不实际执行）
ansible-playbook -i host.ini ansible/playbook.yml --check
```

### 服务器管理

```bash
# 检查服务状态
ssh user@server "systemctl status docker nginx ufw"

# 查看防火墙规则
ssh user@server "sudo ufw status verbose"

# 查看 Docker 容器
ssh user@server "docker ps"
```

---

## 故障排除

### "No hosts matched" 错误

**原因：** `host.ini` 文件不存在或路径错误

**解决：**
```bash
# 确保在 ubuntu-server 目录下
cd ubuntu-server
cp host.ini.example host.ini
vim host.ini
```

### "Permission denied (publickey)" 错误

**原因：** SSH 密钥未配置

**解决：**
```bash
# 先复制密钥到服务器
ssh-copy-id root@your_server_ip
```

### "Don't run this as root!" 错误（Homebrew）

**原因：** Homebrew 不允许 root 用户安装

**解决：** 禁用 Homebrew
```yaml
install_brew: false
```

### apt 锁文件被占用

**原因：** 服务器正在进行自动更新

**解决：**
```bash
# 查看 apt 进程
ssh root@server "ps aux | grep apt"

# 等待完成，或停止自动更新
ssh root@server "sudo systemctl stop unattended-upgrades"
```

### 配置后无法 SSH 登录

**检查清单：**
1. 是否配置了正确的 SSH 公钥？
2. SSH 端口是否修改？使用 `-p 端口号` 连接
3. 防火墙是否放行了新端口？
4. 是否使用了新创建的用户名？

**恢复方法：**
- 使用云服务商的 VNC/控制台访问
- 检查 `/etc/ssh/sshd_config`
- 检查 `/etc/ufw/user.rules`

---

## 项目结构

```
ubuntu-server/
├── ansible.cfg              # Ansible 配置
├── bootstrap.sh             # 首次配置脚本
├── update.sh               # 更新配置脚本
├── host.ini                # 主机清单（需创建）
├── host.ini.example        # 主机清单示例
├── README.md               # 本文档
│
└── ansible/
    ├── playbook.yml        # 主 playbook
    ├── group_vars/
    │   └── all.yml         # 全局变量
    └── roles/
        ├── base/           # 基础配置
        ├── user/           # 用户管理
        ├── security/       # SSH 安全
        ├── firewall/       # 防火墙
        ├── docker/         # Docker
        ├── nginx/          # Nginx
        ├── brew/           # Homebrew
        ├── fonts/          # 字体
        └── shell/          # Zsh
```

---

## License

MIT
