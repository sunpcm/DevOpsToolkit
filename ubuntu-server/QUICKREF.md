# Ubuntu Server 快速参考

## 🚀 快速命令

### 初始配置
```bash
# 1. 复制清单文件
cp host.ini.example host.ini

# 2. 编辑配置
vim host.ini
vim ansible/group_vars/all.yml

# 3. 测试连接
ansible -i host.ini ubuntu_servers -m ping

# 4. 运行配置
./bootstrap.sh
```

### 更新配置
```bash
./update.sh

# 或直接运行
ansible-playbook -i host.ini ansible/playbook.yml
```

### 只运行特定角色
```bash
# 只配置防火墙
ansible-playbook -i host.ini ansible/playbook.yml --tags firewall

# 只安装 Docker
ansible-playbook -i host.ini ansible/playbook.yml --tags docker

# 跳过某些角色
ansible-playbook -i host.ini ansible/playbook.yml --skip-tags nginx,brew
```

---

## 🔐 SSH 连接

### 首次连接（root）
```bash
ssh root@server_ip
```

### 配置后连接（新用户 + 新端口）
```bash
ssh -p 2222 username@server_ip

# 使用密钥文件
ssh -p 2222 -i ~/.ssh/id_rsa username@server_ip
```

### 生成 SSH 密钥
```bash
# ED25519（推荐）
ssh-keygen -t ed25519 -C "your_email@example.com"

# RSA（传统）
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"

# 查看公钥
cat ~/.ssh/id_ed25519.pub
```

### 简化 SSH 连接
编辑 `~/.ssh/config`：
```
Host myserver
    HostName 192.168.1.100
    Port 2222
    User sunpcm
    IdentityFile ~/.ssh/id_ed25519
```

使用：
```bash
ssh myserver
```

---

## 🛡️ 防火墙管理

### 查看状态
```bash
sudo ufw status
sudo ufw status numbered         # 显示规则编号
sudo ufw status verbose          # 详细信息
```

### 添加规则
```bash
# 允许端口
sudo ufw allow 8080/tcp
sudo ufw allow 3306              # 默认 tcp

# 允许特定 IP
sudo ufw allow from 192.168.1.100

# 允许特定 IP 访问特定端口
sudo ufw allow from 192.168.1.100 to any port 22

# 允许子网
sudo ufw allow from 192.168.1.0/24
```

### 删除规则
```bash
# 按编号删除
sudo ufw status numbered
sudo ufw delete 3

# 按规则删除
sudo ufw delete allow 8080/tcp
```

### 防火墙控制
```bash
sudo ufw enable                  # 启用
sudo ufw disable                 # 禁用
sudo ufw reload                  # 重载
sudo ufw reset                   # 重置所有规则
```

---

## 🐳 Docker 命令

### 容器管理
```bash
docker ps                        # 运行中的容器
docker ps -a                     # 所有容器
docker start <container>         # 启动
docker stop <container>          # 停止
docker restart <container>       # 重启
docker rm <container>            # 删除
docker logs <container>          # 查看日志
docker logs -f <container>       # 实时日志
docker exec -it <container> bash # 进入容器
```

### 镜像管理
```bash
docker images                    # 列出镜像
docker pull <image>              # 拉取镜像
docker rmi <image>               # 删除镜像
docker build -t name:tag .       # 构建镜像
```

### Docker Compose
```bash
docker compose up -d             # 启动服务
docker compose down              # 停止并删除
docker compose ps                # 查看服务
docker compose logs -f           # 查看日志
docker compose restart           # 重启服务
docker compose pull              # 拉取最新镜像
```

### 清理
```bash
docker system prune              # 清理未使用资源
docker system prune -a           # 清理所有未使用镜像
docker volume prune              # 清理未使用卷
```

---

## 🌐 Nginx 管理

