#!/usr/bin/env bash
set -euo pipefail

readonly ACME_USER="acme"
readonly ACME_GROUP="acme"
readonly ACME_SECRETS_GROUP="acme-secrets"
readonly CERT_GROUP="ssl-cert"
readonly ACME_BASE="/var/lib/acme"
readonly ACME_USER_HOME="${ACME_BASE}/home"
readonly ACME_CONFIG_DIR="${ACME_BASE}/config"
readonly ACME_STAGING_DIR="${ACME_BASE}/staging"
readonly ACME_QUEUE_DIR="${ACME_BASE}/deploy-queue"
readonly ACME_FAILED_DIR="${ACME_BASE}/deploy-failed"
readonly ACME_CERTS_DIR="${ACME_BASE}/certs"
readonly ACME_ETC_DIR="/etc/acme"
readonly ACME_SH_VERSION="3.1.6"
readonly ACME_SH_COMMIT="807da6498377ee5e0cf43a78091f46f12dc59a89"
readonly ACME_SH_ARCHIVE_SHA256="ddbe1bcbd1a44a2623a2af167ebdc678669e6e2eb396742f2d1d28e02dc14220"
readonly ACME_SH_ARCHIVE_URL="https://codeload.github.com/acmesh-official/acme.sh/tar.gz/${ACME_SH_COMMIT}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR=""
ACME_EMAIL=""
ACME_ARCHIVE_SOURCE=""

info() {
  printf '==> %s\n' "$*"
}

warn() {
  printf '警告：%s\n' "$*" >&2
}

fail() {
  printf '错误：%s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
    rm -rf "${TEMP_DIR}"
  fi
}

usage() {
  cat <<'EOF'
用法：sudo ./acme-init.sh [--archive /绝对路径/acme.sh.tar.gz] <账户邮箱>

从经过审核的完整 AcmeConfig 目录初始化 ACME 环境。该脚本拒绝默认占位邮箱，
不会从可变 main 分支下载或执行安装脚本。--archive 适用于离线安装，但仍强制
校验脚本内固定的归档 SHA256。
EOF
}

validate_email() {
  local email="$1"
  [[ "${email}" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}$ ]] && \
    [[ "${email}" != *..* && "${email}" != .* && "${email}" != *@.* ]]
}

assert_no_symlink() {
  local path
  for path in "$@"; do
    [[ ! -L "${path}" ]] || fail "拒绝符号链接路径：${path}"
  done
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --archive)
        [[ $# -ge 2 ]] || fail "--archive 缺少路径。"
        ACME_ARCHIVE_SOURCE="$2"
        shift 2
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      -*)
        fail "未知参数：$1"
        ;;
      *)
        [[ -z "${ACME_EMAIL}" ]] || fail "只能提供一个账户邮箱。"
        ACME_EMAIL="$1"
        shift
        ;;
    esac
  done
}

require_commands() {
  local command_name
  for command_name in \
    curl getent gpasswd groupadd id install openssl python3 runuser sha256sum systemctl tar useradd usermod; do
    command -v "${command_name}" >/dev/null 2>&1 || fail "缺少命令：${command_name}"
  done
}

require_assets() {
  local path
  for path in \
    "${SCRIPT_DIR}/libexec/acme-manager" \
    "${SCRIPT_DIR}/bin/acme-add" \
    "${SCRIPT_DIR}/bin/acme-list" \
    "${SCRIPT_DIR}/bin/acme-revoke" \
    "${SCRIPT_DIR}/systemd/acme-renew.service" \
    "${SCRIPT_DIR}/systemd/acme-renew.timer" \
    "${SCRIPT_DIR}/systemd/acme-deploy.service" \
    "${SCRIPT_DIR}/systemd/acme-deploy.path" \
    "${SCRIPT_DIR}/logrotate/acme"; do
    [[ -f "${path}" && ! -L "${path}" ]] || fail "缺少或拒绝符号链接资产：${path}"
  done
}

