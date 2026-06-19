# ACME.sh 自动化证书管理系统使用教程

## 📖 简介

这是一套基于 ACME.sh 的生产级 HTTPS 证书自动化管理系统，专为新服务器快速部署和长期运维设计。通过一键初始化，您可以获得完整的证书申请、安装、续期和管理能力。

## 🚀 快速开始

### 前置条件

- Linux 服务器 (Ubuntu 18+, CentOS 7+, Debian 9+)
- root 权限
- 域名已解析到服务器 (webroot 验证) 或 DNS API 访问权限
- 互联网连接

### 一键初始化

```bash
# 下载脚本
wget https://raw.githubusercontent.com/sunpcm/DevOpsToolkit/main/AcmeConfig/acme-init.sh

# 使用默认邮箱初始化
sudo bash acme-init.sh

# 或指定您的邮箱
sudo bash acme-init.sh admin@yourdomain.com
```

初始化完成后，系统将提供三个管理命令：
- `acme-add` - 申请证书
- `acme-list` - 查询证书
- `acme-revoke` - 吊销证书

## 🛠️ 核心功能详解

### 1. 证书申请 (acme-add)

#### 基础用法

```bash
# 单域名证书
sudo acme-add example.com

# 多域名证书 (SAN)
sudo acme-add example.com www.example.com api.example.com

# 泛域名证书 (需要 DNS 验证) 👍👍👍
sudo acme-add example.com '*.example.com' dns
```

#### 验证方式

**Webroot 验证 (推荐)**
```bash
# 自动模式 - 使用默认 webroot
sudo acme-add example.com

# 指定 webroot 目录
WEBROOT=/var/www/mysite sudo acme-add example.com

# 手动指定验证方式
sudo acme-add example.com webroot
```

**DNS 验证 (适用泛域名)**
```bash
# 使用 DNS 验证
sudo acme-add example.com dns

# 泛域名证书
sudo acme-add example.com '*.example.com' dns
```

#### 高级配置

**配置 DNS API (以 Cloudflare 为例)**
```bash
# 创建 DNS 配置文件
sudo mkdir -p /etc/acme
sudo cat > /etc/acme/dns-config <<'EOF'
# Cloudflare API 配置
export CF_Token="your-cloudflare-token"
export CF_Account_ID="your-account-id"
EOF

sudo chmod 600 /etc/acme/dns-config
sudo chown root:root /etc/acme/dns-config

# 在脚本中加载配置
source /etc/acme/dns-config
sudo acme-add example.com '*.example.com' dns
```

### 2. 证书查询 (acme-list)

```bash
# 查看所有证书
sudo acme-list

# 查询特定域名
sudo acme-list example.com

# 查看证书文件状态
sudo acme-list | grep -A 5 -B 5 example.com
```

### 3. 证书管理 (acme-revoke)

```bash
# 交互式吊销 (推荐)
sudo acme-revoke example.com

# 强制吊销 (无需确认)
sudo acme-revoke example.com --force
```

### 4. 自动续期系统

**查看续期状态**
```bash
# 查看定时器状态
systemctl status acme-renew.timer

# 查看最近的续期日志
journalctl -u acme-renew.service --since "1 week ago"

# 手动触发续期测试
sudo systemctl start acme-renew.service
```

**续期配置**
- 检查时间：每日 02:00
- 随机延迟：5 分钟内
- 自动重载：nginx/openresty 服务
- 日志保留：30 天轮替

## 🔧 技术实现

### 系统架构

```text
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   acme-init.sh  │───▶│  系统初始化      │───▶│   工具链生成     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   用户创建      │    │  目录结构        │    │  管理脚本       │
│   权限配置      │    │  权限设置        │    │  systemd 服务   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### 核心技术栈

**基础技术**

- **Bash Scripting**: 主要开发语言，版本要求 4.0+
- **ACME.sh**: 证书签发客户端，支持 100+ CA 和 DNS 提供商
- **systemd**: 服务管理和定时任务
- **logrotate**: 日志轮替管理

**安全技术**

- **预下载校验**: 脚本开始就下载并校验 acme.sh，提前发现网络问题
- **umask 控制**: 强制私钥文件 600 权限
- **用户隔离**: 专用 acme 系统用户，无登录权限
- **权限分离**: 证书文件 root:ssl-cert 组控制
- **脚本校验**: 防止 curl|sh 供应链攻击

**安装策略优化**
```text
传统方式: 创建用户 -> 安装 acme.sh -> 配置
新策略:   预下载校验 -> 创建用户 -> 安装 -> 配置
        ↑ 提前失败，避免半成品状态
