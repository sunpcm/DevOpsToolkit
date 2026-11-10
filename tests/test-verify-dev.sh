#!/usr/bin/env bash
set -euo pipefail

# This test builds isolated fixture environments and must not reuse controls
# inherited from a parent verification run (notably a custom state directory).
PARENT_ISOLATION_CHILD="${VDS_TEST_PARENT_ISOLATION_CHILD:-}"
unset \
  DEVOPS_TOOLKIT_VERIFY_DEV_STATE_DIR \
  DEVOPS_TOOLKIT_EXPECT_ANSIBLE_CORE \
  VDS_ACTIONLINT_MODULE_VERSION \
  VDS_GITLEAKS_MODULE_VERSION \
  VDS_GITLEAKS_MODULE_PATH \
  ANSIBLE_COLLECTIONS_PATHS \
  VDS_TEST_PARENT_ISOLATION_CHILD

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
cleanup() {
  local status=$?
  if [[ -n "${DEVOPS_TOOLKIT_TEST_KEEP_TMP:-}" ]]; then
    echo "保留测试目录：${TMP_DIR}" >&2
  else
    rm -rf "$TMP_DIR"
  fi
  return "$status"
}
trap cleanup EXIT

fail() {
  echo "错误：$*" >&2
  exit 1
}

FIXTURE="${TMP_DIR}/repo"
MOCKS="${TMP_DIR}/mocks"
LOG_DIR="${TMP_DIR}/logs"
mkdir -p \
  "$FIXTURE/.github/workflows" \
  "$FIXTURE/ansible" \
  "$FIXTURE/bin" \
  "$FIXTURE/scripts" \
  "$FIXTURE/tests" \
  "$MOCKS" \
  "$LOG_DIR"

cp "$ROOT_DIR/scripts/verify-dev.sh" "$FIXTURE/scripts/verify-dev.sh"
cp "$ROOT_DIR/scripts/verify-collection-lock.py" \
  "$FIXTURE/scripts/verify-collection-lock.py"
cp "$ROOT_DIR/requirements-dev.txt" "$FIXTURE/requirements-dev.txt"
cp "$ROOT_DIR/.gitignore" "$FIXTURE/.gitignore"
printf '%s\n' '---' 'extends: default' >"$FIXTURE/.yamllint.yml"
printf '%s\n' '---' 'profile: basic' >"$FIXTURE/.ansible-lint"
printf '%s\n' '---' 'jobs:' '  test:' '    runs-on: ubuntu-24.04' '    steps:' '      - run: echo ok' \
  >"$FIXTURE/.github/workflows/test.yml"
printf '%s\n' '---' 'collections:' '  - name: acme.tools' '    version: "1.2.3"' \
  >"$FIXTURE/ansible/requirements.yml"
cat >"$FIXTURE/ansible/collections.lock.json" <<'EOF'
{
  "schema": 1,
  "collections": [
    {
      "name": "acme.tools",
      "version": "1.2.3",
      "artifact": "acme-tools-1.2.3.tar.gz",
      "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    }
  ]
}
EOF
cat >"$FIXTURE/tests/verify-ansible.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' verify-ansible >>"${LOG_DIR}/verify-ansible.log"
EOF
cat >"$FIXTURE/bin/fixture-wrapper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
cat >"$FIXTURE/tests/test-ssh-security.py" <<'EOF'
"""Fixture for future Python file discovery."""

VALUE = 1
EOF
chmod +x \
  "$FIXTURE/scripts/verify-dev.sh" \
  "$FIXTURE/tests/verify-ansible.sh" \
  "$FIXTURE/bin/fixture-wrapper"

EXPECTED_ANSIBLE_CORE="$(
  awk -F '==' '$1 == "ansible-core" { print $2; exit }' \
    "$ROOT_DIR/requirements-dev.txt"
)"
python3 - \
  "$ROOT_DIR/.github/workflows/env-check.yml" \
  "$EXPECTED_ANSIBLE_CORE" <<'PY'
import re
import sys
from pathlib import Path

workflow = Path(sys.argv[1]).read_text(encoding="utf-8")
expected_core = sys.argv[2]

