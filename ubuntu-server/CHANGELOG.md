# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2025-12-21

### 🎉 Initial Release

完整的 Ubuntu Server 自动化配置方案。

### ✨ Features

#### 核心功能
- ✅ 基于 Ansible 的模块化配置
- ✅ 9 个独立可配置的角色
- ✅ 变量驱动的灵活配置
- ✅ 幂等性设计，可重复执行

#### 安全配置
- ✅ 创建普通用户 + SSH 密钥认证
- ✅ SSH 安全加固（禁用 root、密钥登录、自定义端口）
- ✅ UFW 防火墙自动配置
- ✅ 免密 sudo 支持

#### 开发环境
- ✅ Docker CE + Docker Compose Plugin
- ✅ Nginx Web 服务器
- ✅ Homebrew 包管理器
- ✅ Zsh + Oh My Zsh 终端环境
- ✅ 编程字体（Powerline、FiraCode）

#### 系统优化
- ✅ 基础包安装（build-essential, git, vim, htop 等）
- ✅ 时区配置（Asia/Shanghai）
- ✅ Locale 配置（en_US.UTF-8）
- ✅ 自动系统更新

### 📂 项目结构

```
ubuntu-server/
├── bootstrap.sh              # 主入口脚本
├── update.sh                # 更新脚本
├── ansible.cfg              # Ansible 配置
├── host.ini.example         # 主机清单模板
├── README.md                # 项目文档
├── CONFIGURATION.md         # 详细配置指南
├── QUICKREF.md              # 快速参考
├── CHANGELOG.md             # 变更日志
└── ansible/
    ├── playbook.yml         # 主 Playbook
    ├── group_vars/
    │   └── all.yml          # 全局变量配置
    └── roles/
        ├── base/            # 基础系统配置
        ├── user/            # 用户管理
        ├── security/        # SSH 安全
        ├── firewall/        # UFW 防火墙
        ├── docker/          # Docker CE
        ├── nginx/           # Nginx
        ├── brew/            # Homebrew
        ├── shell/           # Zsh + Oh My Zsh
        └── fonts/           # 编程字体
```

### 🔧 角色详情

#### base
- 系统更新（apt update & upgrade）
- 安装基础开发包
- 配置系统 locale（en_US.UTF-8）
- 设置时区（Asia/Shanghai）
- 安装常用工具

#### user
- 创建普通用户
- 配置用户 shell
- 设置 SSH 公钥认证
- 配置 sudo 权限（可选免密）

#### security
- SSH 配置文件备份
- 修改 SSH 端口
- 禁用 root 登录
- 禁用密码认证
- 配置 SSH 保活参数

#### firewall
- 安装 UFW
- 配置默认策略（deny incoming, allow outgoing）
- 开放指定端口
- 启用防火墙

#### docker
- 添加 Docker 官方 GPG 密钥
- 添加 Docker 仓库
- 安装 Docker CE + Compose Plugin
- 将用户添加到 docker 组
- 启动 Docker 服务

#### nginx
- 安装 Nginx 最新稳定版
- 启动服务
- 配置开机自启

#### brew
- 安装 Homebrew/Linuxbrew
- 配置环境变量
- 添加到 shell 配置

#### shell
- 安装 Zsh
- 安装 Oh My Zsh 框架
- 安装插件（zsh-autosuggestions, zsh-syntax-highlighting）
- 配置 .zshrc
- 切换默认 shell
- 生成配置完成提示

#### fonts
- 安装 Powerline 字体
- 安装 FiraCode 编程字体

### 📖 文档

- **README.md**：项目介绍、快速开始、系统要求、安装步骤
- **CONFIGURATION.md**：详细配置指南、角色说明、常见问题、高级配置
- **QUICKREF.md**：快速参考、常用命令、故障排查、维护清单

### 🎯 设计理念

1. **安全优先**：默认禁用不安全的配置，强制使用密钥认证
2. **模块化**：每个功能独立角色，可自由组合
3. **灵活配置**：所有选项通过变量控制，易于定制
4. **幂等性**：可安全重复执行，不会破坏现有配置
5. **生产就绪**：经过测试，可直接用于生产环境

