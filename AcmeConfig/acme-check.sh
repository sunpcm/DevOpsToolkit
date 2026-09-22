#!/usr/bin/env bash
set -euo pipefail

readonly ACME_USER="acme"
readonly ACME_GROUP="acme"
readonly ACME_SECRETS_GROUP="acme-secrets"
readonly CERT_GROUP="ssl-cert"
readonly ACME_BASE="/var/lib/acme"
readonly ACME_ETC="/etc/acme"
readonly EXPECTED_VERSION="3.1.6"
readonly EXPECTED_COMMIT="807da6498377ee5e0cf43a78091f46f12dc59a89"
readonly EXPECTED_ARCHIVE_SHA256="ddbe1bcbd1a44a2623a2af167ebdc678669e6e2eb396742f2d1d28e02dc14220"

FAILURES=0
WARNINGS=0

pass() {
  printf '[PASS] %s\n' "$*"
}

warn() {
  WARNINGS=$((WARNINGS + 1))
  printf '[WARN] %s\n' "$*" >&2
}

fail_check() {
  FAILURES=$((FAILURES + 1))
  printf '[FAIL] %s\n' "$*" >&2
}

group_contains_user() {
  local user="$1"
  local expected_group="$2"
  local group_name
  local -a groups=()
  read -r -a groups <<<"$(id -nG "${user}")"
  for group_name in "${groups[@]}"; do
    [[ "${group_name}" != "${expected_group}" ]] || return 0
  done
  return 1
}

check_account_boundaries() {
  local shell primary_group
  printf '\n== 账户与组边界 ==\n'
  if ! id "${ACME_USER}" >/dev/null 2>&1; then
    fail_check "缺少 ${ACME_USER} 系统账户。"
    return
  fi

  shell="$(getent passwd "${ACME_USER}" | cut -d: -f7)"
  primary_group="$(id -gn "${ACME_USER}")"
  if [[ "${shell}" == */nologin ]]; then
    pass "acme 使用 nologin shell。"
  else
    fail_check "acme shell 不是 nologin：${shell}"
  fi
  if [[ "${primary_group}" == "${ACME_GROUP}" ]]; then
    pass "acme 主组正确。"
  else
    fail_check "acme 主组应为 ${ACME_GROUP}，实际为 ${primary_group}。"
  fi
  if group_contains_user "${ACME_USER}" "${ACME_SECRETS_GROUP}"; then
    pass "acme 可读取 DNS 密钥。"
  else
    fail_check "acme 不在 ${ACME_SECRETS_GROUP}。"
  fi
  if group_contains_user "${ACME_USER}" "${CERT_GROUP}"; then
    fail_check "acme 不应属于 ${CERT_GROUP}；续期进程不应读取已部署私钥。"
  else
    pass "acme 与证书消费者组已隔离。"
  fi

  if id www-data >/dev/null 2>&1; then
    if group_contains_user www-data "${CERT_GROUP}"; then
      pass "www-data 可读取已部署私钥。"
    else
      warn "www-data 不在 ${CERT_GROUP}；使用其他服务账户时可忽略。"
    fi
    if group_contains_user www-data "${ACME_SECRETS_GROUP}"; then
      fail_check "www-data 不得属于 ${ACME_SECRETS_GROUP}。"
    else
      pass "www-data 无 DNS 密钥读取权限。"
    fi
  fi
}

check_path() {
  local path="$1"
  local expected_type="$2"
  local expected_owner="$3"
  local expected_mode="$4"
  local actual_owner actual_mode

  if [[ "${expected_type}" == "dir" ]]; then
    [[ -d "${path}" && ! -L "${path}" ]] || {
      fail_check "目录缺失或类型不安全：${path}"
      return
    }
  else
    [[ -f "${path}" && ! -L "${path}" ]] || {
      fail_check "文件缺失或类型不安全：${path}"
      return
    }
  fi
  actual_owner="$(stat -c '%U:%G' "${path}")"
  actual_mode="$(stat -c '%a' "${path}")"
  if [[ "${actual_owner}" == "${expected_owner}" && "${actual_mode}" == "${expected_mode}" ]]; then
    pass "${path} = ${actual_owner} ${actual_mode}。"
  else
    fail_check "${path} 期望 ${expected_owner} ${expected_mode}，实际 ${actual_owner} ${actual_mode}。"
  fi
}

