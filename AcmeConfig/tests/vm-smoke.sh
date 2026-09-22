#!/usr/bin/env bash
set -euo pipefail

# Destructive to the disposable VM's ACME state. Never run on a real host.
readonly MARKER=/etc/devops-toolkit-acme-test-vm
readonly TEST_UNIT=/etc/systemd/system/acme-test-consumer.service
readonly TEST_RELOAD=/run/acme-test-reloaded
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
  systemctl stop acme-deploy.path >/dev/null 2>&1 || true
  cp -- "${temporary}/reload-services" "${RELOAD_CONFIG}"
  chown root:root "${RELOAD_CONFIG}"
  chmod 0644 "${RELOAD_CONFIG}"
  rm -f -- "${TEST_UNIT}" "${TEST_RELOAD}"
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
chown root:root "${TEST_UNIT}"
chmod 0644 "${TEST_UNIT}"
printf '%s\n' 'acme-test-consumer.service' >"${RELOAD_CONFIG}"
chown root:root "${RELOAD_CONFIG}"
chmod 0644 "${RELOAD_CONFIG}"
systemctl daemon-reload
systemctl start acme-test-consumer.service

# Empty queue must not reload anything.
rm -f -- "${TEST_RELOAD}"
systemctl start acme-deploy.service
[[ ! -e "${TEST_RELOAD}" ]]

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
[[ "$(stat -c '%U:%G %a' /var/lib/acme/certs/example.com.key)" == 'root:ssl-cert 640' ]]
[[ "$(stat -c '%U:%G %a' /var/lib/acme/certs/example.com.crt)" == 'root:ssl-cert 644' ]]
if runuser --user acme -- test -r /var/lib/acme/certs/example.com.key; then
  printf 'acme 不应读取已发布私钥。\n' >&2
  exit 1
fi
runuser --user www-data -- test -r /var/lib/acme/certs/example.com.key

# A staged symlink must fail closed and must not reload consumers.
rm -f -- "${TEST_RELOAD}"
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
[[ ! -e /var/lib/acme/certs/evil.example.com.key ]]
[[ ! -e "${TEST_RELOAD}" ]]
find /var/lib/acme/deploy-failed -maxdepth 1 -type f \
  -name 'evil.example.com.*' | grep -q .

printf '一次性 VM 的部署权限、reload 与符号链接失败隔离验证通过。\n'
