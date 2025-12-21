# Ubuntu Server 配置指南

## 📋 目录

- [核心配置](#核心配置)
- [自定义设置](#自定义设置)
- [角色说明](#角色说明)
- [常见问题](#常见问题)
- [高级配置](#高级配置)

---

## 核心配置

所有配置项都在 [`ansible/group_vars/all.yml`](ansible/group_vars/all.yml) 文件中：

```yaml
# ===== 用户管理 =====
create_user: true
username: "sunpcm"                    # 创建的普通用户名
user_password: ""                     # 留空使用密钥认证
user_shell: "/bin/zsh"               # 用户默认 shell
enable_passwordless_sudo: true       # 免密 sudo

# ===== SSH 安全 =====
enable_ssh_security: true
ssh_port: 22                         # SSH 端口
disable_root_login: true             # 禁用 root 登录
disable_password_auth: true          # 禁用密码认证
ssh_authorized_keys: []              # SSH 公钥列表

# ===== 防火墙 =====
enable_firewall: true
ufw_default_incoming: deny           # 默认拒绝入站
ufw_default_outgoing: allow          # 默认允许出站
allowed_ports:
  - { port: "{{ ssh_port }}", proto: "tcp", comment: "SSH" }
  - { port: "80", proto: "tcp", comment: "HTTP" }
  - { port: "443", proto: "tcp", comment: "HTTPS" }

# ===== 组件安装 =====
install_base_packages: true
install_docker: true
install_nginx: true
install_brew: true
install_zsh: true
install_fonts: true
```

---

## 自定义设置

### 1. 创建新用户

编辑 `ansible/group_vars/all.yml`：

```yaml
username: "yourname"              # 你的用户名
user_shell: "/bin/bash"          # 或 "/bin/zsh"
enable_passwordless_sudo: true   # 是否免密 sudo
```

**添加 SSH 公钥**（重要！）：

```yaml
ssh_authorized_keys:
  - "ssh-rsa AAAAB3NzaC1yc2EAAAADA... user@laptop"
  - "ssh-ed25519 AAAAC3NzaC1lZDI... user@desktop"
```

> 💡 生成密钥：`ssh-keygen -t ed25519 -C "your_email@example.com"`

---

### 2. SSH 安全配置

```yaml
enable_ssh_security: true
ssh_port: 2222                    # 修改默认端口（推荐）
disable_root_login: true          # 禁用 root 登录（强烈推荐）
disable_password_auth: true       # 只允许密钥登录（推荐）
```

⚠️ **警告**：
- 修改配置前，确保已添加 SSH 公钥！
- 配置完成后，在新终端测试连接再断开旧会话！
- 记录新的 SSH 端口号！

**测试新连接**：
```bash
ssh -p 2222 yourname@your_server_ip
```

---

### 3. 防火墙端口管理

添加自定义端口：

```yaml
allowed_ports:
  - { port: "{{ ssh_port }}", proto: "tcp", comment: "SSH" }
  - { port: "80", proto: "tcp", comment: "HTTP" }
  - { port: "443", proto: "tcp", comment: "HTTPS" }
  - { port: "3306", proto: "tcp", comment: "MySQL" }
  - { port: "5432", proto: "tcp", comment: "PostgreSQL" }
  - { port: "6379", proto: "tcp", comment: "Redis" }
```

**添加端口后需要重新运行**：
```bash
ansible-playbook -i host.ini ansible/playbook.yml --tags firewall
```

---

### 4. 禁用某些功能

如不需要某些组件，设置为 `false`：

```yaml
install_docker: false      # 不安装 Docker
install_nginx: false       # 不安装 Nginx
install_brew: false        # 不安装 Homebrew
install_zsh: false         # 不安装 Zsh
install_fonts: false       # 不安装字体
```

---

### 5. 自定义基础包

编辑基础包列表：

```yaml
base_packages:
  - curl
  - wget
  - git
  - vim
  - htop
  - net-tools
  - build-essential
  # 添加你需要的包
  - tmux
  - screen
  - tree
  - jq
```

---

### 6. Docker 用户组

将用户添加到 docker 组：

```yaml
docker_users:
  - "{{ username }}"
  - "anotheruser"           # 可添加多个用户
```

> 注意：用户需要重新登录后才能使用 docker 命令

---

### 7. Zsh 配置

```yaml
install_zsh: true
install_ohmyzsh: true
zsh_theme: "agnoster"              # 或其他主题
zsh_plugins:
  - git
  - zsh-autosuggestions
  - zsh-syntax-highlighting
  - docker
  - kubectl                        # 如果使用 Kubernetes
  - golang                         # 如果使用 Go
```

可用主题：https://github.com/ohmyzsh/ohmyzsh/wiki/Themes

可用插件：https://github.com/ohmyzsh/ohmyzsh/wiki/Plugins

---

### 8. Nginx 配置

安装 Nginx 后的默认设置：

```yaml
install_nginx: true
```

Nginx 将自动：
- 安装最新稳定版
- 启动并设置开机自启
- 监听 80 和 443 端口（需在防火墙放行）

**自定义配置文件**：
```bash
sudo vim /etc/nginx/sites-available/default
sudo nginx -t                       # 测试配置
sudo systemctl reload nginx         # 重载配置
```

---

### 9. 字体配置

```yaml
install_fonts: true
fonts_to_install:
  - fonts-powerline
  - fonts-firacode
  # 添加更多字体
  - fonts-cascadia-code
  - fonts-jetbrains-mono
```

---

## 角色说明

### 🔧 base

**功能**：
- 更新系统包
- 安装基础开发工具
- 配置时区（Asia/Shanghai）
- 配置 locale（en_US.UTF-8）
- 系统优化

**安装的包**：
- build-essential（编译工具链）
- curl, wget（下载工具）
- git（版本控制）
- vim（编辑器）
- htop（系统监控）
- net-tools（网络工具）

**控制开关**：
```yaml
install_base_packages: true
```

---

### 👤 user

**功能**：
- 创建普通用户
- 设置用户 shell
- 配置 sudo 权限
- 添加 SSH 公钥

**配置项**：
```yaml
create_user: true
username: "sunpcm"
user_shell: "/bin/zsh"
enable_passwordless_sudo: true
ssh_authorized_keys:
  - "ssh-rsa AAAAB3..."
```

**生成的文件**：
- `/home/{{ username }}/.ssh/authorized_keys`
- `/etc/sudoers.d/{{ username }}`

---

### 🔐 security

**功能**：
- SSH 安全加固
- 修改 SSH 端口
- 禁用 root 登录
- 禁用密码认证
- 配置 SSH 保活

**修改的文件**：
- `/etc/ssh/sshd_config`（自动备份原文件）

**配置项**：
```yaml
enable_ssh_security: true
ssh_port: 2222
disable_root_login: true
disable_password_auth: true
```

**验证**：
```bash
sudo sshd -t                      # 测试配置
sudo systemctl status sshd        # 查看服务状态
```

---

### 🛡️ firewall

**功能**：
- 安装并配置 UFW 防火墙
- 设置默认策略
- 配置允许的端口
- 启用防火墙

**默认规则**：
- 拒绝所有入站
- 允许所有出站
- 允许配置中的端口

**管理命令**：
```bash
sudo ufw status                   # 查看状态
sudo ufw allow 8080/tcp          # 临时添加端口
sudo ufw delete allow 8080/tcp   # 删除规则
sudo ufw reload                  # 重载配置
```

---

### 🐳 docker

**功能**：
- 安装 Docker CE（社区版）
- 安装 Docker Compose Plugin
- 添加用户到 docker 组
- 启动 Docker 服务

**安装版本**：
- Docker Engine（最新稳定版）
- Docker Compose V2（plugin）

**配置项**：
```yaml
install_docker: true
docker_users:
  - "{{ username }}"
```

**验证**：
```bash
docker --version
docker compose version
docker ps                        # 需要重新登录后执行
```

---

### 🌐 nginx

**功能**：
- 安装 Nginx 最新稳定版
- 配置开机自启
- 设置默认站点

**配置文件位置**：
- `/etc/nginx/nginx.conf`
- `/etc/nginx/sites-available/`
- `/etc/nginx/sites-enabled/`

**常用命令**：
```bash
sudo systemctl status nginx
sudo systemctl restart nginx
sudo nginx -t                    # 测试配置
sudo tail -f /var/log/nginx/access.log
```

---

### 🍺 brew

**功能**：
- 安装 Homebrew（Linuxbrew）
- 配置环境变量

**安装后使用**：
```bash
brew install <package>
brew search <name>
brew list
brew upgrade
```

---

### 💻 shell

**功能**：
- 安装 Zsh
- 安装 Oh My Zsh
- 安装插件（autosuggestions, syntax-highlighting）
- 配置 .zshrc
- 切换默认 shell

**配置项**：
```yaml
install_zsh: true
install_ohmyzsh: true
zsh_theme: "agnoster"
zsh_plugins:
  - git
  - zsh-autosuggestions
  - zsh-syntax-highlighting
  - docker
```

**生成的文件**：
- `~/.zshrc`
- `~/.oh-my-zsh/`

**验证**：
```bash
echo $SHELL                      # 应显示 /usr/bin/zsh
zsh --version
```

---

### 🔤 fonts

**功能**：
- 安装编程字体
- 安装 Powerline 字体

**安装的字体**：
- Powerline Fonts
- FiraCode（支持连字）

**配置项**：
```yaml
install_fonts: true
fonts_to_install:
  - fonts-powerline
  - fonts-firacode
```

---

## 常见问题

### Q1: 运行后无法 SSH 连接？

**原因**：可能修改了 SSH 端口但防火墙未放行。

**解决**：
```bash
# 如果还能通过其他方式登录（如控制台）
sudo ufw allow 2222/tcp
sudo systemctl restart sshd
```

---

### Q2: Docker 命令提示权限不足？

**原因**：用户刚被添加到 docker 组，需要重新登录。

**解决**：
```bash
exit
ssh -p 2222 yourname@server
docker ps                        # 现在应该可以了
```

---

### Q3: Zsh 主题显示异常？

**原因**：终端未使用 Nerd Font 或 Powerline 字体。

**解决**：
- 在本地终端（如 Windows Terminal）安装 FiraCode Nerd Font
- 配置终端使用该字体

---

### Q4: 如何回滚 SSH 配置？

**解决**：
```bash
# 备份文件在 /etc/ssh/sshd_config.backup
sudo cp /etc/ssh/sshd_config.backup /etc/ssh/sshd_config
sudo systemctl restart sshd
```

---

### Q5: 如何只运行特定角色？

**使用 tags**：
```bash
# 只运行 Docker 角色
ansible-playbook -i host.ini ansible/playbook.yml --tags docker

# 跳过某些角色
ansible-playbook -i host.ini ansible/playbook.yml --skip-tags nginx
```

---

### Q6: 如何添加更多服务器？

编辑 `host.ini`：
```ini
[ubuntu_servers]
server1 ansible_host=192.168.1.100 ansible_user=root
server2 ansible_host=192.168.1.101 ansible_user=root
server3 ansible_host=10.0.0.50 ansible_user=admin ansible_port=2222

[ubuntu_servers:vars]
ansible_python_interpreter=/usr/bin/python3
```

---

### Q7: 密码哈希如何生成？

如果需要设置用户密码（不推荐，建议只用密钥）：

```bash
# 生成密码哈希
python3 -c "from passlib.hash import sha512_crypt; print(sha512_crypt.hash('your_password'))"

# 或使用 mkpasswd（需安装 whois 包）
mkpasswd --method=SHA-512
```

将生成的哈希填入：
```yaml
user_password: "$6$rounds=656000$..."
```

---

## 高级配置

### 使用不同的清单文件

```bash
# 开发环境
ansible-playbook -i inventory/dev.ini ansible/playbook.yml

# 生产环境
ansible-playbook -i inventory/prod.ini ansible/playbook.yml
```

---

### 使用变量覆盖

```bash
# 临时覆盖变量
ansible-playbook -i host.ini ansible/playbook.yml \
  -e "ssh_port=2222" \
  -e "install_docker=false"
```

---

### Dry-run 模式

```bash
# 测试运行（不实际执行）
ansible-playbook -i host.ini ansible/playbook.yml --check
```

---

### 详细输出

```bash
# 调试模式
ansible-playbook -i host.ini ansible/playbook.yml -vvv
```

---

### 针对特定主机

```bash
# 只配置 server1
ansible-playbook -i host.ini ansible/playbook.yml --limit server1
```

---

### 使用 Ansible Vault 加密敏感信息

```bash
# 加密变量文件
ansible-vault encrypt ansible/group_vars/all.yml

# 运行时输入密码
ansible-playbook -i host.ini ansible/playbook.yml --ask-vault-pass

# 使用密码文件
ansible-playbook -i host.ini ansible/playbook.yml --vault-password-file ~/.vault_pass
```

---

## 🔄 持续维护

### 定期更新

创建定期更新任务：

```bash
# 创建 cron 任务（服务器上）
crontab -e

# 每周日凌晨 2 点更新系统
0 2 * * 0 apt update && apt upgrade -y
```

### 配置监控

建议安装监控工具：
- Prometheus + Grafana
- Netdata
- Glances

### 日志管理

```bash
# 查看系统日志
sudo journalctl -xe

# 查看认证日志
sudo tail -f /var/log/auth.log

# 查看 Docker 日志
sudo journalctl -u docker
```

---

## 📚 参考资源

- [Ansible 官方文档](https://docs.ansible.com/)
- [Ubuntu Server Guide](https://ubuntu.com/server/docs)
- [Docker Documentation](https://docs.docker.com/)
- [Nginx Documentation](https://nginx.org/en/docs/)
- [UFW Documentation](https://help.ubuntu.com/community/UFW)
- [Oh My Zsh Wiki](https://github.com/ohmyzsh/ohmyzsh/wiki)

---

**💡 提示**：配置文件都经过精心设计，但请根据实际需求调整。安全无小事！
