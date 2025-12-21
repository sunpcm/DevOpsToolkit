# Ubuntu Server 自动化配置

> 基于 Ansible 的 Ubuntu 服务器一键配置方案，模块化设计，安全可靠

这是一个**生产级服务器配置工具**，用于快速、安全地配置全新的 Ubuntu 服务器。

- ✅ 模块化角色设计
- ✅ 安全优先（SSH 加固、防火墙）
- ✅ 可重复执行（幂等性）
- ✅ 灵活配置（变量驱动）

---

## ✨ 功能特性

### 🔐 安全配置
- 创建普通用户 + 免密 sudo
- SSH 安全加固（禁用 root、密钥登录、自定义端口）
- UFW 防火墙配置
- 最小权限原则

### 🛠️ 开发环境
- Docker CE + Compose
- Nginx Web 服务器
- Homebrew 包管理器
- Zsh + Oh My Zsh + 插件
- 开发字体（Powerline、FiraCode）

### 📦 系统优化
- 系统更新和基础包安装
- 时区配置（Asia/Shanghai）
- Locale 设置
- 自动清理

---

## 📋 系统要求

| 项目 | 要求 |
|------|------|
| 操作系统 | Ubuntu 20.04 / 22.04 / 24.04 |
| 架构 | x86_64 (amd64) |
| 初始用户 | root 或具有 sudo 权限的用户 |
| 网络 | 稳定的互联网连接 |
| 控制机 | 安装了 Ansible 的机器（本地或跳板机） |

---

## 🚀 快速开始

### 1️⃣ 准备控制机

在您的**本地机器**或**跳板机**上：

```bash
# 安装 Ansible（如果还没有）
sudo apt update
sudo apt install -y ansible

# 克隆或下载本项目
cd ubuntu-server
```

### 2️⃣ 配置清单文件

```bash
# 复制示例文件
cp host.ini.example host.ini

# 编辑清单文件
vim host.ini
```

**示例配置**：
```ini
[ubuntu_servers]
my-server ansible_host=192.168.1.100 ansible_user=root ansible_port=22

[ubuntu_servers:vars]
ansible_python_interpreter=/usr/bin/python3
```

### 3️⃣ 配置变量

编辑 [`ansible/group_vars/all.yml`](ansible/group_vars/all.yml)：

```bash
vim ansible/group_vars/all.yml
```

**必须配置的项**：
```yaml
# 用户名
username: "your_username"

# SSH 公钥（必须！用于免密登录）
ssh_authorized_keys:
  - "ssh-rsa AAAAB3NzaC1... your_email@example.com"

# SSH 端口（可选，默认 22）
ssh_port: 22
```

### 4️⃣ 测试连接

```bash
# 测试 Ansible 能否连接到服务器
ansible -i host.ini ubuntu_servers -m ping
```

如果看到 `SUCCESS`，说明连接正常。

### 5️⃣ 运行配置

```bash
# 方式 1：使用 bootstrap 脚本（推荐）
./bootstrap.sh

# 方式 2：直接运行 Ansible
ansible-playbook -i host.ini ansible/playbook.yml
```

**预计时间**：10-15 分钟（取决于网络速度）

---

## ⚙️ 配置说明

### 角色启用/禁用

在 [`ansible/group_vars/all.yml`](ansible/group_vars/all.yml) 中通过开关控制：

```yaml
install_docker: true      # 安装 Docker
install_nginx: true       # 安装 Nginx
install_brew: false       # 不安装 Homebrew
install_zsh: true         # 安装 Zsh
```

### SSH 安全设置

```yaml
enable_ssh_security: true
ssh_port: 2222                    # 修改 SSH 端口
disable_root_login: true          # 禁用 root 登录
disable_password_auth: true       # 禁用密码认证
```

⚠️ **重要**：配置 SSH 安全后，必须通过新端口和密钥登录！

### 防火墙端口

```yaml
allowed_ports:
  - { port: "{{ ssh_port }}", proto: "tcp", comment: "SSH" }
  - { port: "80", proto: "tcp", comment: "HTTP" }
  - { port: "443", proto: "tcp", comment: "HTTPS" }
  # 添加更多端口...
```

