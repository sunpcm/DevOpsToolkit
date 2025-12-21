# WSL Dev 快速参考

## 🚀 快速命令

### 初始安装
```bash
./bootstrap.sh
```

### 更新环境
```bash
./update.sh
```

### 完全卸载
```bash
./uninstall.sh
```

---

## 🔤 字体配置（Windows）

### 安装 FiraCode Nerd Font
```powershell
# 在 Windows PowerShell 中执行
winget install -e --id DEVCOM.FiraCodeNerdFont
```

### 配置 Windows Terminal
1. 打开设置（`Ctrl + ,`）
2. 配置文件 → Ubuntu → 外观
3. 字体 → 选择 `FiraCode Nerd Font`
4. 保存并重启终端

### 验证图标显示
```bash
ls              # 应显示文件图标
eza --icons
```

> ⚠️ 图标显示乱码？检查 Windows Terminal 字体设置

---

## 🛠️ 常用工具

### Homebrew
```bash
brew install <package>      # 安装包
brew search <name>          # 搜索包
brew list                   # 列出已安装
brew upgrade                # 更新所有包
brew cleanup                # 清理旧版本
```

### Python (uv)
```bash
uv python install 3.12      # 安装 Python 3.12
uv python list              # 列出已安装版本
uv venv                     # 创建虚拟环境
uv pip install <package>    # 安装包
```

### Node.js (nvm)
```bash
nvm install 20              # 安装 Node 20
nvm use 20                  # 使用 Node 20
nvm list                    # 列出已安装版本
nvm alias default 20        # 设置默认版本
```

### Go (goenv)
```bash
goenv install 1.21.5        # 安装 Go 1.21.5
goenv global 1.21.5         # 设置全局版本
goenv versions              # 列出已安装版本
```

### Git
```bash
git config --global user.name "Name"
git config --global user.email "email@example.com"
git config --list           # 查看配置
```

---

## 🔧 现代 CLI 工具

### eza (替代 ls)
```bash
ls                          # 自动使用 eza
ll                          # 详细列表
la                          # 显示隐藏文件
lt                          # 树状显示
```

### bat (替代 cat)
```bash
cat file.txt                # 自动使用 bat，带语法高亮
bat file1.txt file2.txt     # 查看多个文件
```

### fzf (模糊查找)
```bash
Ctrl+R                      # 搜索命令历史
Ctrl+T                      # 模糊查找文件
Alt+C                       # 模糊查找并进入目录
```

### zoxide (智能 cd)
```bash
z project                   # 跳转到包含 project 的目录
zi                          # 交互式选择目录
```

### lazygit
```bash
lazygit                     # 启动 Git TUI
```

### lazydocker
```bash
lazydocker                  # 启动 Docker TUI
```

### btop
```bash
btop                        # 系统监控
```

---

## 🐳 Docker

### 基本命令
```bash
dps                         # docker ps
dpsa                        # docker ps -a
di                          # docker images
dlog <container>            # docker logs
dlogf <container>           # docker logs -f
dexec <container>           # docker exec -it
dstop                       # 停止所有容器
drm                         # 删除所有容器
drmi                        # 删除所有镜像
dprune                      # 清理系统
```

### Docker Compose
```bash
dc                          # docker compose
dcup                        # docker compose up -d
dcdown                      # docker compose down
dclog                       # docker compose logs -f
dcps                        # docker compose ps
dcrestart                   # docker compose restart
dcbuild                     # docker compose build
```

---

## 🪟 Windows 互操作

### 剪贴板
```bash
echo "text" | clip          # 复制到 Windows 剪贴板
paste                       # 从 Windows 剪贴板粘贴
```

### 文件操作
```bash
explorer                    # 在资源管理器打开当前目录
winopen <path>              # 在资源管理器打开指定路径
winstart <file>             # 用默认应用打开文件
```

### 快捷目录
```bash
cdwin                       # Windows 用户目录
cddownloads                 # Downloads
cddesktop                   # Desktop
cddocuments                 # Documents
```

---

## 🔑 Git 别名

```bash
gs                          # git status
ga                          # git add
gc                          # git commit
gp                          # git push
gl                          # git pull
gd                          # git diff
gco                         # git checkout
gb                          # git branch
glog                        # git log --oneline --graph
```

---

## ⚙️ 配置文件位置

```bash
~/.zshrc                    # zsh 配置
~/.gitconfig                # Git 全局配置
~/.wsl-dev-backup/          # 配置备份目录
~/.oh-my-zsh/               # Oh My Zsh
~/.nvm/                     # nvm
~/.goenv/                   # goenv
~/.cargo/bin/uv             # uv
/home/linuxbrew/.linuxbrew/ # Homebrew
```

---

## 🔧 实用函数

### mkcd - 创建并进入目录
```bash
mkcd myproject              # mkdir + cd
```

### extract - 解压任意格式
```bash
extract file.tar.gz
extract file.zip
extract file.7z
```

---

## 📝 Zsh 别名

```bash
zshconfig                   # 编辑 .zshrc
reload                      # 重新加载 .zshrc
c                           # clear
..                          # cd ..
...                         # cd ../..
....                        # cd ../../..
```

---

## 🆘 故障排除

### 重新加载 shell 配置
```bash
source ~/.zshrc
# 或
exec zsh
```

### 查看安装的包
```bash
brew list
nvm list
uv python list
goenv versions
```

### 检查 Docker
```bash
docker version
docker compose version
```

### 恢复备份
```bash
ls ~/.wsl-dev-backup/
cp ~/.wsl-dev-backup/.zshrc.<timestamp> ~/.zshrc
```

### 重新运行配置
```bash
./bootstrap.sh              # 完整重新配置
```

### 只更新特定组件
```bash
cd ansible
ansible-playbook playbook.yml --tags "shell"
ansible-playbook playbook.yml --tags "git"
```

---

## 📚 更多信息

- 详细配置说明：[CONFIGURATION.md](CONFIGURATION.md)
- 完整文档：[readme.md](readme.md)