assert re.search(r"^  quality:$", workflow, flags=re.MULTILINE)
validate = workflow.split("\n  validate:\n", 1)[1]
include_block = validate.split("        include:\n", 1)[1].split("    steps:\n", 1)[0]
entries = re.findall(
    r'^\s+- python: "([^"]+)"\n\s+ansible_core: "([^"]+)"$',
    include_block,
    flags=re.MULTILINE,
)
assert entries == [("3.12", expected_core), ("3.14", expected_core)], entries
assert (
    "      DEVOPS_TOOLKIT_EXPECT_ANSIBLE_CORE: ${{ matrix.ansible_core }}"
    in validate
)
assert "./scripts/verify-dev.sh --bootstrap --python python3" in workflow
assert (
    "./scripts/verify-dev.sh --bootstrap --ansible-only --python python3"
    in workflow
)
assert "./scripts/verify-dev.sh --ansible-only" in workflow
assert "ansible-core==" not in workflow
assert "actionlint@v" not in workflow
assert "gitleaks/v8@v" not in workflow
PY

git -C "$FIXTURE" init -q
git -C "$FIXTURE" add .
git -C "$FIXTURE" \
  -c user.name=verify-dev-test \
  -c user.email=verify-dev-test@example.invalid \
  commit -qm fixture

printf '\nDIRTY_SOURCE_MARKER\n' >>"$FIXTURE/tests/test-ssh-security.py"
printf '%s\n' UNTRACKED_SOURCE_MARKER \
  >"$FIXTURE/tests/untracked-candidate.txt"
mkdir -p "$FIXTURE/.review" "$FIXTURE/.venv"
printf '%s\n' IGNORED_REVIEW_MARKER >"$FIXTURE/.review/ignored.txt"
printf '%s\n' IGNORED_VENV_MARKER >"$FIXTURE/.venv/ignored.txt"

cat >"$MOCKS/python3.14" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == "--version" ]] || exit 64
printf '%s\n' 'Python 3.14.2'
EOF
cat >"$MOCKS/python3.15" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == "--version" ]] || exit 64
printf '%s\n' 'Python 3.15.1'
EOF
cat >"$MOCKS/go" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >>"${LOG_DIR}/go.log"
if [[ "\${1:-}" == "version" && "\${2:-}" == "-m" ]]; then
  binary="\${3:-}"
  case "\$binary" in
    *actionlint*)
      module_version="\${VDS_ACTIONLINT_MODULE_VERSION:-v1.7.7}"
      printf 'path\tgithub.com/rhysd/actionlint/cmd/actionlint\n'
      printf 'mod\tgithub.com/rhysd/actionlint\t%s\th1:fixture\n' "\$module_version"
      ;;
    *gitleaks*)
      module_path="\${VDS_GITLEAKS_MODULE_PATH:-github.com/zricethezav/gitleaks/v8}"
      module_version="\${VDS_GITLEAKS_MODULE_VERSION:-v8.24.3}"
      printf 'path\tgithub.com/zricethezav/gitleaks/v8\n'
      printf 'mod\t%s\t%s\th1:fixture\n' "\$module_path" "\$module_version"
      ;;
    *)
      exit 69
      ;;
  esac
  exit 0
fi
[[ "\${1:-}" == "install" ]] || exit 64
mkdir -p "\${GOBIN}"
case "\${2:-}" in
  *actionlint*)
    cat >"\${GOBIN}/actionlint" <<'TOOL'
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "--version" ]]; then
  printf '%s\n' \
    'v1.7.7' \
    'installed by building from source' \
    'built with go1.27.3 compiler for darwin/arm64'
else
  printf '%s\n' actionlint >>"${LOG_DIR}/actionlint.log"
fi
TOOL
    ;;
  *gitleaks*)
    cat >"\${GOBIN}/gitleaks" <<'TOOL'
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "version" ]]; then
  printf '%s\n' 'version is set by build process'
else
  printf '%s\n' "\$*" >>"${LOG_DIR}/gitleaks.log"
  no_git=false
  source_dir=""
  expect_source=false
  for argument in "\$@"; do
    if [[ "\$expect_source" == true ]]; then
      source_dir="\$argument"
      expect_source=false
    elif [[ "\$argument" == "--source" ]]; then
      expect_source=true
    elif [[ "\$argument" == "--no-git" ]]; then
      no_git=true
    fi
  done
  if [[ "\$no_git" == true ]]; then
    [[ -f "\${source_dir}/tests/test-ssh-security.py" ]]
    grep -F DIRTY_SOURCE_MARKER "\${source_dir}/tests/test-ssh-security.py" >/dev/null
    [[ -f "\${source_dir}/tests/untracked-candidate.txt" ]]
    [[ ! -e "\${source_dir}/.review" ]]
    [[ ! -e "\${source_dir}/.venv" ]]
    [[ ! -e "\${source_dir}/.verify-dev" ]]
    printf '%s\n' source-scan-ok >>"${LOG_DIR}/gitleaks-source.log"
  fi
