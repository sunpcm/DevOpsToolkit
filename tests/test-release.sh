#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

COLLECTIONS_FIXTURE="${TMP_DIR}/collections"
mkdir -p \
  "${COLLECTIONS_FIXTURE}/ansible_collections/ansible/posix" \
  "${COLLECTIONS_FIXTURE}/ansible_collections/community/general" \
  "${COLLECTIONS_FIXTURE}/ansible_collections/community/library_inventory_filtering_v1"
printf '%s\n' \
  '{"collection_info":{"namespace":"ansible","name":"posix","version":"2.2.2"}}' \
  >"${COLLECTIONS_FIXTURE}/ansible_collections/ansible/posix/MANIFEST.json"
printf '%s\n' \
  '{"collection_info":{"namespace":"community","name":"general","version":"13.4.0"}}' \
  >"${COLLECTIONS_FIXTURE}/ansible_collections/community/general/MANIFEST.json"
printf '%s\n' \
  '{"collection_info":{"namespace":"community","name":"library_inventory_filtering_v1","version":"1.1.5"}}' \
  >"${COLLECTIONS_FIXTURE}/ansible_collections/community/library_inventory_filtering_v1/MANIFEST.json"

DEVOPS_TOOLKIT_COLLECTIONS_SOURCE="${COLLECTIONS_FIXTURE}" \
  "${ROOT_DIR}/scripts/build-release.sh" v0.1.0 "${TMP_DIR}/dist" >/dev/null
test -f "${TMP_DIR}/dist/devops-toolkit.tar.gz"
test -f "${TMP_DIR}/dist/devops-toolkit.tar.gz.sha256"
(cd "${TMP_DIR}/dist" && shasum -a 256 -c devops-toolkit.tar.gz.sha256 >/dev/null)

mkdir "${TMP_DIR}/unpacked"
tar -xzf "${TMP_DIR}/dist/devops-toolkit.tar.gz" -C "${TMP_DIR}/unpacked"
PACKAGE="${TMP_DIR}/unpacked/devops-toolkit"
test "$(cat "${PACKAGE}/VERSION")" = "v0.1.0"
test -x "${PACKAGE}/bin/devops-toolkit"
test -x "${PACKAGE}/bin/ansible-playbook"
test -f "${PACKAGE}/ansible/requirements.yml"
test -f "${PACKAGE}/docs/INSTALLATION.md"
test -f "${PACKAGE}/collections/.bundled-collections"
test -f "${PACKAGE}/collections/ansible_collections/ansible/posix/MANIFEST.json"
test -f "${PACKAGE}/collections/ansible_collections/community/general/MANIFEST.json"
test -f "${PACKAGE}/collections/ansible_collections/community/library_inventory_filtering_v1/MANIFEST.json"
grep -Fx 'ansible.posix=2.2.2' "${PACKAGE}/collections/.bundled-collections" >/dev/null
grep -Fx 'community.general=13.4.0' "${PACKAGE}/collections/.bundled-collections" >/dev/null
grep -Fx 'community.library_inventory_filtering_v1=1.1.5' "${PACKAGE}/collections/.bundled-collections" >/dev/null
mkdir -p "${TMP_DIR}/installed/releases" \
  "${TMP_DIR}/installed/runtime/ansible-core-2.21.4/bin"
cp -R "${PACKAGE}" "${TMP_DIR}/installed/releases/v0.1.0"
installed_launcher="${TMP_DIR}/installed/releases/v0.1.0/bin/ansible-playbook"
if "${installed_launcher}" --version >/dev/null 2>&1; then
  echo "错误：正式安装缺少隔离 runtime 时回退到了环境中的 Ansible。" >&2
  exit 1
fi
ln -s "$(command -v ansible-playbook)" \
  "${TMP_DIR}/installed/runtime/ansible-core-2.21.4/bin/ansible-playbook"
printf '%s\n' '2.21.4' >"${TMP_DIR}/installed/runtime/ansible-core-2.21.4/.ready"
ANSIBLE_LOCAL_TEMP="${TMP_DIR}" "${installed_launcher}" --version >/dev/null
printf '%s\n' 'broken' >"${TMP_DIR}/installed/runtime/ansible-core-2.21.4/.ready"
if "${installed_launcher}" --version >/dev/null 2>&1; then
  echo "错误：正式安装接受了版本标记不符的隔离 runtime。" >&2
  exit 1
fi
test ! -e "${PACKAGE}/archive"
test ! -e "${PACKAGE}/tests"
test ! -e "${PACKAGE}/wsl-dev"
test ! -e "${PACKAGE}/ubuntu-server"
if find "${PACKAGE}" -name '__pycache__' -o -name '*.pyc' -o -name '.DS_Store' -o -name '._*' | grep -q .; then
  echo "错误：Release 包含缓存或个人元数据。" >&2
  exit 1
fi

if DEVOPS_TOOLKIT_COLLECTIONS_SOURCE="${COLLECTIONS_FIXTURE}" \
  "${ROOT_DIR}/scripts/build-release.sh" invalid "${TMP_DIR}/invalid" >/dev/null 2>&1; then
  echo "错误：Release 构建器接受了非法版本。" >&2
  exit 1
fi
if "${ROOT_DIR}/scripts/build-release.sh" v0.1.0 \
  "${TMP_DIR}/missing-collections" >/dev/null 2>&1; then
  echo "错误：Release 构建器接受了缺少固定 collections 的输入。" >&2
  exit 1
fi

WORKFLOW="${ROOT_DIR}/.github/workflows/release.yml"
grep -F 'id-token: write' "${WORKFLOW}" >/dev/null
grep -F 'cosign sign-blob' "${WORKFLOW}" >/dev/null
grep -F 'cosign verify-blob' "${WORKFLOW}" >/dev/null
grep -F 'devops-toolkit.tar.gz.sigstore.json' "${WORKFLOW}" >/dev/null
grep -F 'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02' \
  "${WORKFLOW}" >/dev/null
grep -F 'actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093' \
  "${WORKFLOW}" >/dev/null
grep -F 'DEVOPS_TOOLKIT_COLLECTIONS_SOURCE:' "${WORKFLOW}" >/dev/null
if grep -RE 'uses:[[:space:]]+[^[:space:]]+@(main|master|v[0-9]+)[[:space:]]*$' \
  "${ROOT_DIR}/.github/workflows"; then
  echo "错误：GitHub Action 仍使用可移动引用。" >&2
  exit 1
fi

echo "Release 包测试通过。"
