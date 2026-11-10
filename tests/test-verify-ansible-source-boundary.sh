#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "${TEST_TMP}"' EXIT

SCAN_STDOUT="${TEST_TMP}/scan.stdout"
SCAN_STDERR="${TEST_TMP}/scan.stderr"
SCAN_STATUS=0
TEST_COUNT=0

# shellcheck source=tests/verify-ansible.sh
source "${ROOT_DIR}/tests/verify-ansible.sh"
set -e

make_public_key_line() {
  local prefix="ssh-ed25519"
  local key_tail
  key_tail="$(printf 'A%.0s' {1..90})"
  printf '%s AAAA%s fixture-comment\n' "${prefix}" "${key_tail}"
}

make_ed25519_wire_key_line() {
  python3 - <<'PY'
import base64
import struct

key_type = b"ssh-ed25519"
public_key = bytes(range(32))
wire = (
    struct.pack(">I", len(key_type))
    + key_type
    + struct.pack(">I", len(public_key))
    + public_key
)
payload = base64.b64encode(wire).decode("ascii")
assert len(payload) == 68
print(f"ssh-ed25519 {payload} fixture-comment")
PY
}

init_repo() {
  local repo="${1}"
  mkdir -p "${repo}"
  git -C "${repo}" init -q
}

capture_scan() {
  local repo="${1}"
  : >"${SCAN_STDOUT}"
  : >"${SCAN_STDERR}"
  if scan_project_public_key_candidates "${repo}" \
    >"${SCAN_STDOUT}" 2>"${SCAN_STDERR}"; then
    SCAN_STATUS=0
  else
    SCAN_STATUS=$?
  fi
}

capture_scan_without_git() {
  local repo="${1}"
  : >"${SCAN_STDOUT}"
  : >"${SCAN_STDERR}"
  if (
    # shellcheck disable=SC2123
    PATH="/nonexistent"
    hash -r
    scan_project_public_key_candidates "${repo}"
  ) >"${SCAN_STDOUT}" 2>"${SCAN_STDERR}"; then
    SCAN_STATUS=0
  else
    SCAN_STATUS=$?
  fi
}

assert_status() {
  local expected="${1}"
  local label="${2}"
  TEST_COUNT=$((TEST_COUNT + 1))
  if [[ "${SCAN_STATUS}" -ne "${expected}" ]]; then
    echo "FAIL: ${label}: expected status ${expected}, got ${SCAN_STATUS}" >&2
    sed -n '1,20p' "${SCAN_STDOUT}" >&2
    sed -n '1,20p' "${SCAN_STDERR}" >&2
    exit 1
  fi
}

assert_stderr_contains() {
  local expected="${1}"
  local label="${2}"
  TEST_COUNT=$((TEST_COUNT + 1))
  if ! grep -Fq -- "${expected}" "${SCAN_STDERR}"; then
    echo "FAIL: ${label}: stderr did not contain: ${expected}" >&2
    sed -n '1,20p' "${SCAN_STDERR}" >&2
    exit 1
  fi
}

assert_stdout_empty() {
  local label="${1}"
  TEST_COUNT=$((TEST_COUNT + 1))
  if [[ -s "${SCAN_STDOUT}" ]]; then
    echo "FAIL: ${label}: expected empty stdout" >&2
    sed -n '1,20p' "${SCAN_STDOUT}" >&2
    exit 1
  fi
}

assert_stdout_contains() {
  local expected="${1}"
  local label="${2}"
  TEST_COUNT=$((TEST_COUNT + 1))
  if ! grep -Fq -- "${expected}" "${SCAN_STDOUT}"; then
    echo "FAIL: ${label}: stdout did not contain: ${expected}" >&2
    sed -n '1,20p' "${SCAN_STDOUT}" >&2
    exit 1
  fi
}

assert_equal() {
  local expected="${1}"
  local actual="${2}"
  local label="${3}"
  TEST_COUNT=$((TEST_COUNT + 1))
  if [[ "${actual}" != "${expected}" ]]; then
    echo "FAIL: ${label}: expected ${expected}, got ${actual}" >&2
    exit 1
  fi
}