fi
TOOL
    ;;
  *)
    exit 65
    ;;
esac
chmod +x "\${GOBIN}/actionlint" "\${GOBIN}/gitleaks" 2>/dev/null || true
EOF
chmod +x "$MOCKS/python3.14" "$MOCKS/python3.15" "$MOCKS/go"

REAL_PYTHON="$(command -v python3)"
VENV_BIN="$FIXTURE/.verify-dev/venv/bin"
mkdir -p "$VENV_BIN"
cat >"$VENV_BIN/python" <<EOF
#!/usr/bin/env bash
set -euo pipefail
case "\${1:-}" in
  --version)
    printf '%s\n' 'Python 3.14.2'
    ;;
  -c)
    code="\${2:-}"
    case "\$code" in
      *sys.prefix*base_prefix*)
        printf '%s\n' 1
        ;;
      *importlib.metadata*)
        package="\${3:-}"
        case "\$package" in
          ansible-core) printf '%s\n' 2.21.4 ;;
          ansible-lint) printf '%s\n' 26.8.0 ;;
          yamllint) printf '%s\n' 1.38.0 ;;
          ruff) printf '%s\n' 0.9.10 ;;
          shellcheck-py) printf '%s\n' 0.11.0.1 ;;
          *) exit 66 ;;
        esac
        ;;
      *)
        exit 67
        ;;
    esac
    ;;
  -m)
    if [[ "\${2:-}" == "pip" ]]; then
      printf '%s|%s\n' "\${PIP_CACHE_DIR:-}" "\$*" >>"${LOG_DIR}/pip.log"
    else
      exit 68
    fi
    ;;
  *)
    exec "${REAL_PYTHON}" "\$@"
    ;;
esac
EOF

write_version_tool() {
  local name="$1"
  local version_flag="$2"
  local version="$3"
  cat >"$VENV_BIN/$name" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "$version_flag" ]]; then
  printf '%s\n' "$name $version"
else
  printf '%s\n' "\$*" >>"${LOG_DIR}/$name.log"
fi
EOF
  chmod +x "$VENV_BIN/$name"
}

cat >"$VENV_BIN/ansible-lint" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "\${ANSIBLE_COLLECTIONS_PATHS+x}" ]]; then
  printf '%s\n' \
    'ANSIBLE_COLLECTIONS_PATHS was detected, replace it with ANSIBLE_COLLECTIONS_PATH to continue.' \
    >&2
  exit 1
fi
state_dir="\${DEVOPS_TOOLKIT_VERIFY_DEV_STATE_DIR:-${FIXTURE}/.verify-dev}"
expected_collections_path="\${state_dir}/collections"
if [[ "\${ANSIBLE_COLLECTIONS_PATH:-}" != "\${expected_collections_path}" ]]; then
  printf 'ANSIBLE_COLLECTIONS_PATH mismatch: expected %s, got %s\n' \
    "\${expected_collections_path}" "\${ANSIBLE_COLLECTIONS_PATH:-unset}" >&2
  exit 1
fi
if [[ "\${1:-}" == "--version" ]]; then
  printf '%s\n' 'ansible-lint 26.8.0'
else
  printf '%s\n' "\$*" >>"${LOG_DIR}/ansible-lint.log"
fi
EOF
write_version_tool yamllint --version 1.38.0
write_version_tool ruff --version 0.9.10
cat >"$VENV_BIN/shellcheck" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "--version" ]]; then
  printf '%s\n' 'version: 0.11.0'
else
  printf '%s\n' "\$*" >>"${LOG_DIR}/shellcheck.log"
fi
EOF
cat >"$VENV_BIN/ansible-galaxy" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >>"${LOG_DIR}/galaxy.log"
state_dir="\${DEVOPS_TOOLKIT_VERIFY_DEV_STATE_DIR:-${FIXTURE}/.verify-dev}"
if [[ -n "\${ANSIBLE_COLLECTIONS_PATHS+x}" ]]; then
  printf '%s\n' 'bootstrap inherited deprecated ANSIBLE_COLLECTIONS_PATHS' >&2
  exit 1
