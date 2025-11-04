# 安全配置示例
# =================

# 这个文件展示了如何安全地管理 Ansible 项目中的敏感信息

## 1. host.ini 安全配置

### 开发环境（可以使用密码）
```ini
[servers]
dev.example.com ansible_ssh_pass=dev_password ansible_become_pass=dev_password

[all:vars]
ansible_user=ubuntu
ansible_port=22
```

### 生产环境（建议使用密钥认证）
```ini
[servers]
prod.example.com

[all:vars]
ansible_user=deploy
ansible_port=6626
# 不包含密码，使用 SSH 密钥认证
```

## 2. 使用 Ansible Vault 加密密码

### 创建加密文件
```bash
ansible-vault create secrets.yml
```

### secrets.yml 内容示例
```yaml
vault_ssh_password: "your_secure_password"
vault_sudo_password: "your_sudo_password"
vault_database_password: "db_password_123"
```

### 在 host.ini 中引用
```ini
[servers]
server.example.com ansible_ssh_pass="{{ vault_ssh_password }}" ansible_become_pass="{{ vault_sudo_password }}"
```

### 运行时使用
```bash
ansible-playbook -i host.ini playbook.yml --ask-vault-pass
```

## 3. 环境变量方式

### 设置环境变量
```bash
export ANSIBLE_SSH_PASS="your_password"
export ANSIBLE_BECOME_PASS="your_sudo_password"
```

### 在配置中使用
```ini
[all:vars]
ansible_ssh_pass="{{ lookup('env', 'ANSIBLE_SSH_PASS') }}"
ansible_become_pass="{{ lookup('env', 'ANSIBLE_BECOME_PASS') }}"
```

## 4. 文件权限建议

```bash
# 设置正确的文件权限
chmod 600 host.ini          # 只有所有者可读写
chmod 600 secrets.yml       # 加密文件权限
chmod 700 .ssh/             # SSH 目录权限
chmod 600 .ssh/id_rsa       # 私钥权限
chmod 644 .ssh/id_rsa.pub   # 公钥权限
```

## 5. Git 安全实践

### 永远不要提交的文件
- 包含明文密码的 host.ini
- SSH 私钥文件
- .vault_pass 文件
- 任何包含敏感信息的配置文件

### 可以提交的文件
- playbook.yml
- .zshrc.server (已清理敏感信息)
- README.md
- .gitignore
- host.ini.example (示例文件，不含真实密码)

## 6. 团队协作建议

1. **使用统一的 Vault 密码**：团队成员共享同一个 vault 密码
2. **分环境管理**：不同环境使用不同的配置文件
3. **权限控制**：限制对生产环境配置的访问
4. **定期轮换**：定期更换密码和密钥
