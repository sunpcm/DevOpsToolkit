#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

"${ROOT_DIR}/scripts/build-release.sh" v0.1.0 "${TMP_DIR}/dist" >/dev/null
test -f "${TMP_DIR}/dist/devops-toolkit.tar.gz"
test -f "${TMP_DIR}/dist/devops-toolkit.tar.gz.sha256"
(cd "${TMP_DIR}/dist" && shasum -a 256 -c devops-toolkit.tar.gz.sha256 >/dev/null)

mkdir "${TMP_DIR}/unpacked"
tar -xzf "${TMP_DIR}/dist/devops-toolkit.tar.gz" -C "${TMP_DIR}/unpacked"
PACKAGE="${TMP_DIR}/unpacked/devops-toolkit"
test "$(cat "${PACKAGE}/VERSION")" = "v0.1.0"
test -x "${PACKAGE}/bin/devops-toolkit"
test -f "${PACKAGE}/ansible/requirements.yml"
test -f "${PACKAGE}/docs/INSTALLATION.md"
test ! -e "${PACKAGE}/archive"
test ! -e "${PACKAGE}/tests"
test ! -e "${PACKAGE}/wsl-dev"
test ! -e "${PACKAGE}/ubuntu-server"
if find "${PACKAGE}" -name '__pycache__' -o -name '*.pyc' -o -name '.DS_Store' -o -name '._*' | grep -q .; then
  echo "错误：Release 包含缓存或个人元数据。" >&2
  exit 1
fi

if "${ROOT_DIR}/scripts/build-release.sh" invalid "${TMP_DIR}/invalid" >/dev/null 2>&1; then
  echo "错误：Release 构建器接受了非法版本。" >&2
  exit 1
fi

WORKFLOW="${ROOT_DIR}/.github/workflows/release.yml"
grep -F 'id-token: write' "${WORKFLOW}" >/dev/null
grep -F 'cosign sign-blob' "${WORKFLOW}" >/dev/null
grep -F 'cosign verify-blob' "${WORKFLOW}" >/dev/null
grep -F 'devops-toolkit.tar.gz.sigstore.json' "${WORKFLOW}" >/dev/null
if grep -RE 'uses:[[:space:]]+[^[:space:]]+@(main|master|v[0-9]+)[[:space:]]*$' \
  "${ROOT_DIR}/.github/workflows"; then
  echo "错误：GitHub Action 仍使用可移动引用。" >&2
  exit 1
fi

echo "Release 包测试通过。"