fi
if [[ "\${ANSIBLE_COLLECTIONS_PATH:-}" != "\${state_dir}/collections" ]]; then
  printf 'bootstrap ANSIBLE_COLLECTIONS_PATH mismatch: expected %s, got %s\n' \
    "\${state_dir}/collections" "\${ANSIBLE_COLLECTIONS_PATH:-unset}" >&2
  exit 1
fi
mkdir -p "\${state_dir}/collections/ansible_collections/acme/tools"
printf '%s\n' \
  '{"collection_info":{"namespace":"acme","name":"tools","version":"1.2.3"}}' \
  >"\${state_dir}/collections/ansible_collections/acme/tools/MANIFEST.json"
EOF
cat >"$VENV_BIN/ansible-playbook" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x \
  "$VENV_BIN/python" \
  "$VENV_BIN/ansible-lint" \
  "$VENV_BIN/shellcheck" \
  "$VENV_BIN/ansible-galaxy" \
  "$VENV_BIN/ansible-playbook"

if PATH="$MOCKS:$PATH" \
  DEVOPS_TOOLKIT_VERIFY_DEV_STATE_DIR="$TMP_DIR/missing-state" \
  "$FIXTURE/scripts/verify-dev.sh" >"$TMP_DIR/default.out" 2>&1; then
  fail "默认验证在没有隔离环境时错误通过"
fi
grep -F '隔离环境不存在' "$TMP_DIR/default.out" >/dev/null || \
  fail "默认模式没有清晰说明缺少隔离环境"
[[ ! -e "$TMP_DIR/missing-state" ]] || fail "默认模式隐式创建了隔离环境"
[[ ! -e "$LOG_DIR/pip.log" && ! -e "$LOG_DIR/go.log" && ! -e "$LOG_DIR/galaxy.log" ]] || \
  fail "默认模式隐式执行了安装命令"

if PATH="$MOCKS:$PATH" \
  "$FIXTURE/scripts/verify-dev.sh" --bootstrap --python "$MOCKS/python3.15" \
  >"$TMP_DIR/unsupported.out" 2>&1; then
  fail "bootstrap 接受了不支持的 Python 3.15"
fi
grep -F '仅支持 Python 3.12、3.13、3.14' "$TMP_DIR/unsupported.out" >/dev/null || \
  fail "bootstrap 没有清晰拒绝不支持的 Python"

if DEVOPS_TOOLKIT_EXPECT_ANSIBLE_CORE=2.21.5 \
  PATH="$MOCKS:$PATH" \
  "$FIXTURE/scripts/verify-dev.sh" --bootstrap --python "$MOCKS/python3.14" \
  >"$TMP_DIR/ci-pin-drift.out" 2>&1; then
  fail "CI 矩阵 ansible-core 漂移时错误通过"
fi
grep -F 'CI ansible-core 版本与共享依赖 pin 不一致' "$TMP_DIR/ci-pin-drift.out" >/dev/null || \
  fail "CI 矩阵 ansible-core 漂移没有清晰失败"

PATH="$MOCKS:$PATH" \
  "$FIXTURE/scripts/verify-dev.sh" \
  --bootstrap --ansible-only --python "$MOCKS/python3.14" \
  >"$TMP_DIR/ansible-bootstrap.out" 2>&1 || {
    cat "$TMP_DIR/ansible-bootstrap.out" >&2
    fail "Ansible-only bootstrap 失败"
  }
grep -F 'ansible-core==2.21.4' "$LOG_DIR/pip.log" >/dev/null || \
  fail "Ansible-only bootstrap 没有安装固定 core"
grep -F "${FIXTURE}/.verify-dev/pip-cache|" "$LOG_DIR/pip.log" >/dev/null || \
  fail "Ansible-only bootstrap 没有使用仓库内 pip cache"
if grep -F -- '--requirement' "$LOG_DIR/pip.log" >/dev/null; then
  fail "Ansible-only bootstrap 安装了完整 lint 依赖"
fi
[[ ! -e "$LOG_DIR/go.log" ]] || fail "Ansible-only bootstrap 编译了 Go lint 工具"

PATH="$MOCKS:$PATH" \
  "$FIXTURE/scripts/verify-dev.sh" --bootstrap --python "$MOCKS/python3.14" \
  >"$TMP_DIR/bootstrap.out" 2>&1 || {
    cat "$TMP_DIR/bootstrap.out" >&2
    fail "显式 bootstrap 失败"
  }
