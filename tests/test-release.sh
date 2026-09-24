#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

COLLECTIONS_FIXTURE="${TMP_DIR}/collections"
COLLECTION_ARTIFACTS_FIXTURE="${TMP_DIR}/collection-artifacts"
COLLECTION_LOCK_FIXTURE="${TMP_DIR}/collections.lock.json"
mkdir -p \
  "${COLLECTION_ARTIFACTS_FIXTURE}" \
  "${COLLECTIONS_FIXTURE}/ansible_collections"

python3 - \
  "${ROOT_DIR}/ansible/collections.lock.json" \
  "${COLLECTIONS_FIXTURE}" \
  "${COLLECTION_ARTIFACTS_FIXTURE}" \
  "${COLLECTION_LOCK_FIXTURE}" <<'PY'
import hashlib
import io
import json
import sys
import tarfile
from pathlib import Path

production_lock, source, artifacts, lock_path = map(Path, sys.argv[1:])
entries = []
for locked in json.loads(production_lock.read_text(encoding="utf-8"))["collections"]:
    namespace, collection = locked["name"].split(".", 1)
    version = str(locked["version"])
    data = {
        "collection_info": {
            "namespace": namespace,
            "name": collection,
            "version": version,
        }
    }
    manifest = source / "ansible_collections" / namespace / collection / "MANIFEST.json"
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(json.dumps(data) + "\n", encoding="utf-8")
    name = locked["name"]
    artifact = f"{namespace}-{collection}-{version}.tar.gz"
    payload = json.dumps(data, separators=(",", ":")).encode()
    with tarfile.open(artifacts / artifact, "w:gz") as bundle:
        member = tarfile.TarInfo("MANIFEST.json")
        member.size = len(payload)
        member.mode = 0o644
        bundle.addfile(member, io.BytesIO(payload))
    digest = hashlib.sha256((artifacts / artifact).read_bytes()).hexdigest()
    entries.append(
        {"name": name, "version": version, "artifact": artifact, "sha256": digest}
    )
lock_path.write_text(
    json.dumps({"schema": 1, "collections": entries}, indent=2) + "\n",
    encoding="utf-8",
)
PY

build_fixture() {
  DEVOPS_TOOLKIT_COLLECTIONS_SOURCE="${COLLECTIONS_FIXTURE}" \
    DEVOPS_TOOLKIT_COLLECTION_ARTIFACTS="${COLLECTION_ARTIFACTS_FIXTURE}" \
    DEVOPS_TOOLKIT_COLLECTION_LOCK="${COLLECTION_LOCK_FIXTURE}" \
    DEVOPS_TOOLKIT_TEST_COLLECTION_LOCK=1 \
    "${ROOT_DIR}/scripts/build-release.sh" "$@"
}

build_fixture v0.1.0 "${TMP_DIR}/dist" >/dev/null
test -f "${TMP_DIR}/dist/devops-toolkit.tar.gz"
test -f "${TMP_DIR}/dist/devops-toolkit.tar.gz.sha256"
(cd "${TMP_DIR}/dist" && shasum -a 256 -c devops-toolkit.tar.gz.sha256 >/dev/null)

mkdir "${TMP_DIR}/unpacked"
tar -xzf "${TMP_DIR}/dist/devops-toolkit.tar.gz" -C "${TMP_DIR}/unpacked"
PACKAGE="${TMP_DIR}/unpacked/devops-toolkit"
test "$(cat "${PACKAGE}/VERSION")" = "v0.1.0"
test -x "${PACKAGE}/bin/devops-toolkit"
test -x "${PACKAGE}/bin/devops-toolkit-doctor"
"${PACKAGE}/bin/devops-toolkit" doctor --help >/dev/null
test -x "${PACKAGE}/bin/ansible-playbook"
test -f "${PACKAGE}/ansible/requirements.yml"
test -f "${PACKAGE}/ansible/collections.lock.json"
test -f "${PACKAGE}/docs/INSTALLATION.md"
test -f "${PACKAGE}/collections/.bundled-collections"
test -f "${PACKAGE}/collections/ansible_collections/ansible/posix/MANIFEST.json"
test -f "${PACKAGE}/collections/ansible_collections/community/general/MANIFEST.json"
test -f "${PACKAGE}/collections/ansible_collections/community/library_inventory_filtering_v1/MANIFEST.json"
python3 - "${PACKAGE}" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

package = Path(sys.argv[1])
for name, component in (("devops-toolkit", "wizard"), ("ubuntu-bootstrap", "playbook")):
    output = subprocess.check_output(
        [str(package / "bin" / name), "--capabilities-json"], text=True
    )
    info = json.loads(output)
    assert info["schema"] == 1
    assert info["version"] == "v0.1.0"
    assert info["component"] == component
    assert info["ansible_core"] == "2.21.4"
PY
grep -E '^lock-sha256=[0-9a-f]{64}$' "${PACKAGE}/collections/.bundled-collections" >/dev/null
python3 "${ROOT_DIR}/scripts/verify-collection-lock.py" \
  --lock "${PACKAGE}/ansible/collections.lock.json" \
  --installed "${PACKAGE}/collections" \
  --write-marker "${TMP_DIR}/expected-collection-marker"
cmp "${TMP_DIR}/expected-collection-marker" "${PACKAGE}/collections/.bundled-collections"
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

