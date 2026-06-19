# DevOpsToolkit

基于 Ansible 的 Linux 环境配置工具，明确区分系统配置、root 配置和普通用户配置。

## 选择你的场景

| 场景 | 登录/执行身份 | 会修改系统 | 会创建用户 | 用户配置范围 | 入口 |
|---|---|---:|---:|---|---|
| WSL2 初始化 | WSL 内 root | 是 | 是 | root 最小配置 + 目标用户完整配置 | `bin/wsl-bootstrap` |
| Ubuntu 服务器初始化 | SSH root | 是 | 是 | root 最小配置 + 目标用户完整配置 | `bin/ubuntu-bootstrap` |
| 已有用户配置 | 普通用户密码或密钥 | 默认否 | 否 | 只修改当前用户 HOME | `bin/user-only` |

如果不确定该选哪个：

- 新装 WSL2，需要创建开发用户：选择 WSL2 初始化。
- 新买 Ubuntu VPS，需要初始化系统和创建运维用户：选择 Ubuntu 服务器初始化。
- 公司服务器已有账号，只想配置自己的 Shell 和开发工具：选择 user-only。

## 快速开始

### 1. 安装控制端依赖

```bash
git clone https://github.com/sunpcm/DevOpsToolkit.git
cd DevOpsToolkit

# Ubuntu / WSL2
sudo apt update
sudo apt install -y ansible git

# 安装项目需要的 Ansible collection
ansible-galaxy collection install -r ansible/requirements.yml
```

macOS 控制端可使用：

```bash
brew install ansible
ansible-galaxy collection install -r ansible/requirements.yml
```

### 2. 配置公共变量

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

### 3. 执行对应入口

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
- user-only 默认不使用 sudo；缺少 `curl`、`git`、`zsh` 时会退出。
- 设置 `user_only_allow_system_dependencies=true` 后，只允许通过 sudo 安装上述白名单依赖。
- 不在 inventory 中保存 SSH 密码或 sudo 密码。
- 默认开启 SSH 主机指纹校验。
- 用户 Shell 配置写入 `~/.config/devops-toolkit/shell.zsh`，仅在现有 `.zshrc` 中增加一个托管 source 区块。

## 文档

- [三个场景完整使用指南](docs/GETTING_STARTED.md)
- [配置、安全与故障排查](docs/CONFIGURATION.md)
- [ACME 证书管理](AcmeConfig/README.md)
- [历史文档](archive/README.md)

## 验证代码

```bash
./tests/verify-ansible.sh
```

该检查覆盖新旧入口的 Bash 语法、全部新 Playbook 的 Ansible 语法，以及全局提权、主机指纹和弃用模块检查。

## 兼容入口

以下入口暂时保留，但只作为兼容包装，不应再用于新文档或自动化：

- `wsl-dev/bootstrap.sh`
- `ubuntu-server/bootstrap.sh`
- 根目录 `playbook.yml`
- 根目录 `setup_wsl.yml`

历史实现仍保留在原目录，待新流程完成真实环境验证后再删除。