```

**Web 服务器集成**

- **Nginx/OpenResty**: 自动检测和重载
- **Apache**: 支持扩展 (需自定义 reloadcmd)
- **其他 Web 服务器**: 通过配置支持

### 目录结构设计

```text
/var/lib/acme/                    # 主目录
├── .profile                      # acme 用户环境配置
├── home/                         # acme.sh 工作目录
│   ├── .acme.sh/                # acme.sh 程序文件
│   │   ├── acme.sh              # 主程序
│   │   ├── account.key          # ACME 账户私钥 (root:acme 640)
│   │   └── ca/                  # CA 配置
│   └── logs/                    # 临时日志
├── certs/                       # 证书存储 (root:ssl-cert 750)
│   ├── example.com.key          # 私钥 (root:ssl-cert 640)
│   ├── example.com.crt          # 完整证书链 (644)
│   └── example.com.ca           # CA 证书 (644)
├── config/                      # 配置和日志 (acme:acme 700)
│   ├── install.log              # 安装日志
│   ├── issue-domain.log         # 申请日志
│   └── install-domain.log       # 安装日志
└── logs/                        # 运行日志 (acme:acme 700)
```

### 权限模型

```text
用户/组权限设计:

acme 用户 (系统用户)
├── 主目录: /var/lib/acme (755)
├── 登录: nologin (安全)
├── 权限: 证书申请和管理
└── umask: 077 (新文件默认 600)

ssl-cert 组
├── 成员: www-data (nginx), acme
├── 用途: 访问证书文件
└── 权限: 读取证书和私钥

文件权限:
├── 私钥文件: 640 (root:ssl-cert)
├── 证书文件: 644 (root:ssl-cert) 
├── 账户密钥: 640 (root:acme)
└── 配置文件: 600 (root:root)
```

## 🔒 安全特性

### 已实施的安全措施

**1. 供应链安全**
```bash
# 防止 curl|sh 攻击
TEMP_SCRIPT=$(mktemp)
curl -fsSL https://get.acme.sh -o "$TEMP_SCRIPT"

# 基本内容校验
if ! grep -q "acme.sh" "$TEMP_SCRIPT"; then
    log_error "脚本可能被劫持"
    exit 1
fi

sh "$TEMP_SCRIPT"
rm -f "$TEMP_SCRIPT"
```

**2. 私钥权限保护**
```bash
# 强制 umask 设置
echo 'umask 077' > /var/lib/acme/.profile

# 所有操作都加载安全配置
sudo -u acme bash -c "
    source /var/lib/acme/.profile
    ./.acme.sh/acme.sh --issue -d example.com
"
```

**3. ACME 账户保护**
```bash
# account.key 权限加固
chown root:acme /var/lib/acme/home/.acme.sh/account.key
chmod 0640 /var/lib/acme/home/.acme.sh/account.key
```

**4. 续期黑洞防护**
```bash
# 健壮的重载命令
if systemctl is-active -q nginx; then
    RELOAD_CMD="systemctl reload nginx || true"
else
    RELOAD_CMD="true"  # 不让重载失败影响续期
fi
```

### 安全最佳实践

**DNS API 密钥管理**
```bash
# ❌ 错误方式 - 明文暴露
export CF_Token="your-token"
sudo acme-add example.com dns

# ✅ 正确方式 - 文件保护
echo 'export CF_Token="your-token"' | sudo tee /etc/acme/dns-config
sudo chmod 600 /etc/acme/dns-config
source /etc/acme/dns-config
sudo acme-add example.com dns
```

## 📊 监控和维护

### 证书监控

**定期检查证书状态**
```bash
#!/bin/bash
# cert-monitor.sh - 证书监控脚本

sudo acme-list | while read line; do
    if [[ $line =~ "Main_Domain:" ]]; then
        domain=$(echo $line | awk '{print $2}')
        echo "检查域名: $domain"
        
        # 检查证书有效期
        if openssl x509 -in "/var/lib/acme/certs/${domain}.crt" -noout -checkend 864000 2>/dev/null; then
            echo "✓ $domain 证书正常 (10天内不会过期)"
        else
            echo "⚠ $domain 证书即将过期"
        fi
    fi
done
```

**续期日志监控**
```bash
# 查看今日续期情况
journalctl -u acme-renew.service --since today

# 设置日志告警 (配合 logwatch 或其他工具)
grep -i "error\|fail" /var/log/syslog | grep acme-renew
```

### 性能优化

**大量证书场景**
```bash
# 分批处理多域名
domains=("site1.com" "site2.com" "site3.com")
for domain in "${domains[@]}"; do
    sudo acme-add "$domain"
    sleep 5  # 避免频率限制
done
```

**资源使用监控**
```bash
# 检查磁盘空间
du -sh /var/lib/acme/

# 检查日志大小
du -sh /var/lib/acme/config/
```

## 🔧 故障排查

### 常见问题解决

**1. 证书申请失败**
```bash
# 检查域名解析
dig +short example.com