check_filesystem() {
  printf '\n== 文件系统权限 ==\n'
  check_path "${ACME_BASE}" dir root:root 755
  check_path "${ACME_BASE}/home" dir acme:acme 700
  check_path "${ACME_BASE}/config" dir acme:acme 700
  check_path "${ACME_BASE}/staging" dir acme:acme 700
  check_path "${ACME_BASE}/deploy-queue" dir acme:acme 700
  check_path "${ACME_BASE}/deploy-failed" dir root:root 700
  check_path "${ACME_BASE}/certs" dir root:ssl-cert 750
  check_path "${ACME_ETC}" dir root:acme-secrets 750

  check_path /usr/local/libexec/devops-toolkit/acme-manager file root:root 755
  check_path /usr/local/bin/acme-add file root:root 755
  check_path /usr/local/bin/acme-list file root:root 755
  check_path /usr/local/bin/acme-revoke file root:root 755
  check_path /etc/acme/reload-services file root:root 644

  if [[ -e /etc/acme/dns-config ]]; then
    check_path /etc/acme/dns-config file root:acme-secrets 640
  else
    warn "未配置 /etc/acme/dns-config；仅使用 webroot 时可忽略。"
  fi
}

check_source_pin() {
  local marker="${ACME_ETC}/acme-source"
  local installed_sha256 actual_sha256
  printf '\n== 上游来源锁定 ==\n'
  check_path "${marker}" file root:root 644
  [[ -f "${marker}" && ! -L "${marker}" ]] || return
  if grep -Fxq "version=${EXPECTED_VERSION}" "${marker}" && \
     grep -Fxq "commit=${EXPECTED_COMMIT}" "${marker}" && \
     grep -Fxq "archive_sha256=${EXPECTED_ARCHIVE_SHA256}" "${marker}"; then
    pass "acme.sh 版本、提交和归档 SHA256 与仓库锁定值一致。"
  else
    fail_check "acme.sh 来源 marker 与仓库锁定值不一致。"
  fi
  installed_sha256="$(sed -nE 's/^installed_sha256=([0-9a-f]{64})$/\1/p' "${marker}")"
  if [[ "${#installed_sha256}" -ne 64 ]]; then
    fail_check "acme.sh 已安装程序缺少 SHA256 marker。"
    return
  fi
  if [[ ! -f "${ACME_BASE}/home/.acme.sh/acme.sh" ]]; then
    fail_check "acme.sh 已安装程序不存在。"
    return
  fi
  actual_sha256="$(sha256sum "${ACME_BASE}/home/.acme.sh/acme.sh")"
  if [[ "${actual_sha256%% *}" == "${installed_sha256}" ]]; then
    pass "acme.sh 已安装程序 SHA256 匹配。"
  else
    fail_check "acme.sh 已安装程序 SHA256 与 marker 不匹配。"
  fi
}

check_systemd() {
  local unit
  printf '\n== systemd 调度与沙箱 ==\n'
  for unit in acme-renew.service acme-renew.timer acme-deploy.service acme-deploy.path; do
    check_path "/etc/systemd/system/${unit}" file root:root 644
  done
  if command -v systemd-analyze >/dev/null 2>&1 && \
     systemd-analyze verify \
       /etc/systemd/system/acme-renew.service \
       /etc/systemd/system/acme-renew.timer \
       /etc/systemd/system/acme-deploy.service \
       /etc/systemd/system/acme-deploy.path >/dev/null; then
    pass "systemd-analyze verify 通过。"
  else
    fail_check "systemd unit 静态校验失败或 systemd-analyze 不可用。"
  fi

  for unit in acme-renew.timer acme-deploy.path; do
    if systemctl is-enabled --quiet "${unit}"; then
      pass "${unit} 已启用。"
    else
      fail_check "${unit} 未启用。"
    fi
    if systemctl is-active --quiet "${unit}"; then
      pass "${unit} 运行中。"
    else
      fail_check "${unit} 未运行。"
    fi
  done
}