grep -F -- '--requirement' "$LOG_DIR/pip.log" >/dev/null || fail "bootstrap 没有安装共享依赖"
grep -F 'actionlint/cmd/actionlint@v1.7.7' "$LOG_DIR/go.log" >/dev/null || \
  fail "bootstrap 没有安装固定 actionlint"
grep -F 'gitleaks/v8@v8.24.3' "$LOG_DIR/go.log" >/dev/null || \
  fail "bootstrap 没有安装固定 gitleaks"
grep -F -- '--requirements-file' "$LOG_DIR/galaxy.log" >/dev/null || \
  fail "bootstrap 没有安装锁定 collections"
grep -F 'gitleaks：CLI 为 not-reported，已通过 Go build metadata 确认 github.com/zricethezav/gitleaks/v8 v8.24.3' \
  "$TMP_DIR/bootstrap.out" >/dev/null || \
  fail "bootstrap 没有从真实 gitleaks 非 release CLI 格式回退到精确 build metadata"

if ! env \
  ANSIBLE_COLLECTIONS_PATH="$TMP_DIR/inherited-singular-collections" \
  ANSIBLE_COLLECTIONS_PATHS="$TMP_DIR/inherited-plural-collections" \
  PATH="$MOCKS:$PATH" \
  "$FIXTURE/scripts/verify-dev.sh" >"$TMP_DIR/full.out" 2>&1; then
  cat "$TMP_DIR/full.out" >&2
  fail "父环境 collections 变量导致完整离线 mock 验证失败"
fi
grep -F 'bin/fixture-wrapper' "$LOG_DIR/shellcheck.log" >/dev/null || \
  fail "ShellCheck 没有覆盖无扩展名 shell wrapper"
grep -F 'tests/test-ssh-security.py' "$LOG_DIR/ruff.log" >/dev/null || \
  fail "Ruff 没有自动发现未来的 SSH 安全测试"
grep -Fx -- '--offline ansible' "$LOG_DIR/ansible-lint.log" >/dev/null || \
  fail "ansible-lint 没有使用已安装 collections 的离线模式"
[[ "$(cat "$LOG_DIR/actionlint.log")" == "actionlint" ]] || fail "actionlint 命令转发错误"
grep -F -- '--no-git' "$LOG_DIR/gitleaks.log" >/dev/null || \
  fail "gitleaks 没有扫描 dirty/untracked 源候选"
grep -Fx 'source-scan-ok' "$LOG_DIR/gitleaks-source.log" >/dev/null || \
  fail "gitleaks 源候选内容或排除范围错误"
[[ "$(wc -l <"$LOG_DIR/gitleaks.log" | tr -d ' ')" == "2" ]] || \
  fail "gitleaks 未分别扫描历史和源候选"
if grep -Eq '^version -m .*/actionlint$' "$LOG_DIR/go.log"; then
  fail "actionlint 的真实 CLI 版本格式未直接识别，错误回退到 build metadata"
fi
[[ "$(wc -l <"$LOG_DIR/verify-ansible.log" | tr -d ' ')" == "1" ]] || \
  fail "verify-ansible.sh 未被调用一次"

mv "$FIXTURE/.verify-dev/go" "$TMP_DIR/go.saved"
PATH="$MOCKS:$PATH" \
  "$FIXTURE/scripts/verify-dev.sh" --ansible-only \
  >"$TMP_DIR/ansible-only.out" 2>&1 || {
    cat "$TMP_DIR/ansible-only.out" >&2
    fail "Ansible-only 验证仍依赖 Go lint 工具"
  }
mv "$TMP_DIR/go.saved" "$FIXTURE/.verify-dev/go"

SYNTHETIC_STATE="$TMP_DIR/synthetic-custom-state"
cp -R "$FIXTURE/.verify-dev" "$SYNTHETIC_STATE"
rm -rf \
  "$SYNTHETIC_STATE/collections" \
  "$SYNTHETIC_STATE/go" \
  "$SYNTHETIC_STATE/pip-cache"
rm -f \
  "$LOG_DIR/pip.log" \
  "$LOG_DIR/go.log" \
  "$LOG_DIR/galaxy.log"