# 检查 webroot 权限
ls -la /var/www/html/.well-known/acme-challenge/

# 查看详细错误
tail -f /var/lib/acme/config/issue-example.com.log
```

**2. nginx 无法读取证书**
```bash
# 检查用户组权限
groups www-data

# 测试证书访问
sudo -u www-data cat /var/lib/acme/certs/example.com.key

# 检查 SELinux (CentOS/RHEL)
sestatus
setsebool -P httpd_can_network_connect 1
```

**3. 续期失败**
```bash
# 手动测试续期
sudo systemctl start acme-renew.service

# 查看续期日志
journalctl -u acme-renew.service -f

# 检查 acme.sh 状态
sudo -u acme bash -c "
    cd /var/lib/acme/home
    ./.acme.sh/acme.sh --list
"
```

### 诊断工具

**系统健康检查**
```bash
#!/bin/bash
# acme-health-check.sh

echo "=== ACME 系统健康检查 ==="

# 检查服务状态
echo "1. 检查 systemd 服务:"
systemctl is-enabled acme-renew.timer
systemctl is-active acme-renew.timer

# 检查用户和权限
echo "2. 检查用户权限:"
id acme
groups www-data | grep -q ssl-cert && echo "✓ www-data 在 ssl-cert 组" || echo "✗ www-data 不在 ssl-cert 组"

# 检查证书文件
echo "3. 检查证书目录:"
ls -la /var/lib/acme/certs/ | head -5

# 检查磁盘空间
echo "4. 检查磁盘使用:"
df -h /var/lib/acme

echo "=== 检查完成 ==="
```

## 🚀 高级用法

### 自定义配置

**修改默认 webroot**
```bash
# 方法1: 环境变量
WEBROOT=/var/www/mysite sudo acme-add example.com

# 方法2: 修改脚本默认值
sed -i 's|/var/www/html|/var/www/mysite|' /usr/local/bin/acme-add
```

**配置自定义 DNS 提供商**
```bash
# 修改 DNS 提供商 (以阿里云为例)
sudo sed -i 's/dns_cf/dns_ali/' /usr/local/bin/acme-add

# 配置阿里云 API
cat > /etc/acme/dns-config <<'EOF'
export Ali_Key="your-key"
export Ali_Secret="your-secret"
EOF
```

### 批量管理

**批量申请证书**
```bash
#!/bin/bash
# batch-cert.sh - 批量证书申请

domains=(
    "site1.com"
    "site2.com www.site2.com"
    "api.site3.com"
)

for domain_group in "${domains[@]}"; do
    echo "申请证书: $domain_group"
    sudo acme-add $domain_group
    
    if [ $? -eq 0 ]; then
        echo "✓ $domain_group 申请成功"
    else
        echo "✗ $domain_group 申请失败"
    fi
    
    sleep 10  # 避免频率限制
done
```

### 集成其他服务

**Docker 容器支持**
```bash
# 将证书挂载到容器
docker run -d \
  -v /var/lib/acme/certs:/etc/ssl/certs:ro \
  -v /var/lib/acme/certs:/etc/ssl/private:ro \
  nginx:alpine
```

**Ansible 集成**
```yaml
# playbook.yml
- name: 初始化 ACME 系统
  script: acme-init.sh {{ admin_email }}
  
- name: 申请证书
  command: acme-add {{ item }}
  with_items:
    - "{{ ssl_domains }}"
```

## 📋 最佳实践

### 生产环境建议

1. **备份策略**
```bash
# 定期备份 ACME 配置
tar -czf acme-backup-$(date +%Y%m%d).tar.gz /var/lib/acme/
```

2. **监控告警**
```bash
# 添加到 crontab
0 8 * * * /usr/local/bin/cert-monitor.sh | mail -s "证书状态报告" admin@example.com
```

3. **安全审计**
```bash
# 定期检查文件权限
find /var/lib/acme -type f -perm /o+r -ls
```

4. **更新维护**
```bash
# 定期更新 acme.sh
sudo -u acme bash -c "
    cd /var/lib/acme/home
    ./.acme.sh/acme.sh --upgrade
"
```

## 📚 扩展阅读

- [ACME.sh 官方文档](https://github.com/acmesh-official/acme.sh)
- [Let's Encrypt 最佳实践](https://letsencrypt.org/docs/)
- [Nginx SSL 配置指南](https://ssl-config.mozilla.org/)
- [证书透明度监控](https://crt.sh/)

---

**版本信息**: v2.0 (生产级加固版)  
**维护者**: 系统管理员  
**更新时间**: 2025-11-07  
**适用系统**: Ubuntu 18+, CentOS 7+, Debian 9+