check_certificate_material() {
  local path mode owner
  local -a keys=() certificates=() symlinks=() pending=() failed=()
  printf '\n== 证书与队列 ==\n'
  if [[ ! -d "${ACME_BASE}/certs" ]]; then
    fail_check "证书目录不存在。"
    return
  fi

  mapfile -d '' keys < <(find "${ACME_BASE}/certs" -maxdepth 1 -type f -name '*.key' -print0)
  mapfile -d '' certificates < <(find "${ACME_BASE}/certs" -maxdepth 1 -type f \( -name '*.crt' -o -name '*.ca' \) -print0)
  mapfile -d '' symlinks < <(find "${ACME_BASE}/certs" -maxdepth 1 -type l -print0)
  if ((${#symlinks[@]} == 0)); then
    pass "证书目录中无符号链接。"
  else
    fail_check "证书目录中存在 ${#symlinks[@]} 个符号链接。"
  fi

  for path in "${keys[@]}"; do
    mode="$(stat -c '%a' "${path}")"
    owner="$(stat -c '%U:%G' "${path}")"
    [[ "${mode}" == 640 && "${owner}" == root:ssl-cert ]] || \
      fail_check "私钥权限异常：${path} = ${owner} ${mode}"
    openssl pkey -in "${path}" -noout >/dev/null 2>&1 || \
      fail_check "私钥 PEM 无法解析：${path}"
  done
  for path in "${certificates[@]}"; do
    mode="$(stat -c '%a' "${path}")"
    owner="$(stat -c '%U:%G' "${path}")"
    [[ "${mode}" == 644 && "${owner}" == root:ssl-cert ]] || \
      fail_check "证书权限异常：${path} = ${owner} ${mode}"
    openssl x509 -in "${path}" -noout >/dev/null 2>&1 || \
      fail_check "证书 PEM 无法解析：${path}"
  done
  pass "已检查 ${#keys[@]} 个私钥和 ${#certificates[@]} 个证书文件。"

  mapfile -d '' pending < <(find "${ACME_BASE}/deploy-queue" -mindepth 1 -maxdepth 1 -print0)
  mapfile -d '' failed < <(find "${ACME_BASE}/deploy-failed" -mindepth 1 -maxdepth 1 -print0)
  ((${#pending[@]} == 0)) || warn "存在 ${#pending[@]} 个待部署请求。"
  ((${#failed[@]} == 0)) || warn "存在 ${#failed[@]} 个隔离的失败请求。"
}

check_acme_client() {
  local executable="${ACME_BASE}/home/.acme.sh/acme.sh"
  printf '\n== ACME 客户端 ==\n'
  if [[ ! -x "${executable}" || -L "${executable}" ]]; then
    fail_check "acme.sh 缺失、不可执行或为符号链接。"
    return
  fi
  if runuser --user "${ACME_USER}" -- env HOME="${ACME_BASE}/home" \
       "${executable}" --version >/dev/null; then
    pass "acme.sh 可由非特权账户执行。"
  else
    fail_check "acme.sh 版本命令执行失败。"
  fi
}

main() {
  [[ "${EUID}" -eq 0 ]] || {
    printf '错误：必须以 root 身份运行。\n' >&2
    exit 1
  }
  check_account_boundaries
  check_filesystem
  check_source_pin
  check_systemd
  check_certificate_material
  check_acme_client

  printf '\n检查完成：%d 个失败，%d 个警告。\n' "${FAILURES}" "${WARNINGS}"
  ((FAILURES == 0))
}

main "$@"