ensure_groups_and_account() {
  local nologin_shell
  nologin_shell="$(command -v nologin || true)"
  [[ -n "${nologin_shell}" ]] || nologin_shell="/usr/sbin/nologin"
  [[ -x "${nologin_shell}" ]] || fail "找不到 nologin shell。"

  getent group "${ACME_GROUP}" >/dev/null || groupadd --system "${ACME_GROUP}"
  getent group "${ACME_SECRETS_GROUP}" >/dev/null || groupadd --system "${ACME_SECRETS_GROUP}"
  getent group "${CERT_GROUP}" >/dev/null || groupadd --system "${CERT_GROUP}"

  if id "${ACME_USER}" >/dev/null 2>&1; then
    usermod \
      --gid "${ACME_GROUP}" \
      --home "${ACME_BASE}" \
      --shell "${nologin_shell}" \
      "${ACME_USER}"
  else
    useradd \
      --system \
      --gid "${ACME_GROUP}" \
      --home-dir "${ACME_BASE}" \
      --shell "${nologin_shell}" \
      --no-create-home \
      --comment "ACME certificate management" \
      "${ACME_USER}"
  fi
  # acme 是专用账户；显式覆盖附加组可清除旧部署遗留的 ssl-cert 读取权限。
  usermod --groups "${ACME_SECRETS_GROUP}" "${ACME_USER}"

  if id www-data >/dev/null 2>&1; then
    local -a web_groups=()
    local group_name
    read -r -a web_groups <<<"$(id -nG www-data)"
    for group_name in "${web_groups[@]}"; do
      if [[ "${group_name}" == "${ACME_GROUP}" || "${group_name}" == "${ACME_SECRETS_GROUP}" ]]; then
        gpasswd --delete www-data "${group_name}" >/dev/null
      fi
    done
    usermod --append --groups "${CERT_GROUP}" www-data
  else
    warn "未找到 www-data；需要读取证书私钥的服务账户必须由管理员显式加入 ${CERT_GROUP}。"
  fi
}

ensure_directories() {
  assert_no_symlink \
    "${ACME_BASE}" \
    "${ACME_USER_HOME}" \
    "${ACME_USER_HOME}/.acme.sh" \
    "${ACME_USER_HOME}/.acme.sh/acme.sh" \
    "${ACME_CONFIG_DIR}" \
    "${ACME_CONFIG_DIR}/certs" \
    "${ACME_BASE}/logs" \
    "${ACME_STAGING_DIR}" \
    "${ACME_QUEUE_DIR}" \
    "${ACME_FAILED_DIR}" \
    "${ACME_CERTS_DIR}" \
    "${ACME_ETC_DIR}"
  install -d -o root -g root -m 0755 "${ACME_BASE}"
  install -d -o "${ACME_USER}" -g "${ACME_GROUP}" -m 0700 \
    "${ACME_USER_HOME}" \
    "${ACME_CONFIG_DIR}" \
    "${ACME_BASE}/logs" \
    "${ACME_STAGING_DIR}" \
    "${ACME_QUEUE_DIR}"
  install -d -o root -g root -m 0700 "${ACME_FAILED_DIR}"
  install -d -o root -g "${CERT_GROUP}" -m 0750 "${ACME_CERTS_DIR}"
  install -d -o root -g "${ACME_SECRETS_GROUP}" -m 0750 "${ACME_ETC_DIR}"

  if [[ -e "${ACME_ETC_DIR}/dns-config" ]]; then
    [[ -f "${ACME_ETC_DIR}/dns-config" && ! -L "${ACME_ETC_DIR}/dns-config" ]] || \
      fail "拒绝非普通 DNS 配置：${ACME_ETC_DIR}/dns-config"
    chown root:"${ACME_SECRETS_GROUP}" "${ACME_ETC_DIR}/dns-config"
    chmod 0640 "${ACME_ETC_DIR}/dns-config"
  fi

  if [[ ! -e "${ACME_ETC_DIR}/reload-services" ]]; then
    TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/devops-toolkit-acme-init.XXXXXX")"
    printf '%s\n' \
      '# One active systemd service per line. All listed active services reload after deployment.' \
      'nginx.service' \
      'openresty.service' \
      'xray.service' >"${TEMP_DIR}/reload-services"
    install -o root -g root -m 0644 \
      "${TEMP_DIR}/reload-services" "${ACME_ETC_DIR}/reload-services"
  else
    [[ -f "${ACME_ETC_DIR}/reload-services" && ! -L "${ACME_ETC_DIR}/reload-services" ]] || \
      fail "拒绝非普通 reload service 配置。"
    chown root:root "${ACME_ETC_DIR}/reload-services"
    chmod 0644 "${ACME_ETC_DIR}/reload-services"
  fi
}

