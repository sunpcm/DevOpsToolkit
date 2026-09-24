#!/usr/bin/env bash
set -euo pipefail

# Creates and removes only synthetic logs on a marked throwaway VM.
readonly MARKER=/etc/devops-toolkit-acme-test-vm
readonly INSTALLED_CONFIG=/etc/logrotate.d/acme
readonly ACME_CONFIG=/var/lib/acme/config

[[ "${EUID}" -eq 0 ]] || {
  printf '必须以 root 身份运行。\n' >&2
  exit 1
}
[[ -f "${MARKER}" && "$(<"${MARKER}")" == 'throwaway-multipass-only' ]] || {
  printf '缺少一次性 VM 标记；拒绝运行。\n' >&2
  exit 1
}
[[ -f "${INSTALLED_CONFIG}" && ! -L "${INSTALLED_CONFIG}" ]] || {
  printf '缺少已安装的 ACME logrotate 配置。\n' >&2
  exit 1
}
[[ -d "${ACME_CONFIG}" && ! -L "${ACME_CONFIG}" ]] || {
  printf 'ACME 配置目录缺失或类型不安全。\n' >&2
  exit 1
}
command -v logrotate >/dev/null || {
  printf 'VM 缺少 logrotate；本脚本不会安装依赖。\n' >&2
  exit 1
}

IFS= read -r first_line <"${INSTALLED_CONFIG}"
[[ "${first_line}" == '/var/lib/acme/config/*.log {' ]] || {
  printf '已安装的 logrotate 目标与预期不符。\n' >&2
  exit 1
}

temporary="$(mktemp -d "${ACME_CONFIG}/.logrotate-smoke.XXXXXX")"
state_dir=''
cleanup() {
  rm -rf -- "${temporary}"
  if [[ -n "${state_dir}" ]]; then
    rm -rf -- "${state_dir}"
  fi
}
trap cleanup EXIT
state_dir="$(mktemp -d /tmp/acme-logrotate-state.XXXXXX)"
chown acme:acme "${temporary}"
chmod 0700 "${temporary}"

# Keep the installed directives; substitute only the log path and state path.
printf '%s/*.log {\n' "${temporary}" >"${state_dir}/config"
tail -n +2 "${INSTALLED_CONFIG}" >>"${state_dir}/config"
log_file="${temporary}/synthetic.log"
install -o acme -g acme -m 0600 /dev/null "${log_file}"

assert_private_log() {
  local path="$1"
  [[ -f "${path}" && ! -L "${path}" ]] || {
    printf '轮替日志缺失或类型不安全：%s\n' "${path}" >&2
    return 1
  }
  [[ "$(stat -c '%U:%G %a %h' "${path}")" == 'acme:acme 600 1' ]] || {
    printf '轮替日志 owner/mode/硬链接数不安全：%s\n' "${path}" >&2
    return 1
  }
}

printf 'synthetic ACME log, first rotation\n' | runuser --user acme -- tee -a "${log_file}" >/dev/null
logrotate --force --state "${state_dir}/status" "${state_dir}/config"
assert_private_log "${log_file}"
assert_private_log "${log_file}.1"

printf 'synthetic ACME log, second rotation\n' | runuser --user acme -- tee -a "${log_file}" >/dev/null
logrotate --force --state "${state_dir}/status" "${state_dir}/config"
assert_private_log "${log_file}"
assert_private_log "${log_file}.1"
assert_private_log "${log_file}.2.gz"

printf '一次性 VM 的 ACME 日志双轮替、压缩与权限验证通过。\n'