### 服务控制
```bash
sudo systemctl start nginx       # 启动
sudo systemctl stop nginx        # 停止
sudo systemctl restart nginx     # 重启
sudo systemctl reload nginx      # 重载配置（无缝）
sudo systemctl status nginx      # 查看状态
sudo systemctl enable nginx      # 开机自启
```

### 配置管理
```bash
# 测试配置
sudo nginx -t

# 查看配置文件
sudo vim /etc/nginx/nginx.conf
sudo vim /etc/nginx/sites-available/default

# 创建新站点
sudo vim /etc/nginx/sites-available/mysite
sudo ln -s /etc/nginx/sites-available/mysite /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### 日志查看
```bash
# 访问日志
sudo tail -f /var/log/nginx/access.log

# 错误日志
sudo tail -f /var/log/nginx/error.log

# 实时监控
sudo tail -f /var/log/nginx/access.log /var/log/nginx/error.log
```

---

## 👤 用户管理

### 查看用户
```bash
whoami                           # 当前用户
id                              # 用户 ID 和组
groups                          # 所属组
cat /etc/passwd                 # 所有用户
```

### 切换用户
```bash
su - username                    # 切换用户
sudo -i                         # 切换到 root
exit                            # 退出
```

### Sudo 管理
```bash
# 查看 sudo 权限
sudo -l

# 编辑 sudoers
sudo visudo

# 查看 sudo 配置
ls -la /etc/sudoers.d/
```

---

## 📦 包管理

### APT 命令
```bash
# 更新包列表
sudo apt update

# 升级所有包
sudo apt upgrade

# 升级系统（包括内核）
sudo apt full-upgrade

# 搜索包
apt search <package>

# 安装包
sudo apt install <package>

# 删除包
sudo apt remove <package>
sudo apt purge <package>        # 同时删除配置

# 清理
sudo apt autoremove             # 删除无用依赖
sudo apt clean                  # 清理缓存
```

### Homebrew 命令
```bash
brew install <package>           # 安装
brew uninstall <package>         # 卸载
brew search <name>               # 搜索
brew list                        # 已安装列表
brew upgrade                     # 更新所有
brew update                      # 更新 Homebrew 自身
brew info <package>              # 包信息
brew cleanup                     # 清理旧版本
```

---

## 🔧 系统监控

### 系统信息
```bash
# 系统版本
lsb_release -a
uname -a

# CPU 信息
lscpu
cat /proc/cpuinfo

# 内存信息
free -h
cat /proc/meminfo

