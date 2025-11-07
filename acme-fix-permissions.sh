#!/bin/bash

set -euo pipefail

# ============================================================================
# 修复 ACME 证书安装权限问题
# ============================================================================

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# 检查是否 root
if [[ $EUID -ne 0 ]]; then
    log_error "此脚本必须以 root 身份运行"
    exit 1
fi

ACME_USER="acme"
ACME_CERTS_DIR="/var/lib/acme/certs"

log_info "修复 ACME 证书安装权限问题..."

# 检查 ssl-cert 组是否存在
if ! getent group ssl-cert >/dev/null 2>&1; then
    log_info "创建 ssl-cert 组..."
    groupadd ssl-cert
fi

# 将 acme 用户加入 ssl-cert 组
if ! groups "$ACME_USER" | grep -q ssl-cert; then
    log_info "将 acme 用户加入 ssl-cert 组..."
    usermod -aG ssl-cert "$ACME_USER"
else
    log_info "✓ acme 用户已在 ssl-cert 组中"
fi

# 修复证书目录权限
log_info "修复证书目录权限..."
chown root:ssl-cert "$ACME_CERTS_DIR"
chmod 0775 "$ACME_CERTS_DIR"

log_info "✓ 权限修复完成"
log_info ""
log_info "现在可以重新尝试证书安装："
log_info "  sudo acme-add biubiuniu.com dns"
log_info ""
log_info "或者手动完成安装："
log_info "  sudo -u acme bash -c 'cd /var/lib/acme/home && ./.acme.sh/acme.sh --install-cert -d biubiuniu.com --key-file /var/lib/acme/certs/biubiuniu.com.key --fullchain-file /var/lib/acme/certs/biubiuniu.com.crt --ca-file /var/lib/acme/certs/biubiuniu.com.ca --reloadcmd \"systemctl reload nginx || true\"'"
