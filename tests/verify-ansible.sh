#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

cat >"${TMP_DIR}/inventory.ini" <<'EOF'
[ubuntu_servers]
ubuntu-test ansible_host=192.0.2.10 ansible_user=root

[user_only]
user-test ansible_host=192.0.2.11 ansible_user=developer
EOF

export ANSIBLE_CONFIG="${ROOT_DIR}/ansible/ansible.cfg"
export ANSIBLE_LOCAL_TEMP="${TMP_DIR}/local"
export ANSIBLE_REMOTE_TEMP="/tmp/devops-toolkit-ansible"

ansible-playbook --syntax-check -i 'localhost,' "${ROOT_DIR}/ansible/playbooks/wsl-bootstrap.yml"
ansible-playbook --syntax-check -i "${TMP_DIR}/inventory.ini" \
  "${ROOT_DIR}/ansible/playbooks/ubuntu-bootstrap.yml"
ansible-playbook --syntax-check -i "${TMP_DIR}/inventory.ini" \
  "${ROOT_DIR}/ansible/playbooks/user-only.yml"
ansible-playbook --syntax-check -i "${TMP_DIR}/inventory.ini" \
  "${ROOT_DIR}/ansible/playbooks/user-only-remove.yml"

bash -n \
  "${ROOT_DIR}/bin/wsl-bootstrap" \
  "${ROOT_DIR}/bin/ubuntu-bootstrap" \
  "${ROOT_DIR}/bin/user-only" \
  "${ROOT_DIR}/bin/user-only-remove" \
  "${ROOT_DIR}/wsl-dev/bootstrap.sh" \
  "${ROOT_DIR}/ubuntu-server/bootstrap.sh"

if grep -R -nE 'apt_key:|apt_repository:' "${ROOT_DIR}/ansible"; then
  echo "错误：统一实现中仍有已弃用的 APT 仓库模块。" >&2
  exit 1
fi

if grep -nE 'host_key_checking[[:space:]]*=[[:space:]]*False|become[[:space:]]*=[[:space:]]*True' \
  "${ROOT_DIR}/ansible/ansible.cfg"; then
  echo "错误：统一配置重新启用了不安全的全局设置。" >&2
  exit 1
fi

echo "统一 Ansible 入口静态验证通过。"