PATH="$MOCKS:$PATH" \
  DEVOPS_TOOLKIT_VERIFY_DEV_STATE_DIR="$SYNTHETIC_STATE" \
  "$FIXTURE/scripts/verify-dev.sh" \
  --bootstrap --ansible-only --python "$MOCKS/python3.14" \
  >"$TMP_DIR/custom-state-bootstrap.out" 2>&1 || {
    cat "$TMP_DIR/custom-state-bootstrap.out" >&2
    fail "显式 custom state 的 Ansible-only bootstrap 失败"
  }
grep -F "${SYNTHETIC_STATE}/pip-cache|" \
  "$LOG_DIR/pip.log" >/dev/null || \
  fail "custom state 没有隔离 pip cache"
grep -F 'ansible-core==2.21.4' "$LOG_DIR/pip.log" >/dev/null || \
  fail "custom state 没有安装固定 ansible-core"
grep -F -- "--collections-path ${SYNTHETIC_STATE}/collections" \
  "$LOG_DIR/galaxy.log" >/dev/null || \
  fail "custom state 没有隔离 collections"
[[ -f "$SYNTHETIC_STATE/collections/ansible_collections/acme/tools/MANIFEST.json" ]] || \
  fail "custom state 的 collections 未写入覆盖目录"
[[ ! -e "$SYNTHETIC_STATE/go" ]] || \
  fail "custom state 的 Ansible-only bootstrap 错误创建 Go 工具目录"
[[ ! -e "$LOG_DIR/go.log" ]] || \
  fail "custom state 的 Ansible-only bootstrap 错误编译 Go 工具"

cp "$FIXTURE/.verify-dev/go/bin/actionlint" "$TMP_DIR/actionlint.original"
cat >"$FIXTURE/.verify-dev/go/bin/actionlint" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "--version" ]]; then
  printf '%s\n' dev
else
  printf '%s\n' actionlint >>"${LOG_DIR}/actionlint.log"
fi
EOF
chmod +x "$FIXTURE/.verify-dev/go/bin/actionlint"
PATH="$MOCKS:$PATH" \
"$FIXTURE/scripts/verify-dev.sh" >"$TMP_DIR/metadata-version.out" 2>&1 || {
  cat "$TMP_DIR/metadata-version.out" >&2
  fail "Go build metadata 未接受无 release CLI 版本的固定工具"
}
grep -F 'Go build metadata' "$TMP_DIR/metadata-version.out" >/dev/null || \
  fail "版本确认没有明确使用 Go build metadata"

if VDS_ACTIONLINT_MODULE_VERSION=v1.7.8 PATH="$MOCKS:$PATH" \
  "$FIXTURE/scripts/verify-dev.sh" >"$TMP_DIR/metadata-drift.out" 2>&1; then
  fail "Go build metadata 版本漂移时错误通过"
fi
grep -F 'Go build metadata 不匹配' "$TMP_DIR/metadata-drift.out" >/dev/null || \
  fail "Go build metadata 漂移没有清晰失败"
cp "$TMP_DIR/actionlint.original" "$FIXTURE/.verify-dev/go/bin/actionlint"

if VDS_GITLEAKS_MODULE_VERSION=v8.24.4 PATH="$MOCKS:$PATH" \
  "$FIXTURE/scripts/verify-dev.sh" >"$TMP_DIR/gitleaks-metadata-drift.out" 2>&1; then
  fail "gitleaks 非 release CLI 格式下的 metadata 漂移错误通过"
fi
grep -F 'gitleaks CLI 未报告 release 版本，且 Go build metadata 不匹配' \
  "$TMP_DIR/gitleaks-metadata-drift.out" >/dev/null || \
  fail "gitleaks metadata 漂移没有清晰失败"

if VDS_GITLEAKS_MODULE_PATH=example.invalid/gitleaks PATH="$MOCKS:$PATH" \
  "$FIXTURE/scripts/verify-dev.sh" >"$TMP_DIR/gitleaks-module-drift.out" 2>&1; then
  fail "gitleaks 非 release CLI 格式下的 main module 路径漂移错误通过"
fi
grep -F 'gitleaks CLI 未报告 release 版本，且 Go build metadata 不匹配' \
  "$TMP_DIR/gitleaks-module-drift.out" >/dev/null || \
  fail "gitleaks main module 路径漂移没有清晰失败"

cp "$FIXTURE/.verify-dev/go/bin/gitleaks" "$TMP_DIR/gitleaks.original"
cat >"$FIXTURE/.verify-dev/go/bin/gitleaks" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "version" ]]; then
  printf '%s\n' v8.24.4