installed_source_matches() {
  local marker="${ACME_ETC_DIR}/acme-source"
  local installed_sha256 actual_sha256
  [[ -x "${ACME_USER_HOME}/.acme.sh/acme.sh" && \
     ! -L "${ACME_USER_HOME}/.acme.sh/acme.sh" && \
     -f "${marker}" && ! -L "${marker}" ]] || return 1
  grep -Fxq "version=${ACME_SH_VERSION}" "${marker}" || return 1
  grep -Fxq "commit=${ACME_SH_COMMIT}" "${marker}" || return 1
  grep -Fxq "archive_sha256=${ACME_SH_ARCHIVE_SHA256}" "${marker}" || return 1
  installed_sha256="$(sed -nE 's/^installed_sha256=([0-9a-f]{64})$/\1/p' "${marker}")"
  [[ "${#installed_sha256}" -eq 64 ]] || return 1
  actual_sha256="$(sha256sum "${ACME_USER_HOME}/.acme.sh/acme.sh")"
  [[ "${actual_sha256%% *}" == "${installed_sha256}" ]]
}

install_pinned_acme() {
  if installed_source_matches; then
    info "复用已固定的 acme.sh ${ACME_SH_VERSION}"
    return 0
  fi

  [[ -n "${TEMP_DIR}" ]] || \
    TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/devops-toolkit-acme-init.XXXXXX")"
  chmod 0711 "${TEMP_DIR}"
  local archive="${TEMP_DIR}/acme.sh.tar.gz"
  local extracted="${TEMP_DIR}/extracted"
  local source_directory="${extracted}/acme.sh-${ACME_SH_COMMIT}"

  if [[ -n "${ACME_ARCHIVE_SOURCE}" ]]; then
    [[ "${ACME_ARCHIVE_SOURCE}" == /* ]] || fail "--archive 必须是绝对路径。"
    [[ -f "${ACME_ARCHIVE_SOURCE}" && ! -L "${ACME_ARCHIVE_SOURCE}" ]] || \
      fail "离线归档不存在、不是普通文件或为符号链接。"
    info "复制并校验离线 acme.sh ${ACME_SH_VERSION} 归档"
    install -o root -g root -m 0600 "${ACME_ARCHIVE_SOURCE}" "${archive}"
  else
    info "下载并校验 acme.sh ${ACME_SH_VERSION} (${ACME_SH_COMMIT})"
    curl --fail --silent --show-error --location \
      --retry 5 --retry-delay 2 --retry-all-errors \
      --connect-timeout 30 --speed-limit 1024 --speed-time 30 \
      "${ACME_SH_ARCHIVE_URL}" --output "${archive}"
  fi
  printf '%s  %s\n' "${ACME_SH_ARCHIVE_SHA256}" "${archive}" | sha256sum --check --strict

  install -d -o "${ACME_USER}" -g "${ACME_GROUP}" -m 0700 "${extracted}"
  python3 - "${archive}" "${extracted}" "acme.sh-${ACME_SH_COMMIT}" <<'PY'
import sys
import tarfile
from pathlib import Path, PurePosixPath

archive, destination, expected_root = sys.argv[1:]
with tarfile.open(archive, "r:gz") as package:
    members = package.getmembers()
    if not members:
        raise SystemExit("empty acme.sh archive")
    for member in members:
        path = PurePosixPath(member.name)
        if path.is_absolute() or ".." in path.parts:
            raise SystemExit(f"unsafe archive path: {member.name}")
        if not path.parts or path.parts[0] != expected_root:
            raise SystemExit(f"unexpected archive root: {member.name}")
        if not (member.isfile() or member.isdir()):
            raise SystemExit(f"unsupported archive entry: {member.name}")
    package.extractall(Path(destination))
PY
  chown -R "${ACME_USER}:${ACME_GROUP}" "${extracted}"

  (
    cd "${source_directory}"
    runuser --user "${ACME_USER}" -- env -i \
      HOME="${ACME_USER_HOME}" PATH=/usr/local/bin:/usr/bin:/bin \
      ./acme.sh \
      --install \
      --home "${ACME_USER_HOME}/.acme.sh" \
      --config-home "${ACME_CONFIG_DIR}" \
      --cert-home "${ACME_CONFIG_DIR}/certs" \
      --email "${ACME_EMAIL}" \
      --no-cron \
      --no-profile
  )

  local installed_sha256
  installed_sha256="$(sha256sum "${ACME_USER_HOME}/.acme.sh/acme.sh")"
  printf 'version=%s\ncommit=%s\narchive_sha256=%s\ninstalled_sha256=%s\n' \
    "${ACME_SH_VERSION}" "${ACME_SH_COMMIT}" "${ACME_SH_ARCHIVE_SHA256}" \
    "${installed_sha256%% *}" \
    >"${TEMP_DIR}/acme-source"
  install -o root -g root -m 0644 "${TEMP_DIR}/acme-source" "${ACME_ETC_DIR}/acme-source"
}

install_managed_assets() {
  info "安装权限分离的 ACME 管理器和 systemd units"
  install -D -o root -g root -m 0755 \
    "${SCRIPT_DIR}/libexec/acme-manager" \
    /usr/local/libexec/devops-toolkit/acme-manager
  install -D -o root -g root -m 0755 "${SCRIPT_DIR}/bin/acme-add" /usr/local/bin/acme-add
  install -D -o root -g root -m 0755 "${SCRIPT_DIR}/bin/acme-list" /usr/local/bin/acme-list
  install -D -o root -g root -m 0755 "${SCRIPT_DIR}/bin/acme-revoke" /usr/local/bin/acme-revoke

  install -o root -g root -m 0644 \
    "${SCRIPT_DIR}/systemd/acme-renew.service" \
    "${SCRIPT_DIR}/systemd/acme-renew.timer" \
    "${SCRIPT_DIR}/systemd/acme-deploy.service" \
    "${SCRIPT_DIR}/systemd/acme-deploy.path" \
    /etc/systemd/system/
  install -o root -g root -m 0644 "${SCRIPT_DIR}/logrotate/acme" /etc/logrotate.d/acme

  python3 -m py_compile /usr/local/libexec/devops-toolkit/acme-manager
  if command -v systemd-analyze >/dev/null 2>&1; then
    systemd-analyze verify \
      /etc/systemd/system/acme-renew.service \
      /etc/systemd/system/acme-renew.timer \
      /etc/systemd/system/acme-deploy.service \
      /etc/systemd/system/acme-deploy.path
  fi
  systemctl daemon-reload
  systemctl enable --now acme-renew.timer acme-deploy.path
}

configure_default_ca() {
  info "设置默认 CA 为 Let's Encrypt"
  runuser --user "${ACME_USER}" -- env -i \
    HOME="${ACME_USER_HOME}" PATH=/usr/local/bin:/usr/bin:/bin \
    "${ACME_USER_HOME}/.acme.sh/acme.sh" \
    --set-default-ca \
    --server letsencrypt \
    --auto-upgrade 0 \
    --home "${ACME_USER_HOME}/.acme.sh" \
    --config-home "${ACME_CONFIG_DIR}"
}

main() {
  parse_arguments "$@"
  [[ "${EUID}" -eq 0 ]] || fail "必须以 root 身份运行。"
  [[ -n "${ACME_EMAIL}" ]] || {
    usage
    exit 2
  }
  validate_email "${ACME_EMAIL}" || fail "请提供有效的 ACME 账户邮箱。"
  readonly ACME_EMAIL ACME_ARCHIVE_SOURCE

  require_commands
  require_assets
  umask 077
  trap cleanup EXIT INT TERM

  ensure_groups_and_account
  ensure_directories
  install_pinned_acme
  install_managed_assets
  configure_default_ca

  info "ACME 环境初始化完成"
  printf '%s\n' \
    "下一步：" \
    "  1. DNS 验证时，以严格 KEY=value 格式创建 ${ACME_ETC_DIR}/dns-config，并设为 root:${ACME_SECRETS_GROUP} 0640。" \
    "  2. 运行 sudo acme-add example.com，或 sudo acme-add example.com '*.example.com' dns。" \
    "  3. 使用 sudo acme-list 和 systemctl status acme-renew.timer acme-deploy.path 验证状态。"
}

main "$@"