# 磁盘空间
df -h
du -sh /*                       # 各目录大小
```

### 进程监控
```bash
# 进程列表
ps aux
ps aux | grep nginx

# 实时监控
htop                            # 交互式（推荐）
top                             # 传统
```

### 网络监控
```bash
# 端口监听
sudo netstat -tlnp              # TCP 监听端口
sudo ss -tlnp                   # 更现代的方式

# 网络连接
netstat -an
ss -an

# 测试端口
telnet localhost 80
nc -zv localhost 80
```

### 日志查看
```bash
# 系统日志
sudo journalctl -xe             # 最新日志
sudo journalctl -f              # 实时日志
sudo journalctl -u nginx        # 特定服务

# 认证日志
sudo tail -f /var/log/auth.log

# 系统日志
sudo tail -f /var/log/syslog
```

---

## 💻 Shell (Zsh) 配置

### Oh My Zsh
```bash
# 更新 Oh My Zsh
omz update

# 重载配置
source ~/.zshrc

# 编辑配置
vim ~/.zshrc
```

### 插件管理
```bash
# 启用插件（编辑 .zshrc）
plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
  docker
  kubectl
)

# 手动安装插件
cd ~/.oh-my-zsh/custom/plugins
git clone <plugin-repo>
```

### 主题切换
```bash
# 编辑 .zshrc
ZSH_THEME="robbyrussell"        # 或其他主题

# 预览主题
omz theme list
omz theme use <theme-name>
```

---

## 🔍 故障排查

### SSH 问题
```bash
# 查看 SSH 服务
sudo systemctl status sshd

# 测试 SSH 配置
sudo sshd -t

# 查看 SSH 日志
sudo tail -f /var/log/auth.log

# 详细连接日志
ssh -vvv user@host
```

### 防火墙问题
```bash
# 检查防火墙状态
sudo ufw status verbose

# 临时禁用防火墙（测试用）
sudo ufw disable

# 查看规则
sudo iptables -L -n -v
```

### Docker 问题
```bash
# 查看 Docker 日志
sudo journalctl -u docker -f

# 重启 Docker
sudo systemctl restart docker

# 检查 Docker 状态
sudo systemctl status docker
docker info
```

### 磁盘空间
```bash
# 查看磁盘使用
df -h

# 查找大文件
sudo du -ah / | sort -rh | head -n 20

# 清理日志
sudo journalctl --vacuum-time=7d
```

---

## 📊 性能优化

### 查看负载
```bash
uptime                          # 系统负载
w                               # 谁在线 + 负载
```

### 内存优化
```bash
# 查看内存使用
free -h

# 清理缓存（慎用）
sudo sync
sudo sysctl vm.drop_caches=3
```

### 查看连接数
```bash
# 统计连接状态
netstat -an | grep ESTABLISHED | wc -l

# 按状态统计
netstat -an | awk '/^tcp/ {print $6}' | sort | uniq -c
```

---

## 🔄 定期维护

### 每日检查
```bash
# 系统负载
uptime

# 磁盘空间
df -h

# 检查服务
sudo systemctl status nginx docker

# 查看日志
sudo tail -100 /var/log/auth.log
```

### 每周维护
```bash
# 更新系统
sudo apt update && sudo apt upgrade -y

# 清理无用包
sudo apt autoremove -y
sudo apt clean

# 更新 Docker 镜像
docker compose pull
docker compose up -d
```

### 每月维护
```bash
# 重启服务器（更新内核后）
sudo reboot

# 检查磁盘
sudo fsck -n /dev/sda1

# 备份重要数据
tar -czf backup-$(date +%Y%m%d).tar.gz /home /etc
```

---

## 🆘 紧急恢复

### SSH 锁定
如果修改 SSH 配置后无法连接：

```bash
# 通过控制台或 VNC 登录
sudo cp /etc/ssh/sshd_config.backup /etc/ssh/sshd_config
sudo systemctl restart sshd
```

### 防火墙锁定
```bash
# 通过控制台登录
sudo ufw disable
sudo ufw allow 22/tcp
sudo ufw enable
```

### 忘记 sudo 密码
```bash
# 使用 root 账户
sudo passwd username            # 重置用户密码
```

---

## 📚 有用的命令组合

### 监控端口
```bash
# 持续监控端口 80 的连接
watch -n 1 'netstat -an | grep :80 | wc -l'
```

### 批量操作
```bash
# 停止所有 Docker 容器
docker stop $(docker ps -q)

# 删除所有停止的容器
docker rm $(docker ps -aq)
```

### 查找文件
```bash
# 查找最近修改的文件
find /var/log -type f -mtime -1

# 查找大于 100M 的文件
find / -type f -size +100M
```

---

## 🔗 配置文件位置

| 服务 | 配置文件 |
|------|---------|
| SSH | `/etc/ssh/sshd_config` |
| UFW | `/etc/ufw/` |
| Nginx | `/etc/nginx/` |
| Docker | `/etc/docker/daemon.json` |
| Zsh | `~/.zshrc` |
| Oh My Zsh | `~/.oh-my-zsh/` |

---

**💡 提示**：将常用命令添加到 `.zshrc` 的 alias 中，提高效率！

```bash
# 编辑 ~/.zshrc
alias ll='ls -lah'
alias update='sudo apt update && sudo apt upgrade -y'
alias docker-clean='docker system prune -a -f'
alias nginx-reload='sudo nginx -t && sudo systemctl reload nginx'
```
