#!/bin/bash

set -euo pipefail

# ============================================================================
# ACME.sh 安装位置修复脚本
# 功能：将错误安装的 acme.sh 移动到正确位置
# 用法：sudo bash acme-fix-install.sh
# ============================================================================

ACME_USER="acme"
ACME_HOME="/var/lib/acme"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

log_info "========================================"
log_info "ACME.sh 安装位置修复脚本"
log_info "========================================"

# 检查当前安装状态
if [[ -d "$ACME_HOME/.acme.sh" ]]; then
    log_info "发现 acme.sh 安装在: $ACME_HOME/.acme.sh"
    
    if [[ -d "$ACME_HOME/home/.acme.sh" ]]; then
        log_warn "目标位置 $ACME_HOME/home/.acme.sh 已存在，将备份旧版本"
        mv "$ACME_HOME/home/.acme.sh" "$ACME_HOME/home/.acme.sh.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    log_info "移动 acme.sh 到正确位置..."
    mv "$ACME_HOME/.acme.sh" "$ACME_HOME/home/.acme.sh"
    
    # 修复所有权
    chown -R "$ACME_USER:$ACME_USER" "$ACME_HOME/home/.acme.sh"
    
    log_info "✓ acme.sh 已移动到 $ACME_HOME/home/.acme.sh"
    
    # 更新 .profile 中的别名路径
    if [[ -f "$ACME_HOME/.profile" ]]; then
        log_info "更新 .profile 中的路径..."
        sed -i 's|alias acme.sh="/var/lib/acme/.acme.sh/acme.sh"|alias acme.sh="/var/lib/acme/home/.acme.sh/acme.sh"|g' "$ACME_HOME/.profile"
    fi
    
    # 修复 account.key 权限
    ACCOUNT_KEY="$ACME_HOME/home/.acme.sh/account.key"
    if [[ -f "$ACCOUNT_KEY" ]]; then
        chown root:acme "$ACCOUNT_KEY"
        chmod 0640 "$ACCOUNT_KEY"
        log_info "✓ account.key 权限已修复"
    fi
    
    log_info "✓ 修复完成！现在可以正常使用 acme-list 等命令"
    
elif [[ -d "$ACME_HOME/home/.acme.sh" ]]; then
    log_info "acme.sh 已在正确位置: $ACME_HOME/home/.acme.sh"
    log_info "无需修复"
else
    log_error "未找到 acme.sh 安装，请重新运行 acme-init.sh"
    exit 1
fi

# 验证修复结果
log_info "验证安装..."
if [[ -f "$ACME_HOME/home/.acme.sh/acme.sh" ]]; then
    log_info "✓ acme.sh 文件存在"
    
    # 测试 acme-list 命令
    if command -v acme-list >/dev/null 2>&1; then
        log_info "测试 acme-list 命令..."
        if sudo acme-list >/dev/null 2>&1; then
            log_info "✓ acme-list 命令正常工作"
        else
            log_warn "acme-list 命令可能有问题，但 acme.sh 已正确安装"
        fi
    fi
else
    log_error "修复失败，acme.sh 文件仍不存在"
    exit 1
fi

log_info ""
log_info "========================================"
log_info "✅ 修复完成！"
log_info "========================================"
log_info "现在可以使用以下命令："
log_info "  sudo acme-list      # 查看证书列表"
log_info "  sudo acme-add <域名> # 申请新证书"