### 🚀 支持的系统

- Ubuntu 20.04 LTS
- Ubuntu 22.04 LTS  
- Ubuntu 24.04 LTS

### 📝 配置选项

#### 用户管理
- `create_user`: 是否创建用户
- `username`: 用户名
- `user_shell`: 默认 shell
- `enable_passwordless_sudo`: 免密 sudo

#### SSH 安全
- `enable_ssh_security`: 启用 SSH 加固
- `ssh_port`: SSH 端口
- `disable_root_login`: 禁用 root 登录
- `disable_password_auth`: 禁用密码认证
- `ssh_authorized_keys`: SSH 公钥列表

#### 防火墙
- `enable_firewall`: 启用防火墙
- `allowed_ports`: 允许的端口列表

#### 组件安装
- `install_base_packages`: 基础包
- `install_docker`: Docker CE
- `install_nginx`: Nginx
- `install_brew`: Homebrew
- `install_zsh`: Zsh + Oh My Zsh
- `install_fonts`: 编程字体

### 🔐 安全特性

- **SSH 密钥认证**：强制使用 SSH 密钥，禁用密码登录
- **非 root 用户**：创建普通用户，禁用 root 远程登录
- **防火墙保护**：UFW 默认拒绝入站，仅开放必要端口
- **端口修改**：支持修改 SSH 默认端口
- **最小权限**：按需配置 sudo 权限

### ⚠️ 重要提醒

1. **首次运行前**：
   - 务必配置 SSH 公钥
   - 检查 host.ini 配置
   - 确认防火墙端口设置

2. **配置 SSH 时**：
   - 保持当前连接不断开
   - 在新终端测试新连接
   - 确认可连接后再断开旧会话

3. **Docker 使用**：
   - 用户添加到 docker 组后需重新登录
   - 验证 `docker ps` 命令可用

4. **防火墙配置**：
   - 确保 SSH 端口在允许列表中
   - 修改端口后记得更新防火墙规则

### 🛠️ 脚本说明

#### bootstrap.sh
- 检查 host.ini 是否存在
- 安装 Ansible（如果需要）
- 显示配置摘要
- 运行 Ansible playbook

#### update.sh
- 重新运行 playbook
- 应用配置变更
- 更新已安装组件

### 📦 依赖

**控制机要求**：
- Ansible 2.9+
- Python 3.6+
- SSH 客户端

**目标机器要求**：
- Ubuntu 20.04/22.04/24.04
- Python 3
- SSH 服务

### 🔄 更新方法

修改配置后：
```bash
./update.sh
```

或针对特定角色：
```bash
ansible-playbook -i host.ini ansible/playbook.yml --tags docker
```

### 🐛 已知问题

无重大已知问题。

### 📊 测试环境

- ✅ Ubuntu 22.04 LTS (x86_64)
- ✅ Ubuntu 24.04 LTS (x86_64)
- ✅ 本地虚拟机测试
- ✅ 云服务器测试

### 🙏 致谢

本项目参考和借鉴了：
- Ansible 官方最佳实践
- Ubuntu Server 官方文档
- 社区安全加固指南

---

## 未来计划

### 🎯 计划中的功能

- [ ] 添加 fail2ban 角色（防暴力破解）
- [ ] 添加监控角色（Prometheus、Netdata）
- [ ] 添加备份角色（自动备份配置）
- [ ] 添加 SSL/TLS 证书管理（Let's Encrypt）
- [ ] 添加数据库角色（MySQL、PostgreSQL、Redis）
- [ ] 添加日志管理（rsyslog、Logrotate）
- [ ] 支持多服务器批量配置
- [ ] 添加回滚功能
- [ ] Web UI 配置界面

### 🔮 长期目标

- 支持更多 Linux 发行版（Debian、CentOS）
- 容器化部署选项
- 自动化测试套件
- CI/CD 集成示例

---

**更新日期**：2025-12-21  
**版本**：1.0.0  
**维护者**：sunpcm
