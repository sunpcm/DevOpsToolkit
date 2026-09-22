#!/usr/bin/env bash
set -euo pipefail

readonly ACME_BASE="/var/lib/acme"
readonly ACME_ETC="/etc/acme"
readonly DEFAULT_BACKUP_ROOT="/var/backups/devops-toolkit-acme"

APPLY=0
BACKUP_ROOT="${DEFAULT_BACKUP_ROOT}"

usage() {
  cat <<'EOF'
用法：sudo ./acme-cleanup.sh [--yes] [--backup-dir /绝对路径]

默认只显示清理范围，不修改系统。传入 --yes 后，脚本会先创建仅 root 可读的
备份，再停用 unit 并删除 DevOpsToolkit ACME 的固定路径。不会删除系统用户或组。
EOF
}

fail() {
  printf '错误：%s\n' "$*" >&2
  exit 1
}

info() {
  printf '==> %s\n' "$*"
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes)
        APPLY=1
        shift
        ;;
      --backup-dir)
        [[ $# -ge 2 ]] || fail "--backup-dir 缺少路径。"
        BACKUP_ROOT="$2"
        shift 2
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        fail "未知参数：$1"
        ;;
    esac
  done
}

validate_fixed_paths() {
  local resolved_backup_root
  [[ "${ACME_BASE}" == "/var/lib/acme" ]] || fail "ACME_BASE 安全校验失败。"
  [[ "${ACME_ETC}" == "/etc/acme" ]] || fail "ACME_ETC 安全校验失败。"
  [[ "${BACKUP_ROOT}" == /* && "${BACKUP_ROOT}" != "/" ]] || \
    fail "备份目录必须是非根目录的绝对路径。"
  [[ "/${BACKUP_ROOT#/}" != *"/../"* && "${BACKUP_ROOT}" != */.. ]] || \
    fail "备份目录不得包含 ..。"
  resolved_backup_root="$(realpath -m -- "${BACKUP_ROOT}")"
  case "${resolved_backup_root}" in
    / | "${ACME_BASE}" | "${ACME_BASE}"/* | "${ACME_ETC}" | "${ACME_ETC}"/*)
      fail "备份目录与待清理目录重叠：${resolved_backup_root}"
      ;;
  esac
}

print_scope() {
  cat <<EOF
将备份（如存在）：
  ${ACME_BASE}
  ${ACME_ETC}

将停用：
  acme-renew.timer
  acme-renew.service
  acme-deploy.path
  acme-deploy.service

将删除：
  ${ACME_BASE}
  ${ACME_ETC}
  /usr/local/libexec/devops-toolkit/acme-manager
  /usr/local/bin/acme-add
  /usr/local/bin/acme-list
  /usr/local/bin/acme-revoke
  /etc/systemd/system/acme-renew.service
  /etc/systemd/system/acme-renew.timer
  /etc/systemd/system/acme-deploy.service
  /etc/systemd/system/acme-deploy.path
  /etc/logrotate.d/acme

不会删除：acme 用户、acme/acme-secrets/ssl-cert 组。
EOF
}

create_backup() {
  local timestamp backup_directory archive
  local -a relative_paths=()
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  backup_directory="${BACKUP_ROOT}/${timestamp}"
  archive="${backup_directory}/acme-state.tar.gz"

  [[ ! -L "${BACKUP_ROOT}" ]] || fail "拒绝符号链接备份目录。"
  [[ ! -e "${backup_directory}" ]] || fail "备份目标已存在：${backup_directory}"
  install -d -o root -g root -m 0700 "${BACKUP_ROOT}" "${backup_directory}"
  [[ -d "${BACKUP_ROOT}" && ! -L "${BACKUP_ROOT}" ]] || fail "拒绝符号链接备份目录。"
  [[ -d "${backup_directory}" && ! -L "${backup_directory}" ]] || \
    fail "拒绝符号链接备份目标。"

  [[ ! -e "${ACME_BASE}" ]] || relative_paths+=("${ACME_BASE#/}")
  [[ ! -e "${ACME_ETC}" ]] || relative_paths+=("${ACME_ETC#/}")
  if ((${#relative_paths[@]} == 0)); then
    printf '未发现 ACME 状态目录；无需创建状态归档。\n' >"${backup_directory}/EMPTY"
    chmod 0600 "${backup_directory}/EMPTY"
  else
    tar --create --gzip --file "${archive}" --directory / -- "${relative_paths[@]}"
    chown root:root "${archive}"
    chmod 0600 "${archive}"
  fi

  printf 'created_utc=%s\nacme_base=%s\nacme_etc=%s\n' \
    "${timestamp}" "${ACME_BASE}" "${ACME_ETC}" >"${backup_directory}/MANIFEST"
  chmod 0600 "${backup_directory}/MANIFEST"
  info "备份已创建：${backup_directory}"
}

stop_units() {
  local unit
  for unit in acme-renew.timer acme-renew.service acme-deploy.path acme-deploy.service; do
    systemctl disable --now "${unit}" >/dev/null 2>&1 || true
  done
}

remove_managed_paths() {
  rm -f -- \
    /usr/local/libexec/devops-toolkit/acme-manager \
    /usr/local/bin/acme-add \
    /usr/local/bin/acme-list \
    /usr/local/bin/acme-revoke \
    /etc/systemd/system/acme-renew.service \
    /etc/systemd/system/acme-renew.timer \
    /etc/systemd/system/acme-deploy.service \
    /etc/systemd/system/acme-deploy.path \
    /etc/logrotate.d/acme
  rm -rf -- "${ACME_BASE}" "${ACME_ETC}"
  systemctl daemon-reload
  systemctl reset-failed \
    acme-renew.service acme-deploy.service >/dev/null 2>&1 || true
}

main() {
  parse_arguments "$@"
  [[ "${EUID}" -eq 0 ]] || fail "必须以 root 身份运行。"
  command -v install >/dev/null 2>&1 || fail "缺少命令：install"
  command -v realpath >/dev/null 2>&1 || fail "缺少命令：realpath"
  command -v systemctl >/dev/null 2>&1 || fail "缺少命令：systemctl"
  command -v tar >/dev/null 2>&1 || fail "缺少命令：tar"
  validate_fixed_paths
  print_scope

  if [[ "${APPLY}" -ne 1 ]]; then
    info "以上为 dry-run；未修改系统。确认后使用 --yes。"
    return 0
  fi

  umask 077
  create_backup
  stop_units
  remove_managed_paths
  info "清理完成；备份保留在 ${BACKUP_ROOT}。"
}

main "$@"
