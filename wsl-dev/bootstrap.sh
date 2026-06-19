#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "警告：wsl-dev/bootstrap.sh 已弃用，请改用 bin/wsl-bootstrap。" >&2

TARGET_USER="${TARGET_USER:-${SUDO_USER:-${USER}}}"
if [[ "${EUID}" -eq 0 ]]; then
  exec env TARGET_USER="${TARGET_USER}" "${ROOT_DIR}/bin/wsl-bootstrap"
else
  exec sudo env TARGET_USER="${TARGET_USER}" "${ROOT_DIR}/bin/wsl-bootstrap"
fi