else
  printf '%s\n' "$*" >>"${LOG_DIR}/gitleaks.log"
fi
EOF
chmod +x "$FIXTURE/.verify-dev/go/bin/gitleaks"
if PATH="$MOCKS:$PATH" \
  "$FIXTURE/scripts/verify-dev.sh" >"$TMP_DIR/gitleaks-cli-drift.out" 2>&1; then
  fail "gitleaks CLI 明确报告错误版本时错误通过"
fi
grep -F 'gitleaks 版本漂移：需要 8.24.3，CLI 报告 8.24.4' \
  "$TMP_DIR/gitleaks-cli-drift.out" >/dev/null || \
  fail "gitleaks CLI 版本漂移没有清晰失败"
mv "$TMP_DIR/gitleaks.original" "$FIXTURE/.verify-dev/go/bin/gitleaks"

mv "$FIXTURE/.verify-dev/go/bin/actionlint" "$TMP_DIR/actionlint.saved"
if PATH="$MOCKS:$PATH" "$FIXTURE/scripts/verify-dev.sh" >"$TMP_DIR/missing-tool.out" 2>&1; then
  fail "缺少 actionlint 时错误通过"
fi
grep -F '缺少工具' "$TMP_DIR/missing-tool.out" >/dev/null || \
  fail "缺少工具时没有清晰失败"
mv "$TMP_DIR/actionlint.saved" "$FIXTURE/.verify-dev/go/bin/actionlint"

cat >"$FIXTURE/.verify-dev/go/bin/actionlint" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' 1.7.8
EOF
chmod +x "$FIXTURE/.verify-dev/go/bin/actionlint"
if PATH="$MOCKS:$PATH" "$FIXTURE/scripts/verify-dev.sh" >"$TMP_DIR/version-drift.out" 2>&1; then
  fail "工具版本漂移时错误通过"
fi
grep -F 'actionlint 版本漂移' "$TMP_DIR/version-drift.out" >/dev/null || \
  fail "工具版本漂移没有清晰失败"

if [[ "$PARENT_ISOLATION_CHILD" != 1 ]]; then
  PARENT_STATE="$TMP_DIR/parent-custom-state"
  PARENT_SENTINEL="$PARENT_STATE/venv/bin/parent-sentinel"
  mkdir -p "$(dirname "$PARENT_SENTINEL")"
  printf '%s\n' 'parent-state-must-remain-untouched' >"$PARENT_SENTINEL"
  parent_sentinel_before="$(cksum "$PARENT_SENTINEL")"
  parent_tree_before="$(
    find "$PARENT_STATE" -print | LC_ALL=C sort
  )"

  if ! env \
    DEVOPS_TOOLKIT_VERIFY_DEV_STATE_DIR="$PARENT_STATE" \
    DEVOPS_TOOLKIT_EXPECT_ANSIBLE_CORE=9.9.9 \
    VDS_ACTIONLINT_MODULE_VERSION=v9.9.9 \
    VDS_GITLEAKS_MODULE_VERSION=v9.9.9 \
    VDS_GITLEAKS_MODULE_PATH=example.invalid/gitleaks \
    ANSIBLE_COLLECTIONS_PATH="$PARENT_STATE/inherited-singular-collections" \
    ANSIBLE_COLLECTIONS_PATHS="$PARENT_STATE/inherited-plural-collections" \
    VDS_TEST_PARENT_ISOLATION_CHILD=1 \
    "$ROOT_DIR/tests/test-verify-dev.sh" \
    >"$TMP_DIR/parent-isolation-child.out" 2>&1; then
    cat "$TMP_DIR/parent-isolation-child.out" >&2
    fail "父级 verification 控制变量泄漏到 fixture 子进程"
  fi

  parent_sentinel_after="$(cksum "$PARENT_SENTINEL")"
  parent_tree_after="$(
    find "$PARENT_STATE" -print | LC_ALL=C sort
  )"
  [[ "$parent_sentinel_after" == "$parent_sentinel_before" ]] || \
    fail "fixture 测试修改了父级 custom state 的 sentinel"
  [[ "$parent_tree_after" == "$parent_tree_before" ]] || \
    fail "fixture 测试在父级 custom state 中创建或删除了文件"
fi

echo "统一开发验证入口测试通过。"
