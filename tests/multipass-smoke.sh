#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_ID="$(date +%Y%m%d%H%M%S)-$$"
MANAGED_SSH_PORT="${MANAGED_SSH_PORT:-2222}"
TARGET_USER="${TARGET_USER:-devops_test}"
KEEP_INSTANCES=0
TEST_UV=0
TEST_FAULTS=0
TEST_PROXY="${MULTIPASS_TEST_PROXY:-}"
TEST_HOSTS="${MULTIPASS_TEST_HOSTS:-}"
MODE="run"
WORK_DIR=""
SSH_CONTROL_DIR=""
REPORT_FILE="${MULTIPASS_REPORT_FILE:-}"
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SOURCE_SHA="unknown"
SOURCE_DIRTY="unknown"
ANSIBLE_CORE_VERSION="unknown"
declare -a REQUESTED_INSTANCES=()
declare -a ACTIVE_INSTANCES=()
declare -a CREATED_INSTANCES=()

usage() {
  cat <<'EOF'
用法：
  ./tests/multipass-smoke.sh run [--instance NAME ...] [--keep] [--with-uv] [--with-faults] [--report PATH]
  ./tests/multipass-smoke.sh check [NAME ...]
  ./tests/multipass-smoke.sh cleanup NAME ...

说明：
  run      不传 --instance 时，为 Ubuntu 22.04/24.04 创建临时实例并在成功后清理；
           成功或失败均清理脚本创建的实例；只有明确传入 --keep 才保留现场。
           --instance 仅用于续跑已有的 *-test-* 临时实例，脚本不会删除外部实例。
           --with-uv 额外验证固定 uv 产物下载与 SHA256 校验，默认不启用。
           可通过 DEVOPS_TOOLKIT_UV_RELEASE_BASE_URL 指向 HTTPS 镜像的版本目录。
           --with-faults 在一次性实例中注入 SSH、UFW 和中断恢复故障。
           --report 写入不含凭据的机器可读验收报告；默认不写文件。
           宿主网络使用本地代理时，可用 MULTIPASS_TEST_PROXY 为 VM 设置临时 HTTP 代理。
           VM DNS 返回 Fake-IP 时，可用 MULTIPASS_TEST_HOSTS 临时覆盖受限的官方域名。
  check    只检查实例状态、版本、架构、联网和 SSH 服务。
  cleanup  只删除由本脚本命名的 *-test-* 临时实例，先显示实例列表。

续跑临时实例示例：
  ./tests/multipass-smoke.sh run \
    --instance devops-toolkit-2204-test-YYYYMMDDhhmmss-PID
EOF
}

die() {
  echo "错误：$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "找不到命令：$1"
}

