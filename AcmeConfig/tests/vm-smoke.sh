#!/usr/bin/env bash
set -euo pipefail

# Destructive to the disposable VM's ACME state. Never run on a real host.
readonly MARKER=/etc/devops-toolkit-acme-test-vm
readonly TEST_UNIT=/etc/systemd/system/acme-test-consumer.service
readonly TEST_RELOAD=/run/acme-test-reloaded
readonly TEST_UNIT_SECONDARY=/etc/systemd/system/acme-test-secondary.service
readonly TEST_RELOAD_SECONDARY=/run/acme-test-secondary-reloaded
readonly RELOAD_CONFIG=/etc/acme/reload-services

[[ "${EUID}" -eq 0 ]] || {
  printf '必须以 root 身份运行。\n' >&2
  exit 1
}
[[ -f "${MARKER}" && "$(<"${MARKER}")" == 'throwaway-multipass-only' ]] || {
  printf '缺少一次性 VM 标记；拒绝运行。\n' >&2
  exit 1
}
[[ -d /var/lib/acme/staging && -f "${RELOAD_CONFIG}" ]] || {
  printf 'ACME 初始化未完成。\n' >&2
  exit 1
}
systemctl stop acme-deploy.path
systemctl reset-failed acme-deploy.service
rm -f -- \
  /var/lib/acme/staging/evil.example.com.key \
  /var/lib/acme/staging/evil.example.com.crt \
  /var/lib/acme/staging/evil.example.com.ca \
  /var/lib/acme/deploy-queue/evil.example.com

temporary="$(mktemp -d /tmp/acme-vm-smoke.XXXXXX)"
cp -- "${RELOAD_CONFIG}" "${temporary}/reload-services"

cleanup() {
  systemctl stop acme-test-consumer.service >/dev/null 2>&1 || true
  systemctl stop acme-test-secondary.service >/dev/null 2>&1 || true
  systemctl stop acme-deploy.path >/dev/null 2>&1 || true
  cp -- "${temporary}/reload-services" "${RELOAD_CONFIG}"
  chown root:root "${RELOAD_CONFIG}"
  chmod 0644 "${RELOAD_CONFIG}"
  rm -f -- \
    "${TEST_UNIT}" "${TEST_RELOAD}" \
    "${TEST_UNIT_SECONDARY}" "${TEST_RELOAD_SECONDARY}"
  systemctl daemon-reload
  systemctl start acme-deploy.path >/dev/null 2>&1 || true
  rm -rf -- "${temporary}"
}
trap cleanup EXIT

systemctl stop acme-deploy.path
printf '%s\n' \
  '[Unit]' \
  'Description=Disposable ACME reload test consumer' \
  '' \
  '[Service]' \
  'Type=simple' \
  'ExecStart=/usr/bin/sleep infinity' \
  'ExecReload=/usr/bin/touch /run/acme-test-reloaded' \
  >"${TEST_UNIT}"
printf '%s\n' \
  '[Unit]' \
  'Description=Disposable secondary ACME reload test consumer' \
  '' \
  '[Service]' \
  'Type=simple' \
  'ExecStart=/usr/bin/sleep infinity' \
  'ExecReload=/usr/bin/touch /run/acme-test-secondary-reloaded' \
  >"${TEST_UNIT_SECONDARY}"
chown root:root "${TEST_UNIT}" "${TEST_UNIT_SECONDARY}"
chmod 0644 "${TEST_UNIT}" "${TEST_UNIT_SECONDARY}"
printf '%s\n' \
  'acme-test-consumer.service' \
  'acme-test-secondary.service' \
  'acme-test-inactive.service' \
  >"${RELOAD_CONFIG}"
chown root:root "${RELOAD_CONFIG}"
chmod 0644 "${RELOAD_CONFIG}"
systemctl daemon-reload
systemctl start acme-test-consumer.service
systemctl start acme-test-secondary.service

# Empty queue must not reload anything.
rm -f -- "${TEST_RELOAD}" "${TEST_RELOAD_SECONDARY}"
systemctl start acme-deploy.service
[[ ! -e "${TEST_RELOAD}" && ! -e "${TEST_RELOAD_SECONDARY}" ]]

