#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"
OUTPUT_DIR="${2:-${ROOT_DIR}/dist}"
COLLECTIONS_SOURCE="${DEVOPS_TOOLKIT_COLLECTIONS_SOURCE:-}"
COLLECTION_ARTIFACTS="${DEVOPS_TOOLKIT_COLLECTION_ARTIFACTS:-}"
COLLECTION_LOCK="${DEVOPS_TOOLKIT_COLLECTION_LOCK:-${ROOT_DIR}/ansible/collections.lock.json}"

if [[ "${COLLECTION_LOCK}" != "${ROOT_DIR}/ansible/collections.lock.json" && \
      "${DEVOPS_TOOLKIT_TEST_COLLECTION_LOCK:-0}" != 1 ]]; then
  echo "错误：仅测试夹具可覆盖 collection lock。" >&2
  exit 1
fi

if [[ ! "${VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([._-][A-Za-z0-9.-]+)?$ ]]; then
  echo "用法：$0 v0.1.0 [输出目录]" >&2
  exit 1
fi

STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/devops-toolkit-release.XXXXXX")"
trap 'rm -rf "${STAGE_DIR}"' EXIT
PACKAGE_DIR="${STAGE_DIR}/devops-toolkit"

if [[ -z "${COLLECTIONS_SOURCE}" || -z "${COLLECTION_ARTIFACTS}" || \
      ! -d "${COLLECTIONS_SOURCE}/ansible_collections" || \
      ! -d "${COLLECTION_ARTIFACTS}" || ! -f "${COLLECTION_LOCK}" ]]; then
  echo "错误：缺少 collection lock、原始归档或已安装 collections 构建目录。" >&2
  exit 1
fi

python3 "${ROOT_DIR}/scripts/verify-collection-lock.py" \
  --lock "${COLLECTION_LOCK}" \
  --requirements "${ROOT_DIR}/ansible/requirements.yml" \
  --artifacts "${COLLECTION_ARTIFACTS}" \
  --installed "${COLLECTIONS_SOURCE}"

mkdir -p "${PACKAGE_DIR}/collections" "${OUTPUT_DIR}"
cp -R \
  "${ROOT_DIR}/ansible" \
  "${ROOT_DIR}/bin" \
  "${ROOT_DIR}/docs" \
  "${PACKAGE_DIR}/"
cp "${ROOT_DIR}/README.md" "${ROOT_DIR}/install.sh" "${PACKAGE_DIR}/"
cp -R "${COLLECTIONS_SOURCE}/ansible_collections" "${PACKAGE_DIR}/collections/"
cp "${COLLECTION_LOCK}" "${PACKAGE_DIR}/ansible/collections.lock.json"
python3 "${ROOT_DIR}/scripts/verify-collection-lock.py" \
  --lock "${PACKAGE_DIR}/ansible/collections.lock.json" \
  --installed "${PACKAGE_DIR}/collections" \
  --write-marker "${PACKAGE_DIR}/collections/.bundled-collections"
printf '%s\n' "${VERSION}" >"${PACKAGE_DIR}/VERSION"
find "${PACKAGE_DIR}" -type d -name '__pycache__' -prune -exec rm -rf {} +
find "${PACKAGE_DIR}" -type f \( -name '*.pyc' -o -name '.DS_Store' -o -name '._*' \) -delete
chmod 0755 "${PACKAGE_DIR}/bin/devops-toolkit" "${PACKAGE_DIR}/install.sh"

rm -f \
  "${OUTPUT_DIR}/devops-toolkit.tar.gz" \
  "${OUTPUT_DIR}/devops-toolkit.tar.gz.sha256"
COPYFILE_DISABLE=1 tar --no-xattrs -C "${STAGE_DIR}" \
  -czf "${OUTPUT_DIR}/devops-toolkit.tar.gz" devops-toolkit

if command -v sha256sum >/dev/null 2>&1; then
  (cd "${OUTPUT_DIR}" && sha256sum devops-toolkit.tar.gz >devops-toolkit.tar.gz.sha256)
else
  (cd "${OUTPUT_DIR}" && shasum -a 256 devops-toolkit.tar.gz >devops-toolkit.tar.gz.sha256)
fi

echo "Release 资产已生成：${OUTPUT_DIR}"
