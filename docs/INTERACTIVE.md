# 交互式向导

交互式向导适合单台机器首次初始化或临时配置。Release 安装后运行：

```bash
devops-toolkit
```

从源码运行：

```bash
./bin/devops-toolkit
```

它不会替代 Ansible Playbook，而是收集输入后调用现有的 WSL2、Ubuntu 或 user-only Playbook。因此权限边界、幂等逻辑和手工入口保持一致。

## 支持的选择

### WSL2

- 创建或更新普通用户。
- 配置目标用户密码哈希和 SSH 公钥。
- 选择 Shell、Git、uv、Node.js、Go、Linuxbrew 和 WSL 集成。
- 可检查 Docker Desktop WSL Integration。

必须在 WSL 内以 root 运行：

```bash
sudo ./bin/devops-toolkit
```

### Ubuntu

- 已经以 root 登录新服务器时，可选择“当前服务器本地执行”，无需再次配置 SSH inventory。
- 也可以从 macOS、WSL 或其他控制端通过 SSH 配置远程服务器。
- 输入服务器、当前 SSH 端口和 root 认证方式。
- 创建或更新普通用户。
- 公钥既可直接粘贴，也可输入 `.pub` 文件路径。
- 选择 Linuxbrew、Docker、Nginx、UFW 和 OpenSSH 管理。
- 启用 Nginx 和 UFW 时自动放行 80/443。
- 支持输入其他 TCP/UDP 放行端口。

当前 Ubuntu Playbook仍要求 root SSH 登录，因此向导不会禁用 root 登录。使用密钥连接且给目标用户配置了公钥时，可以选择禁用 SSH 密码认证。

新服务器本地初始化的推荐流程：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/sunpcm/DevOpsToolkit/main/install.sh)"
```

首个 Release 发布前，或需要审查源码时使用 clone：

```bash
apt update
apt install -y git ansible
git clone https://github.com/sunpcm/DevOpsToolkit.git
cd DevOpsToolkit
ansible-galaxy collection install -r ansible/requirements.yml
./bin/devops-toolkit
```

选择 `Ubuntu` → `当前服务器本地执行`。首次初始化不会自动关闭 SSH 密码认证，应先从另一终端验证新用户密钥登录。

### user-only

- 使用普通用户密码或密钥登录。
- 只选择当前用户需要的开发环境。
- 默认不使用 sudo。
- 可显式允许 sudo 安装白名单基础依赖。

## 敏感信息处理

- SSH 私钥只输入文件路径，向导不会读取或复制私钥内容。
- SSH 密码由 Ansible 的 `--ask-pass` 直接询问。
- sudo 密码由 Ansible 的 `--ask-become-pass` 直接询问。
- 新用户本地密码使用隐藏输入，立即通过 `openssl passwd -6` 转为哈希。
- 临时 inventory 和变量文件位于系统临时目录，目录仅当前用户可访问，文件权限为 `0600`。
- 正常完成、执行失败或 Ctrl+C 后自动删除临时文件。
- 向导不会关闭 SSH 主机指纹校验，也不会自动接受未知指纹。

密码 SSH 认证通常要求控制端安装 `sshpass`；更推荐使用带密码保护的 SSH 私钥。

首次连接服务器前应人工确认指纹：

```bash
ssh root@SERVER
```

## 交互式与配置文件的取舍

交互式向导不保存选择，每次运行都需要重新确认，适合少量机器和人工操作。

以下场景继续使用 inventory、Vault 和原始入口：

- CI/CD。
- 多台服务器批量部署。
- 需要代码审查的生产配置。
- 需要长期保存并重复使用相同配置。

原始入口保持不变：

```bash
sudo ./bin/wsl-bootstrap developer
./bin/ubuntu-bootstrap ansible/inventories/ubuntu.ini developer
./bin/user-only ansible/inventories/user-only.ini
```