if build_fixture invalid "${TMP_DIR}/invalid" >/dev/null 2>&1; then
  echo "错误：Release 构建器接受了非法版本。" >&2
  exit 1
fi

cp -R "${COLLECTION_ARTIFACTS_FIXTURE}" "${TMP_DIR}/tampered-artifacts"
tampered_artifact="$(find "${TMP_DIR}/tampered-artifacts" -type f -name '*.tar.gz' -print -quit)"
printf 'tamper\n' >>"${tampered_artifact}"
if DEVOPS_TOOLKIT_COLLECTIONS_SOURCE="${COLLECTIONS_FIXTURE}" \
  DEVOPS_TOOLKIT_COLLECTION_ARTIFACTS="${TMP_DIR}/tampered-artifacts" \
  DEVOPS_TOOLKIT_COLLECTION_LOCK="${COLLECTION_LOCK_FIXTURE}" \
  DEVOPS_TOOLKIT_TEST_COLLECTION_LOCK=1 \
  "${ROOT_DIR}/scripts/build-release.sh" v0.1.0 "${TMP_DIR}/tampered-output" \
  >/dev/null 2>&1; then
  echo "错误：Release 构建器接受了被篡改的 collection tarball。" >&2
  exit 1
fi

cp -R "${COLLECTIONS_FIXTURE}" "${TMP_DIR}/tampered-installed"
printf '%s\n' \
  '{"collection_info":{"namespace":"community","name":"general","version":"9.9.9"}}' \
  >"${TMP_DIR}/tampered-installed/ansible_collections/community/general/MANIFEST.json"
if DEVOPS_TOOLKIT_COLLECTIONS_SOURCE="${TMP_DIR}/tampered-installed" \
  DEVOPS_TOOLKIT_COLLECTION_ARTIFACTS="${COLLECTION_ARTIFACTS_FIXTURE}" \
  DEVOPS_TOOLKIT_COLLECTION_LOCK="${COLLECTION_LOCK_FIXTURE}" \
  DEVOPS_TOOLKIT_TEST_COLLECTION_LOCK=1 \
  "${ROOT_DIR}/scripts/build-release.sh" v0.1.0 "${TMP_DIR}/tampered-installed-output" \
  >/dev/null 2>&1; then
  echo "错误：Release 构建器接受了被篡改的已安装 collection manifest。" >&2
  exit 1
fi

cp "${COLLECTION_LOCK_FIXTURE}" "${TMP_DIR}/tampered-lock.json"
python3 - "${TMP_DIR}/tampered-lock.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["collections"][0]["sha256"] = "0" * 64
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
if DEVOPS_TOOLKIT_COLLECTIONS_SOURCE="${COLLECTIONS_FIXTURE}" \
  DEVOPS_TOOLKIT_COLLECTION_ARTIFACTS="${COLLECTION_ARTIFACTS_FIXTURE}" \
  DEVOPS_TOOLKIT_COLLECTION_LOCK="${TMP_DIR}/tampered-lock.json" \
  DEVOPS_TOOLKIT_TEST_COLLECTION_LOCK=1 \
  "${ROOT_DIR}/scripts/build-release.sh" v0.1.0 "${TMP_DIR}/tampered-lock-output" \
  >/dev/null 2>&1; then
  echo "错误：Release 构建器接受了错误的 collection checksum。" >&2
  exit 1
fi
cp "${ROOT_DIR}/ansible/requirements.yml" "${TMP_DIR}/tampered-requirements.yml"
python3 - "${TMP_DIR}/tampered-requirements.yml" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text(encoding="utf-8")
tampered, replacements = re.subn(
    r'^    version: "[^"]+"$', '    version: "0.0.0"', original, count=1, flags=re.MULTILINE
)
if replacements != 1:
    raise SystemExit("requirements fixture was not tampered")
path.write_text(tampered, encoding="utf-8")
PY
if python3 "${ROOT_DIR}/scripts/verify-collection-lock.py" \
  --lock "${ROOT_DIR}/ansible/collections.lock.json" \
  --requirements "${TMP_DIR}/tampered-requirements.yml" >/dev/null 2>&1; then
  echo "错误：collection lock 校验器接受了不一致的 requirements.yml。" >&2
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
grep -F 'DEVOPS_TOOLKIT_COLLECTION_ARTIFACTS:' "${WORKFLOW}" >/dev/null
grep -F 'ansible-galaxy collection download' "${WORKFLOW}" >/dev/null
grep -F 'needs: quality' "${WORKFLOW}" >/dev/null
grep -F 'needs: validate' "${WORKFLOW}" >/dev/null
grep -F 'environment: release' "${WORKFLOW}" >/dev/null
if grep -Eq 'vm-evidence|vm-smoke.yml|self-hosted' "${WORKFLOW}"; then
  echo "错误：Release workflow 仍依赖自托管 VM runner。" >&2
  exit 1
fi
if grep -F 'DEVOPS_TOOLKIT_TEST_COLLECTION_LOCK' "${WORKFLOW}"; then
  echo "错误：Release workflow 启用了仅供测试使用的 lock 覆盖。" >&2
  exit 1
fi
if grep -RE 'uses:[[:space:]]+[^[:space:]]+@(main|master|v[0-9]+)[[:space:]]*$' \
  "${ROOT_DIR}/.github/workflows"; then
  echo "错误：GitHub Action 仍使用可移动引用。" >&2
  exit 1
fi

echo "Release 包测试通过。"