# Generate a disposable local certificate without contacting a CA.
runuser --user acme -- openssl req \
  -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
  -keyout /var/lib/acme/staging/example.com.key \
  -out /var/lib/acme/staging/example.com.crt \
  -days 1 -subj /CN=example.com >/dev/null 2>&1
runuser --user acme -- cp \
  /var/lib/acme/staging/example.com.crt \
  /var/lib/acme/staging/example.com.ca
runuser --user acme -- \
  /usr/local/libexec/devops-toolkit/acme-manager request-deploy example.com
systemctl start acme-deploy.service

[[ -e "${TEST_RELOAD}" ]]
[[ -e "${TEST_RELOAD_SECONDARY}" ]]
bundle=/var/lib/acme/certs/example.com
[[ -L "${bundle}/current" ]]
first_revision="$(readlink "${bundle}/current")"
[[ "${first_revision}" =~ ^revisions/[0-9a-f]{32}$ ]]
[[ "$(stat -c '%U:%G %a' "${bundle}/current/privkey.pem")" == 'root:ssl-cert 640' ]]
[[ "$(stat -c '%U:%G %a' "${bundle}/current/fullchain.pem")" == 'root:ssl-cert 644' ]]
[[ "$(stat -c '%U:%G %a' "${bundle}/current/ca.pem")" == 'root:ssl-cert 644' ]]
if runuser --user acme -- test -r "${bundle}/current/privkey.pem"; then
  printf 'acme 不应读取已发布私钥。\n' >&2
  exit 1
fi
runuser --user www-data -- test -r "${bundle}/current/privkey.pem"

# Duplicate material is not a renewal and must not reload a consumer.
rm -f -- "${TEST_RELOAD}" "${TEST_RELOAD_SECONDARY}"
runuser --user acme -- \
  /usr/local/libexec/devops-toolkit/acme-manager request-deploy example.com
systemctl start acme-deploy.service
[[ ! -e "${TEST_RELOAD}" && ! -e "${TEST_RELOAD_SECONDARY}" ]]
[[ "$(readlink "${bundle}/current")" == "${first_revision}" ]]

# A new valid revision switches the directory pointer once and keeps the old bundle.
runuser --user acme -- openssl req \
  -x509 -key /var/lib/acme/staging/example.com.key \
  -out /var/lib/acme/staging/example.com.crt \
  -days 2 -subj /CN=example.com -set_serial 2 >/dev/null 2>&1
runuser --user acme -- cp \
  /var/lib/acme/staging/example.com.crt \
  /var/lib/acme/staging/example.com.ca
runuser --user acme -- \
  /usr/local/libexec/devops-toolkit/acme-manager request-deploy example.com
systemctl start acme-deploy.service
[[ -e "${TEST_RELOAD}" ]]
[[ -e "${TEST_RELOAD_SECONDARY}" ]]
[[ "$(readlink "${bundle}/current")" != "${first_revision}" ]]
[[ -f "${bundle}/${first_revision}/privkey.pem" ]]

# A staged symlink must fail closed and must not reload consumers.
rm -f -- "${TEST_RELOAD}" "${TEST_RELOAD_SECONDARY}"
runuser --user acme -- ln -s \
  /var/lib/acme/staging/example.com.key \
  /var/lib/acme/staging/evil.example.com.key
runuser --user acme -- cp \
  /var/lib/acme/staging/example.com.crt \
  /var/lib/acme/staging/evil.example.com.crt
runuser --user acme -- cp \
  /var/lib/acme/staging/example.com.ca \
  /var/lib/acme/staging/evil.example.com.ca
runuser --user acme -- \
  /usr/local/libexec/devops-toolkit/acme-manager request-deploy evil.example.com
if systemctl start acme-deploy.service; then
  printf 'staging 符号链接攻击竟然成功。\n' >&2
  exit 1
fi
[[ ! -e /var/lib/acme/certs/evil.example.com ]]
[[ ! -e "${TEST_RELOAD}" && ! -e "${TEST_RELOAD_SECONDARY}" ]]
find /var/lib/acme/deploy-failed -maxdepth 1 -type f \
  -name 'evil.example.com.*' | grep -q .

printf '一次性 VM 的部署权限、多消费者 reload 与符号链接失败隔离验证通过。\n'