validate_test_hosts() {
  local entry host ip seen="," configured="${1:-${TEST_HOSTS}}"
  [[ -n "${configured}" ]] || return 0
  [[ "${configured}" != ,* && "${configured}" != *, && "${configured}" != *,,* ]] || \
    die "MULTIPASS_TEST_HOSTS 包含空映射"
  local -a entries
  IFS=',' read -r -a entries <<<"${configured}"
  ((${#entries[@]} > 0)) || die "MULTIPASS_TEST_HOSTS 不能为空列表"
  for entry in "${entries[@]}"; do
    [[ "${entry}" =~ ^(ports\.ubuntu\.com|download\.docker\.com)=([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || \
      die "MULTIPASS_TEST_HOSTS 只接受官方域名=IPv4，逗号分隔"
    host="${entry%%=*}"
    ip="${entry#*=}"
    [[ "${seen}" != *",${host},"* ]] || die "MULTIPASS_TEST_HOSTS 重复域名：${host}"
    seen="${seen}${host},"
    python3 -c 'import ipaddress, sys; assert ipaddress.IPv4Address(sys.argv[1]).is_global' \
      "${ip}" || die "MULTIPASS_TEST_HOSTS 只接受公网 IPv4：${ip}"
  done
}

read_ansible_core_version() {
  ansible-playbook --version | sed -n '1s/.*core \([0-9][0-9.]*\).*/\1/p'
}

instance_exists() {
  multipass list --format json | python3 -c '
import json
import sys

name = sys.argv[1]
data = json.load(sys.stdin)
raise SystemExit(0 if any(item["name"] == name for item in data["list"]) else 1)
' "$1"
}

is_disposable_name() {
  [[ "$1" =~ ^devops-toolkit-(2204|2404)-test-[0-9]{14}-[0-9]+$ ]]
}

check_instance() {
  local instance="$1"
  echo "==> 检查 ${instance}"
  multipass info "${instance}"
  # 单引号内的变量刻意在 VM 内展开，不在宿主机展开。
  # shellcheck disable=SC2016
  multipass exec "${instance}" -- sh -lc '
    set -eu
    . /etc/os-release
    printf "release=%s arch=" "$VERSION_ID"
    uname -m
    getent hosts github.com >/dev/null
    printf "internet=ok ssh="
    systemctl is-active ssh
  '
}

cleanup_instances() {
  local instance
  (($# > 0)) || die "cleanup 至少需要一个实例名"
  for instance in "$@"; do
    is_disposable_name "${instance}" || \
      die "拒绝删除非临时实例：${instance}"
    instance_exists "${instance}" || die "实例不存在：${instance}"
    multipass list
  done
  for instance in "$@"; do
    multipass stop --force "${instance}" || true
    multipass delete --purge "${instance}"
  done
}

cleanup_created_instances() {
  local instance cleanup_status=0
  ((${#CREATED_INSTANCES[@]} > 0)) || return 0
  multipass list --format json >/dev/null || return 1
  for instance in "${CREATED_INSTANCES[@]}"; do
    if ! is_disposable_name "${instance}"; then
      echo "错误：拒绝自动清理非临时实例：${instance}" >&2
      cleanup_status=1
      continue
    fi
    if instance_exists "${instance}"; then
      multipass stop --force "${instance}" || true
      if ! multipass delete --purge "${instance}"; then
        cleanup_status=1
      fi
    fi
  done
  return "${cleanup_status}"
}

write_report() {
  local result="$1" cleanup_status="$2" report_tmp instance_csv
  [[ -n "${REPORT_FILE}" ]] || return 0
  instance_csv="$(IFS=,; echo "${ACTIVE_INSTANCES[*]}")"
  mkdir -p "$(dirname "${REPORT_FILE}")"
  report_tmp="${REPORT_FILE}.tmp.$$"
  umask 022
  cat >"${report_tmp}" <<EOF
schema=1
result=${result}
source_sha=${SOURCE_SHA}
source_dirty=${SOURCE_DIRTY}
started_at=${STARTED_AT}
finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ansible_core=${ANSIBLE_CORE_VERSION}
ubuntu_images=22.04,24.04
instances=${instance_csv}
managed_ssh_port=${MANAGED_SSH_PORT}
test_uv=${TEST_UV}
test_faults=${TEST_FAULTS}
test_hosts=${TEST_HOSTS}
cleanup_status=${cleanup_status}
EOF
  chmod 0644 "${report_tmp}"
  mv "${report_tmp}" "${REPORT_FILE}"
}

report_exit() {
  local status="$1" final_status cleanup_status result
  final_status="${status}"
  cleanup_status="not-owned"
  if ((${#CREATED_INSTANCES[@]} > 0)); then
    if ((KEEP_INSTANCES == 1)); then
      cleanup_status="skipped-by-request"
    elif cleanup_created_instances; then
      cleanup_status="passed"
    else
      cleanup_status="failed"
      final_status=1
    fi
  fi
  if [[ -n "${SSH_CONTROL_DIR}" && -d "${SSH_CONTROL_DIR}" ]]; then
    rm -rf -- "${SSH_CONTROL_DIR}"
  fi
  result="passed"
  ((final_status == 0)) || result="failed"
  if ! write_report "${result}" "${cleanup_status}"; then
    echo "错误：无法写入 Multipass 验收报告：${REPORT_FILE}" >&2
    final_status=1
  fi
  if ((KEEP_INSTANCES == 1)); then
    echo "测试工件保留在：${WORK_DIR}"
    printf '临时实例已按明确请求保留。确认后清理：%q cleanup' "$0"
    printf ' %q' "${CREATED_INSTANCES[@]}"
    printf '\n'
  elif [[ -n "${WORK_DIR}" && -d "${WORK_DIR}" ]]; then
    rm -rf -- "${WORK_DIR}"
  fi
  trap - EXIT
  exit "${final_status}"
}

validate_transfer() {
  local instance="$1"
  local remote_marker="/tmp/devops-toolkit-${RUN_ID}-TODO.md"
  multipass transfer "${ROOT_DIR}/TODO.md" "${instance}:${remote_marker}"
  multipass exec "${instance}" -- sh -eu -c \
    "test -s '${remote_marker}'; rm -f '${remote_marker}'"
  echo "${instance}: 项目标记文件传输验证通过"
}

configure_test_proxy() {
  local instance="$1"
  [[ -n "${TEST_PROXY}" ]] || return 0
  [[ "${TEST_PROXY}" =~ ^http://[A-Za-z0-9.:-]+$ ]] || \
    die "MULTIPASS_TEST_PROXY 只接受不含凭据的 http://host:port"
  multipass exec "${instance}" -- sudo sh -eu -c "
    cat >/etc/apt/apt.conf.d/99-devops-toolkit-test-proxy <<'EOF'
Acquire::http::Proxy \"${TEST_PROXY}\";
Acquire::https::Proxy \"${TEST_PROXY}\";
EOF
    cat >/etc/environment <<'EOF'
http_proxy=\"${TEST_PROXY}\"
https_proxy=\"${TEST_PROXY}\"
HTTP_PROXY=\"${TEST_PROXY}\"
HTTPS_PROXY=\"${TEST_PROXY}\"
no_proxy=\"localhost,127.0.0.1,::1\"
NO_PROXY=\"localhost,127.0.0.1,::1\"
EOF
  "
  echo "${instance}: 已配置一次性 VM 测试代理 ${TEST_PROXY}"
}

configure_test_hosts() {
  local instance="$1" entry host ip
  [[ -n "${TEST_HOSTS}" ]] || return 0
  local -a entries
  IFS=',' read -r -a entries <<<"${TEST_HOSTS}"
  for entry in "${entries[@]}"; do
    host="${entry%%=*}"
    ip="${entry#*=}"
    multipass exec "${instance}" -- sudo sh -c \
      "grep -Fqx '${ip} ${host}' /etc/hosts || printf '%s\\n' '${ip} ${host}' >>/etc/hosts"
  done
  echo "${instance}: 已加入一次性 VM 测试 DNS 覆盖：${TEST_HOSTS}"
}

prepare_root_key() {
  local instance="$1"
  local public_key_file="$2"
  local remote_key="/tmp/devops-toolkit-${RUN_ID}.pub"
  multipass transfer "${public_key_file}" "${instance}:${remote_key}"
  multipass exec "${instance}" -- sudo sh -eu -c "
    install -d -m 0700 /root/.ssh
    touch /root/.ssh/authorized_keys
    chmod 0600 /root/.ssh/authorized_keys
    key=\$(cat '${remote_key}')
    grep -Fqx \"\${key}\" /root/.ssh/authorized_keys || printf '%s\\n' \"\${key}\" >>/root/.ssh/authorized_keys
    rm -f '${remote_key}'
  "
}

instance_ip() {
  multipass info "$1" --format json | \
    python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(iter(d["info"].values()))["ipv4"][0])'
}

write_inventory() {
  local path="$1"
  local name="$2"
  local ip="$3"
  local port="$4"
  local key_file="$5"
  local known_hosts="$6"
  local user="${7:-root}"
  cat >"${path}" <<EOF
[ubuntu_servers]
${name} ansible_host=${ip} ansible_user=${user} ansible_port=${port} ansible_ssh_private_key_file=${key_file} ansible_ssh_common_args='-o UserKnownHostsFile=${known_hosts} -o IdentitiesOnly=yes'
EOF
}

assert_recap_clean() {
  local log_file="$1"
  local recap
  recap="$(grep -E 'changed=[0-9]+.*unreachable=[0-9]+.*failed=[0-9]+' "${log_file}" | tail -n 1 || true)"
  [[ -n "${recap}" ]] || die "无法识别 Ansible PLAY RECAP：${log_file}"
  if grep -Eq 'changed=[1-9][0-9]*|unreachable=[1-9][0-9]*|failed=[1-9][0-9]*' <<<"${recap}"; then
    die "第二次执行不是零变更：${recap}"
  fi
  echo "幂等验证通过：${recap}"
}

verify_result() {
  local instance="$1"
  local ip="$2"
  local key_file="$3"
  local known_hosts="$4"

  ssh -F /dev/null -i "${key_file}" -o IdentitiesOnly=yes \
    -o "UserKnownHostsFile=${known_hosts}" -p "${MANAGED_SSH_PORT}" \
    "${TARGET_USER}@${ip}" true
  ssh -F /dev/null -i "${key_file}" -o IdentitiesOnly=yes \
    -o "UserKnownHostsFile=${known_hosts}" -p "${MANAGED_SSH_PORT}" \
    "${TARGET_USER}@${ip}" sudo env \
    TARGET_USER="${TARGET_USER}" MANAGED_SSH_PORT="${MANAGED_SSH_PORT}" \
    TEST_UV="${TEST_UV}" sh -eu -s <<'EOF'
id "$TARGET_USER" >/dev/null
test -s "/home/$TARGET_USER/.ssh/authorized_keys"
sshd -T | grep -Eq "^port ${MANAGED_SSH_PORT}$"
sshd -T | grep -Eq '^passwordauthentication no$'
grep -Fxq 'PasswordAuthentication no' /etc/ssh/sshd_config.d/99-devops-toolkit.conf
grep -Fxq 'KbdInteractiveAuthentication no' /etc/ssh/sshd_config.d/99-devops-toolkit.conf
if [ "${MANAGED_SSH_PORT}" != 22 ]; then
  ! ss -H -ltn "sport = :22" | grep -q .
fi
ufw status | grep -Fq "Status: active"
# UFW converges through the managed application profile, so "ufw status" lists the
# profile name rather than the raw port. Assert the port via the profile itself.
ufw app info DevOpsToolkit | grep -Fq "${MANAGED_SSH_PORT}/tcp"
if [ "${MANAGED_SSH_PORT}" != 22 ]; then
  ! ufw app info DevOpsToolkit | grep -Eq '(^|[|,[:space:]])22/tcp([|,[:space:]]|$)'
fi
systemctl is-active --quiet docker
systemctl is-enabled --quiet docker
systemctl is-active --quiet nginx
systemctl is-enabled --quiet nginx
id -nG "$TARGET_USER" | tr " " "\n" | grep -Fxq docker
if [ "$TEST_UV" = 1 ]; then
  test -x "/home/$TARGET_USER/.local/bin/uv"
fi
EOF
  echo "${instance}: 用户、SSH、UFW、Docker、Nginx 验证通过"
}

ssh_as_target() {
  local ip="$1"
  local key_file="$2"
  local known_hosts="$3"
  shift 3
  ssh -F /dev/null -i "${key_file}" -o IdentitiesOnly=yes \
    -o "UserKnownHostsFile=${known_hosts}" -p "${MANAGED_SSH_PORT}" \
    "${TARGET_USER}@${ip}" "$@"
}

run_fault_injections() {
  local instance="$1"
  local ip="$2"
  local key_file="$3"
  local known_hosts="$4"
  local inventory="$5"
  local vars_file="$6"
  local work_dir="$7"
  local invalid_vars="${work_dir}/${instance}-invalid-ssh-vars.yml"
  local invalid_log="${work_dir}/${instance}-invalid-ssh.log"
  local recovery_log="${work_dir}/${instance}-fault-recovery.log"
  local firewall_log="${work_dir}/${instance}-firewall-recovery.log"
  local partial_playbook="${work_dir}/${instance}-partial-account.yml"
  local partial_log="${work_dir}/${instance}-partial-account.log"
  local resume_log="${work_dir}/${instance}-resume-second.log"
  local occupied_playbook="${work_dir}/${instance}-occupied-port.yml"
  local occupied_log="${work_dir}/${instance}-occupied-port.log"
  local occupied_port=2223
  local resume_user="${TARGET_USER}_resume"

  [[ "${MANAGED_SSH_PORT}" != 2223 ]] || occupied_port=2224

  echo "==> ${instance}: 故障注入（无效 SSH 配置不得重启）"
  cp "${vars_file}" "${invalid_vars}"
  printf '\ndisable_root_login: true\n' >>"${invalid_vars}"
  printf 'DefinitelyInvalidDirective yes\n' | \
    ssh_as_target "${ip}" "${key_file}" "${known_hosts}" \
      sudo tee /etc/ssh/sshd_config.d/98-devops-toolkit-fault.conf >/dev/null
  if "${ROOT_DIR}/bin/ubuntu-bootstrap" "${inventory}" "${TARGET_USER}" \
      -e "@${invalid_vars}" >"${invalid_log}" 2>&1; then
    die "${instance}: 无效 SSH 配置没有阻止 Playbook"
  fi
  grep -Fq 'Validate the complete OpenSSH configuration before handlers run' \
    "${invalid_log}" || die "${instance}: SSH 故障没有在预重启校验任务中失败"
  ssh_as_target "${ip}" "${key_file}" "${known_hosts}" true
  ssh_as_target "${ip}" "${key_file}" "${known_hosts}" \
    sudo rm -f /etc/ssh/sshd_config.d/98-devops-toolkit-fault.conf
  "${ROOT_DIR}/bin/ubuntu-bootstrap" "${inventory}" "${TARGET_USER}" \
    -e "@${vars_file}" >"${recovery_log}"
  echo "${instance}: SSH 预重启校验与恢复通过"

  echo "==> ${instance}: 故障注入（陈旧 UFW profile）"
  ssh_as_target "${ip}" "${key_file}" "${known_hosts}" \
    sudo sh -eu -s -- "${MANAGED_SSH_PORT}" <<'EOF'
managed_ssh_port="$1"
ufw --force disable
ufw --force reset
cp /etc/apt/keyrings/docker.asc /etc/apt/keyrings/docker.gpg
printf '%s\n' \
  'deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable' \
  >/etc/apt/sources.list.d/docker-legacy-test.list
ufw allow "${managed_ssh_port}/tcp" comment 'Existing SSH rule'
ufw allow 80/tcp comment 'Existing HTTP rule'
ufw allow 443/tcp comment 'Existing HTTPS rule'
cat >/etc/ufw/applications.d/devopstoolkit <<'PROFILE'
[DevOpsToolkit]
title=Stale DevOpsToolkit profile
description=Fault injected by the disposable Multipass test
ports=65000/tcp
PROFILE
ufw allow DevOpsToolkit
EOF
  "${ROOT_DIR}/bin/ubuntu-bootstrap" "${inventory}" "${TARGET_USER}" \
    -e "@${vars_file}" >"${firewall_log}"
  ssh_as_target "${ip}" "${key_file}" "${known_hosts}" \
    sudo ufw app info DevOpsToolkit | grep -Fq "${MANAGED_SSH_PORT}/tcp"
  if ssh_as_target "${ip}" "${key_file}" "${known_hosts}" \
      sudo grep -Fq 'download.docker.com/linux/ubuntu' \
      /etc/apt/sources.list.d/docker-legacy-test.list; then
    die "${instance}: 旧 Docker APT 源没有被受管 deb822 源收敛"
  fi
  ssh_as_target "${ip}" "${key_file}" "${known_hosts}" true
  echo "${instance}: UFW profile 与旧 Docker APT 源冲突恢复，SSH 仍可达"

  echo "==> ${instance}: 故障注入（新 SSH 端口被其他服务占用）"
  cat >"${occupied_playbook}" <<EOF
---
- name: Refuse an occupied desired SSH port
  hosts: ubuntu_servers
  gather_facts: true
  vars_files:
    - ${ROOT_DIR}/ansible/group_vars/all.yml
  roles:
    - role: ssh_security
EOF
  ssh_as_target "${ip}" "${key_file}" "${known_hosts}" \
    sudo systemd-run --unit=devops-toolkit-test-port --collect \
      /usr/bin/python3 -m http.server "${occupied_port}" >/dev/null
  local listen_attempt=0
  until ssh_as_target "${ip}" "${key_file}" "${known_hosts}" \
      sudo ss --tcp --listening --numeric "sport = :${occupied_port}" | \
      grep -Fq ":${occupied_port}"; do
    ((listen_attempt += 1))
    ((listen_attempt < 10)) || die "${instance}: 故障服务未监听 ${occupied_port}"
    sleep 1
  done
  if ansible-playbook -i "${inventory}" "${occupied_playbook}" \
      -e "@${vars_file}" -e "target_user=${TARGET_USER}" \
      -e "ssh_port=${occupied_port}" >"${occupied_log}" 2>&1; then
    die "${instance}: 被占用的新 SSH 端口没有阻止切换"
  fi
  grep -Fq "Refusing to move SSH to occupied port ${occupied_port}" "${occupied_log}" || \
    die "${instance}: 端口占用没有触发预期的安全拒绝"
  ssh_as_target "${ip}" "${key_file}" "${known_hosts}" true
  ssh_as_target "${ip}" "${key_file}" "${known_hosts}" \
    sudo systemctl stop devops-toolkit-test-port
  echo "${instance}: 被占用端口安全拒绝，原 SSH 连接仍可达"

  echo "==> ${instance}: 故障注入（部分账户状态后完整重跑）"
  cat >"${partial_playbook}" <<EOF
---
- name: Create a controlled partial bootstrap state
  hosts: ubuntu_servers
  gather_facts: true
  vars_files:
    - ${ROOT_DIR}/ansible/group_vars/all.yml
  roles:
    - role: account_create
  post_tasks:
    - name: Simulate interruption after account creation
      ansible.builtin.fail:
        msg: Controlled interruption for idempotence testing
EOF
  if ansible-playbook -i "${inventory}" "${partial_playbook}" \
      -e "target_user=${resume_user}" -e "@${vars_file}" >"${partial_log}" 2>&1; then
    die "${instance}: 受控中断没有按预期失败"
  fi
  grep -Fq 'Controlled interruption for idempotence testing' "${partial_log}" || \
    die "${instance}: 未观察到受控中断标记"
  "${ROOT_DIR}/bin/ubuntu-bootstrap" "${inventory}" "${resume_user}" \
    -e "@${vars_file}" >/dev/null
  "${ROOT_DIR}/bin/ubuntu-bootstrap" "${inventory}" "${resume_user}" \
    -e "@${vars_file}" | tee "${resume_log}"
  assert_recap_clean "${resume_log}"
  ssh -F /dev/null -i "${key_file}" -o IdentitiesOnly=yes \
    -o "UserKnownHostsFile=${known_hosts}" -p "${MANAGED_SSH_PORT}" \
    "${resume_user}@${ip}" sudo true
  echo "${instance}: 中断后的完整重跑与二次幂等验证通过"
}

run_instance() {
  local instance="$1"
  local work_dir="$2"
  local key_file="$3"
  local public_key_file="${key_file}.pub"
  local known_hosts="${work_dir}/${instance}.known_hosts"
  local initial_inventory="${work_dir}/${instance}-initial.ini"
  local managed_inventory="${work_dir}/${instance}-managed.ini"
  local target_inventory="${work_dir}/${instance}-target.ini"
  local vars_file="${work_dir}/${instance}-vars.yml"
  local second_log="${work_dir}/${instance}-second.log"
  local unverified_log="${work_dir}/${instance}-unverified-key.log"
  local ip public_key initial_port

  check_instance "${instance}"
  validate_transfer "${instance}"
  configure_test_proxy "${instance}"
  configure_test_hosts "${instance}"
  prepare_root_key "${instance}" "${public_key_file}"
  ip="$(instance_ip "${instance}")"
  public_key="$(cat "${public_key_file}")"
  cat >"${vars_file}" <<EOF
---
target_authorized_keys:
  - ${public_key}
ssh_port: ${MANAGED_SSH_PORT}
disable_password_auth: true
target_passwordless_sudo: true
install_docker: true
install_nginx: true
install_linuxbrew: false
configure_shell: false
configure_git: false
configure_node: false
configure_go: false
configure_homebrew_environment: false
configure_wsl_integration: false
configure_uv: $([[ "${TEST_UV}" == 1 ]] && echo true || echo false)
EOF

  initial_port=22
  if ! ssh-keyscan -T 3 -p "${initial_port}" -H "${ip}" >"${known_hosts}" 2>/dev/null; then
    initial_port="${MANAGED_SSH_PORT}"
    ssh-keyscan -T 3 -p "${initial_port}" -H "${ip}" >"${known_hosts}" 2>/dev/null || \
      die "${instance}: SSH 22 和 ${MANAGED_SSH_PORT} 均不可达"
  fi
  write_inventory "${initial_inventory}" "${instance}" "${ip}" \
    "${initial_port}" "${key_file}" "${known_hosts}"

  echo "==> ${instance}: 首次配置（SSH ${initial_port} -> ${MANAGED_SSH_PORT}）"
  "${ROOT_DIR}/bin/ubuntu-bootstrap" "${initial_inventory}" "${TARGET_USER}" \
    -e "@${vars_file}"

  ssh-keyscan -p "${MANAGED_SSH_PORT}" -H "${ip}" >"${known_hosts}" 2>/dev/null
  write_inventory "${target_inventory}" "${instance}" "${ip}" \
    "${MANAGED_SSH_PORT}" "${key_file}" "${known_hosts}" "${TARGET_USER}"
  if ((TEST_FAULTS == 1)); then
    echo "==> ${instance}: 故障注入（未确认密钥不得关闭旧 SSH 端口）"
    if "${ROOT_DIR}/bin/ubuntu-ssh-finalize" "${target_inventory}" "${TARGET_USER}" \
        -e "@${vars_file}" -e ssh_finalize_key_verified=false \
        >"${unverified_log}" 2>&1; then
      die "${instance}: 未确认密钥仍允许 SSH finalize"
    fi
    grep -Fq 'ssh_finalize_key_verified=true' "${unverified_log}" || \
      die "${instance}: 未确认密钥没有触发预期的安全拒绝"
    ssh -F /dev/null -i "${key_file}" -o IdentitiesOnly=yes \
      -o "UserKnownHostsFile=${known_hosts}" -p "${initial_port}" \
      "root@${ip}" true || die "${instance}: 密钥确认失败后旧 SSH 连接不可达"
  fi
  echo "==> ${instance}: 从普通用户新端口执行 SSH finalize"
  "${ROOT_DIR}/bin/ubuntu-ssh-finalize" "${target_inventory}" "${TARGET_USER}" \
    -e "@${vars_file}" -e ssh_finalize_key_verified=true

  write_inventory "${managed_inventory}" "${instance}" "${ip}" \
    "${MANAGED_SSH_PORT}" "${key_file}" "${known_hosts}"

  echo "==> ${instance}: 第二次配置（幂等性）"
  "${ROOT_DIR}/bin/ubuntu-bootstrap" "${managed_inventory}" "${TARGET_USER}" \
    -e "@${vars_file}" | tee "${second_log}"

  assert_recap_clean "${second_log}"
  verify_result "${instance}" "${ip}" "${key_file}" "${known_hosts}"
  if ((TEST_FAULTS == 1)); then
    run_fault_injections "${instance}" "${ip}" "${key_file}" "${known_hosts}" \
      "${managed_inventory}" "${vars_file}" "${work_dir}"
  fi
}

parse_args() {
  if (($# > 0)) && [[ "$1" != --* ]]; then
    MODE="$1"
    shift
  fi
  case "${MODE}" in
    run)
      while (($# > 0)); do
        case "$1" in
          --instance)
            (($# >= 2)) || die "--instance 缺少实例名"
            REQUESTED_INSTANCES+=("$2")
            shift 2
            ;;
          --keep)
            KEEP_INSTANCES=1
            shift
            ;;
          --with-uv)
            TEST_UV=1
            shift
            ;;
          --with-faults)
            TEST_FAULTS=1
            shift
            ;;
          --report)
            (($# >= 2)) || die "--report 缺少路径"
            REPORT_FILE="$2"
            shift 2
            ;;
          -h|--help)
            usage
            exit 0
            ;;
          *) die "未知参数：$1" ;;
        esac
      done
      ;;
    check|cleanup)
      REQUESTED_INSTANCES=("$@")
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "未知模式：${MODE}" ;;
  esac
}

main() {
  local instance
  parse_args "$@"
  require_command multipass
  require_command ansible-playbook
  require_command ssh
  require_command ssh-keygen
  require_command ssh-keyscan
  require_command python3
  validate_test_hosts
  SOURCE_SHA="$(git -C "${ROOT_DIR}" rev-parse HEAD)"
  if [[ -n "$(git -C "${ROOT_DIR}" status --porcelain)" ]]; then
    SOURCE_DIRTY=true
  else
    SOURCE_DIRTY=false
  fi
  ANSIBLE_CORE_VERSION="$(read_ansible_core_version)"
  [[ -n "${ANSIBLE_CORE_VERSION}" ]] || die "无法识别 ansible-core 版本"

  if [[ "${MODE}" == check ]]; then
    ((${#REQUESTED_INSTANCES[@]} > 0)) || die "check 至少需要一个实例名"
    for instance in "${REQUESTED_INSTANCES[@]}"; do check_instance "${instance}"; done
    exit 0
  fi
  if [[ "${MODE}" == cleanup ]]; then
    cleanup_instances "${REQUESTED_INSTANCES[@]}"
    exit 0
  fi

  WORK_DIR="$(mktemp -d)"
  trap 'report_exit "$?"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  SSH_CONTROL_DIR="$(mktemp -d /tmp/devops-ssh.XXXXXX)"
  ssh-keygen -q -t ed25519 -N '' -C "devops-toolkit-multipass-${RUN_ID}" \
    -f "${WORK_DIR}/id_ed25519"

  if ((${#REQUESTED_INSTANCES[@]} > 0)); then
    for instance in "${REQUESTED_INSTANCES[@]}"; do
      is_disposable_name "${instance}" || \
        die "拒绝在长期实例 ${instance} 上执行配置测试；请使用 *-test-* 临时实例"
    done
    ACTIVE_INSTANCES=("${REQUESTED_INSTANCES[@]}")
  else
    ACTIVE_INSTANCES=(
      "devops-toolkit-2204-test-${RUN_ID}"
      "devops-toolkit-2404-test-${RUN_ID}"
    )
    for instance in "${ACTIVE_INSTANCES[@]}"; do
      if instance_exists "${instance}"; then
        die "拒绝覆盖已存在的临时实例：${instance}"
      fi
    done
    CREATED_INSTANCES=("${ACTIVE_INSTANCES[@]}")
    write_report running pending
    multipass launch 22.04 --name "${ACTIVE_INSTANCES[0]}" --cpus 2 --memory 3G --disk 15G
    multipass launch 24.04 --name "${ACTIVE_INSTANCES[1]}" --cpus 2 --memory 3G --disk 15G
  fi

  export ANSIBLE_CONFIG="${ROOT_DIR}/ansible/ansible.cfg"
  export ANSIBLE_LOCAL_TEMP="${WORK_DIR}/ansible-local"
  export ANSIBLE_SSH_CONTROL_PATH_DIR="${SSH_CONTROL_DIR}"
  unset ANSIBLE_REMOTE_TEMP
  mkdir -p "${ANSIBLE_LOCAL_TEMP}"

  for instance in "${ACTIVE_INSTANCES[@]}"; do
    run_instance "${instance}" "${WORK_DIR}" "${WORK_DIR}/id_ed25519"
  done

  echo "请求的 Multipass Ubuntu 实例测试全部通过。"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
