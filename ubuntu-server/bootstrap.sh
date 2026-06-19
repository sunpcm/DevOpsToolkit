#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INVENTORY="${INVENTORY:-${SCRIPT_DIR}/host.ini}"

echo "警告：ubuntu-server/bootstrap.sh 已弃用，请改用 bin/ubuntu-bootstrap。" >&2

if [[ ! -f "${INVENTORY}" ]]; then
  echo "错误：找不到 inventory：${INVENTORY}" >&2
  exit 1
fi

TARGET_USER="${TARGET_USER:-$(sed -nE 's/^[[:space:]]*username:[[:space:]]*["'\'']?([^"'\'' #]+).*/\1/p' "${SCRIPT_DIR}/ansible/group_vars/all.yml" | head -n 1)}"
if [[ -z "${TARGET_USER}" ]]; then
  echo "错误：请设置 TARGET_USER。" >&2
  exit 1
fi

exec "${ROOT_DIR}/bin/ubuntu-bootstrap" "${INVENTORY}" "${TARGET_USER}" "$@"