repo="${TEST_TMP}/ignored-third-party"
init_repo "${repo}"
printf '.verify-dev/\n' >"${repo}/.gitignore"
git -C "${repo}" add .gitignore
mkdir -p "${repo}/.verify-dev/collections/upstream/tests"
make_public_key_line >"${repo}/.verify-dev/collections/upstream/tests/key.txt"
capture_scan "${repo}"
assert_status 0 "ignored third-party fixture"
assert_stdout_empty "ignored third-party fixture remains silent"

repo="${TEST_TMP}/untracked-source"
init_repo "${repo}"
make_public_key_line >"${repo}/new-source.txt"
capture_scan "${repo}"
assert_status 1 "untracked source key is rejected"
assert_stdout_contains "new-source.txt" "untracked source key reports path"

repo="${TEST_TMP}/standard-ed25519-untracked"
init_repo "${repo}"
ed25519_line="$(make_ed25519_wire_key_line)"
ed25519_payload="${ed25519_line#* }"
ed25519_payload="${ed25519_payload%% *}"
assert_equal 68 "${#ed25519_payload}" "structured Ed25519 wire payload length"
printf 'upstream_key: %s\n' "${ed25519_line}" >"${repo}/service.cfg"
capture_scan "${repo}"
assert_status 1 "68-character Ed25519 wire key is rejected"
assert_stdout_contains "service.cfg" "Ed25519 wire key reports candidate path"

repo="${TEST_TMP}/tracked-dirty-source"
init_repo "${repo}"
printf 'placeholder\n' >"${repo}/tracked-source.txt"
git -C "${repo}" add tracked-source.txt
make_public_key_line >"${repo}/tracked-source.txt"
capture_scan "${repo}"
assert_status 1 "dirty tracked source key is rejected"

repo="${TEST_TMP}/force-tracked-ignored"
init_repo "${repo}"
printf 'ignored-runtime/\n' >"${repo}/.gitignore"
git -C "${repo}" add .gitignore
mkdir -p "${repo}/ignored-runtime"
make_public_key_line >"${repo}/ignored-runtime/upstream.txt"
git -C "${repo}" add -f ignored-runtime/upstream.txt
capture_scan "${repo}"
assert_status 1 "force-tracked ignored key is rejected"
assert_stdout_contains "ignored-runtime/upstream.txt" "force-tracked key reports path"

repo="${TEST_TMP}/space-path"
init_repo "${repo}"
make_public_key_line >"${repo}/source with spaces.txt"
capture_scan "${repo}"
assert_status 1 "NUL-delimited path with spaces is scanned"
assert_stdout_contains "source with spaces.txt" "path with spaces is reported intact"

repo="${TEST_TMP}/deleted-tracked"
init_repo "${repo}"
printf 'placeholder\n' >"${repo}/deleted-source.txt"
git -C "${repo}" add deleted-source.txt
rm "${repo}/deleted-source.txt"
capture_scan "${repo}"
assert_status 0 "deleted tracked file is skipped"

repo="${TEST_TMP}/documentation-exceptions"
init_repo "${repo}"
make_public_key_line >"${repo}/README.md"
make_public_key_line >"${repo}/verify-ansible.sh"
capture_scan "${repo}"
assert_status 0 "documentation and verifier exemptions are preserved"

repo="${TEST_TMP}/short-placeholders"
init_repo "${repo}"
cat >"${repo}/config.cfg" <<'EOF'
identity: ssh-ed25519
authorized_key: ssh-ed25519 AAAATEST workstation
EOF
capture_scan "${repo}"
assert_status 0 "short SSH placeholders remain allowed"
assert_stdout_empty "short SSH placeholders remain silent"

repo="${TEST_TMP}/not-a-repository"
mkdir -p "${repo}"
capture_scan "${repo}"
assert_status 2 "non-Git directory fails closed"
assert_stderr_contains "候选源" "non-Git failure is explicit"

repo="${TEST_TMP}/git-unavailable"
init_repo "${repo}"
capture_scan_without_git "${repo}"
assert_status 2 "missing Git fails closed"
assert_stderr_contains "需要 Git" "missing Git failure is explicit"

echo "SSH 公钥候选源边界测试通过（${TEST_COUNT} 项断言）。"