---

## 📂 目录结构

```
ubuntu-server/
├── bootstrap.sh           # 主入口脚本
├── update.sh             # 更新脚本
├── ansible.cfg           # Ansible 配置
├── host.ini.example      # 主机清单模板
├── host.ini              # 实际主机清单（需创建）
├── README.md             # 本文档
├── CONFIGURATION.md      # 详细配置指南
└── ansible/
    ├── playbook.yml      # 主 Playbook
    ├── group_vars/
    │   └── all.yml       # 全局变量
    └── roles/
        ├── user/         # 用户管理
        ├── security/     # SSH 安全
        ├── firewall/     # UFW 防火墙
        ├── base/         # 基础系统
        ├── docker/       # Docker CE
        ├── nginx/        # Nginx
        ├── brew/         # Homebrew
        ├── shell/        # Zsh + Oh My Zsh
        └── fonts/        # 字体安装
```

---

## 🔄 更新配置

修改配置后，重新应用：

```bash
./update.sh
```

或：

```bash
ansible-playbook -i host.ini ansible/playbook.yml
```

---

## ✅ 配置完成后

### 1. 测试新 SSH 连接

**不要关闭当前 SSH 会话！** 在新终端测试：

```bash
# 使用新端口和新用户
ssh -p 2222 your_username@your_server_ip

# 使用密钥文件
ssh -p 2222 -i ~/.ssh/id_rsa your_username@your_server_ip
```

### 2. 验证服务

```bash
# 检查 Docker
docker --version
docker compose version

# 检查 Nginx
sudo systemctl status nginx

# 检查防火墙
sudo ufw status

# 检查 Zsh
echo $SHELL
```

### 3. 切换到新用户

```bash
# 登出 root
exit

# 使用新用户登录
ssh -p 2222 your_username@your_server_ip
```

---

## 🛡️ 安全建议

### 必须执行
1. ✅ 设置 SSH 公钥认证
2. ✅ 禁用 root 登录
3. ✅ 禁用密码认证
4. ✅ 修改 SSH 默认端口
5. ✅ 启用防火墙

### 推荐执行
6. ✅ 配置 fail2ban（防暴力破解）
7. ✅ 定期更新系统
8. ✅ 使用非标准用户名
9. ✅ 定期审查防火墙规则
10. ✅ 监控系统日志

---

## 🔧 故障排除

### 无法 SSH 连接

```bash
# 1. 检查防火墙是否放行了 SSH 端口
sudo ufw status

# 2. 检查 SSH 服务状态
sudo systemctl status sshd

# 3. 查看 SSH 日志
sudo tail -f /var/log/auth.log
```

### Ansible 连接失败

```bash
# 测试连接
ansible -i host.ini ubuntu_servers -m ping -vvv

# 常见问题：
# - 检查 host.ini 中的 IP、用户名、端口
# - 确保 SSH 密钥已添加到 ssh-agent
# - 检查目标服务器 Python 是否安装
```

### Docker 权限问题

```bash
# 用户需要登出并重新登录才能生效
exit
ssh -p 2222 your_username@your_server

# 验证
docker ps
```

---

## 📚 扩展阅读

- [CONFIGURATION.md](CONFIGURATION.md) - 详细配置指南
- [Ansible 官方文档](https://docs.ansible.com/)
- [Ubuntu 服务器指南](https://ubuntu.com/server/docs)
- [Docker 官方文档](https://docs.docker.com/)

---

## ⚠️ 注意事项

1. **首次运行需谨慎**：建议先在测试服务器上运行
2. **备份重要数据**：虽然脚本是幂等的，但建议提前备份
3. **保持当前会话**：配置 SSH 时不要关闭当前连接
4. **测试后断开**：确认新连接可用后再断开旧会话
5. **记录新端口**：如果修改了 SSH 端口，务必记录

---

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

---

## 📄 许可

MIT License

---

**🎉 享受自动化配置的便利吧！**
