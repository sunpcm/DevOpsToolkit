#!/usr/bin/env bash
set -euo pipefail

# ansible-lint 26.x refuses to start when the deprecated plural variable is
# inherited, so isolate verification from any parent shell that still sets it.
unset ANSIBLE_COLLECTIONS_PATHS

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${DEVOPS_TOOLKIT_VERIFY_DEV_STATE_DIR:-${ROOT_DIR}/.verify-dev}"
REQUIREMENTS_FILE="${ROOT_DIR}/requirements-dev.txt"
VENV_DIR="${STATE_DIR}/venv"
VENV_BIN="${VENV_DIR}/bin"
VENV_PYTHON="${VENV_BIN}/python"
COLLECTIONS_DIR="${STATE_DIR}/collections"
PIP_CACHE_DIR="${STATE_DIR}/pip-cache"
GO_BIN="${STATE_DIR}/go/bin"
ACTIONLINT_BIN="${GO_BIN}/actionlint"
GITLEAKS_BIN="${GO_BIN}/gitleaks"

usage() {
  cat <<'EOF'
用法：
  ./scripts/verify-dev.sh [--ansible-only]
  ./scripts/verify-dev.sh --bootstrap [--ansible-only] [--python /path/to/python3.12-3.14]

默认模式只使用仓库内 .verify-dev/ 环境执行完整静态验证，不会安装软件。
--bootstrap 显式创建或更新 .verify-dev/：验证 Python 3.12-3.14，安装
requirements-dev.txt 中的精确版本，安装固定版本 actionlint/gitleaks，并安装
ansible/requirements.yml 对应且通过 collections.lock.json 校验的 collections。
与 --ansible-only 组合时只安装 ansible-core 和 collections，不编译其他 lint 工具。
--ansible-only 只执行 tests/verify-ansible.sh，供 CI 的 Python 版本矩阵复用。
EOF
}

fail() {
  printf '错误：%s\n' "$*" >&2
  exit 1
}

bootstrap=false
ansible_only=false
python_override=""
while (( $# > 0 )); do
  case "$1" in
    --bootstrap)
      bootstrap=true
      ;;
    --ansible-only)
      ansible_only=true
      ;;
    --python)
      (( $# >= 2 )) || fail "--python 需要跟随一个 Python 可执行文件路径。"
      python_override="$2"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "未知参数：$1"
      ;;
  esac
  shift
done

if [[ "$STATE_DIR" == "/" || "$STATE_DIR" == "$ROOT_DIR" ]]; then
  fail "隔离环境目录不能是 / 或仓库根目录。"
fi
if [[ ! -f "$REQUIREMENTS_FILE" ]]; then
  fail "缺少共享依赖清单：${REQUIREMENTS_FILE}"
fi
if ! command -v git >/dev/null 2>&1; then
  fail "缺少 git，无法只扫描版本控制内的开发文件。"
fi

cd "$ROOT_DIR"

read_python_pin() {
  local package="$1"
  local value
  value="$(awk -F '==' -v package="$package" '$1 == package { print $2; exit }' "$REQUIREMENTS_FILE")"
  [[ -n "$value" ]] || fail "requirements-dev.txt 缺少 ${package}==<version>。"
  printf '%s\n' "$value"
}

read_go_pin() {
  local tool_name="$1"
  local value
  value="$(
    awk -v tool_name="$tool_name" \
      '$1 == "#" && $2 == "go-tool" && $3 == tool_name { print $4; exit }' \
      "$REQUIREMENTS_FILE"
  )"
  [[ -n "$value" ]] || fail "requirements-dev.txt 缺少 go-tool ${tool_name} 版本。"
  printf '%s\n' "$value"
}

ANSIBLE_CORE_VERSION="$(read_python_pin ansible-core)"
ANSIBLE_LINT_VERSION="$(read_python_pin ansible-lint)"
YAMLLINT_VERSION="$(read_python_pin yamllint)"
RUFF_VERSION="$(read_python_pin ruff)"
SHELLCHECK_PY_VERSION="$(read_python_pin shellcheck-py)"
SHELLCHECK_VERSION="${SHELLCHECK_PY_VERSION%.*}"
ACTIONLINT_VERSION="$(read_go_pin actionlint)"
GITLEAKS_VERSION="$(read_go_pin gitleaks)"

EXPECTED_ANSIBLE_CORE="${DEVOPS_TOOLKIT_EXPECT_ANSIBLE_CORE:-}"
if [[ -n "$EXPECTED_ANSIBLE_CORE" && "$EXPECTED_ANSIBLE_CORE" != "$ANSIBLE_CORE_VERSION" ]]; then
  fail "CI ansible-core 版本与共享依赖 pin 不一致：CI=${EXPECTED_ANSIBLE_CORE}，requirements-dev.txt=${ANSIBLE_CORE_VERSION}。"
fi

python_version() {
  local python_bin="$1"
  local output version
  if ! output="$("$python_bin" --version 2>&1)"; then
    return 1
  fi
  [[ "$output" == Python\ * ]] || return 1
  version="${output#Python }"
  [[ "$version" =~ ^3\.(12|13|14)(\.|$) ]] || return 1
  printf '%s\n' "$version"
}

python_minor() {
  local version="$1"
  local major minor _
  IFS=. read -r major minor _ <<<"$version"
  printf '%s.%s\n' "$major" "$minor"
}

find_supported_python() {
  local requested="${1:-}"
  local candidate candidate_path version
  local -a candidates=()

  if [[ -n "$requested" ]]; then
    candidate_path="$(command -v "$requested" 2>/dev/null || true)"
    [[ -n "$candidate_path" ]] || fail "指定的 Python 不存在或不可执行：${requested}"
    version="$(python_version "$candidate_path" || true)"
    [[ -n "$version" ]] || fail "指定的 Python 不受支持：${candidate_path}。仅支持 Python 3.12、3.13、3.14。"
    printf '%s\n' "$candidate_path"
    return 0
  fi

  candidates=(python3.14 python3.13 python3.12 python3)
  for candidate in "${candidates[@]}"; do
    candidate_path="$(command -v "$candidate" 2>/dev/null || true)"
    [[ -n "$candidate_path" ]] || continue
    version="$(python_version "$candidate_path" || true)"
    if [[ -n "$version" ]]; then
      printf '%s\n' "$candidate_path"
      return 0
    fi
  done
  fail "未找到 Python 3.12、3.13 或 3.14。请安装受支持版本并使用 --bootstrap --python /path/to/python。"
}

safe_remove_generated_tree() {
  local target="$1"
  case "$target" in
    "${STATE_DIR}/venv"|"${STATE_DIR}/collections")
      rm -rf -- "$target"
      ;;
    *)
      fail "拒绝删除非托管路径：${target}"
      ;;
  esac
}

install_python_dependencies() {
  if [[ "$ansible_only" == true ]]; then
    "$VENV_PYTHON" -m pip install \
      --disable-pip-version-check \
      "ansible-core==${ANSIBLE_CORE_VERSION}"
  else
    "$VENV_PYTHON" -m pip install \
      --disable-pip-version-check \
      --requirement "$REQUIREMENTS_FILE"
  fi
}

install_go_tools() {
  command -v go >/dev/null 2>&1 || fail "缺少 go，无法在 --bootstrap 中安装 actionlint/gitleaks。"
  mkdir -p "$GO_BIN" "${STATE_DIR}/go/cache" "${STATE_DIR}/go/pkg/mod"
  GOBIN="$GO_BIN" \
    GOPATH="${STATE_DIR}/go" \
    GOMODCACHE="${STATE_DIR}/go/pkg/mod" \
    GOCACHE="${STATE_DIR}/go/cache" \
    GOTOOLCHAIN=local \
    go install "github.com/rhysd/actionlint/cmd/actionlint@v${ACTIONLINT_VERSION}"
  GOBIN="$GO_BIN" \
    GOPATH="${STATE_DIR}/go" \
    GOMODCACHE="${STATE_DIR}/go/pkg/mod" \
    GOCACHE="${STATE_DIR}/go/cache" \
    GOTOOLCHAIN=local \
    go install "github.com/zricethezav/gitleaks/v8@v${GITLEAKS_VERSION}"
}

bootstrap_environment() {
  local candidate selected_version existing_version
  candidate="$(find_supported_python "$python_override")"
  selected_version="$(python_version "$candidate")"
  mkdir -p "$STATE_DIR"

  existing_version=""
  if [[ -x "$VENV_PYTHON" ]]; then
    existing_version="$(python_version "$VENV_PYTHON" || true)"
  fi
  if [[ -n "$existing_version" && \
        "$(python_minor "$existing_version")" == "$(python_minor "$selected_version")" ]]; then
    printf '复用 Python %s 隔离环境：%s\n' "$existing_version" "$VENV_DIR"
  else
    safe_remove_generated_tree "$VENV_DIR"
    "$candidate" -m venv "$VENV_DIR"
    printf '创建 Python %s 隔离环境：%s\n' "$selected_version" "$VENV_DIR"
  fi

  [[ -x "$VENV_PYTHON" ]] || fail "venv 创建后缺少 Python：${VENV_PYTHON}"
  existing_version="$(python_version "$VENV_PYTHON" || true)"
  [[ -n "$existing_version" ]] || fail "venv 创建后的 Python 不受支持。"
  if [[ "$(python_minor "$existing_version")" != "$(python_minor "$selected_version")" ]]; then
    fail "venv Python 版本与请求不一致：请求 ${selected_version}，发现 ${existing_version}。"
  fi
  export PATH="${VENV_BIN}:${GO_BIN}:${PATH}"
  export VIRTUAL_ENV="$VENV_DIR"
  export PIP_CACHE_DIR="$PIP_CACHE_DIR"
  export PIP_DISABLE_PIP_VERSION_CHECK=1
  export ANSIBLE_COLLECTIONS_PATH="$COLLECTIONS_DIR"
  mkdir -p "$PIP_CACHE_DIR"

  install_python_dependencies
  if [[ "$ansible_only" != true ]]; then
    install_go_tools
    check_go_tool_versions
  fi

  safe_remove_generated_tree "$COLLECTIONS_DIR"
  mkdir -p "$COLLECTIONS_DIR"
  "$VENV_BIN/ansible-galaxy" collection install \
    --force \
    --requirements-file "${ROOT_DIR}/ansible/requirements.yml" \
    --collections-path "$COLLECTIONS_DIR"
  "$VENV_PYTHON" "${ROOT_DIR}/scripts/verify-collection-lock.py" \
    --lock "${ROOT_DIR}/ansible/collections.lock.json" \
    --requirements "${ROOT_DIR}/ansible/requirements.yml" \
    --installed "$COLLECTIONS_DIR"

  printf '隔离开发环境已就绪：%s\n' "$STATE_DIR"
}

metadata_version() {
  local package="$1"
  "$VENV_PYTHON" -c \
    'import importlib.metadata, sys; print(importlib.metadata.version(sys.argv[1]))' \
    "$package"
}

binary_cli_version() {
  local binary="$1"
  shift
  local output version first_word
  output="$("$binary" "$@" 2>&1)" || return 1

  # Only a standalone semantic version is authoritative CLI evidence. Tools such
  # as gitleaks print a non-version sentence when the release variable is absent,
  # in which case the exact Go main-module metadata below is required.
  version="$(
    printf '%s\n' "$output" | awk '
      $1 ~ /^v?[0-9]+\.[0-9]+\.[0-9]+$/ {
        sub(/^v/, "", $1)
        print $1
        exit
      }
    '
  )"
  if [[ -n "$version" ]]; then
    printf '%s\n' "$version"
    return 0
  fi

  first_word="$(printf '%s\n' "$output" | awk 'NR == 1 { print $1; exit }')"
  case "$first_word" in
    dev|devel|unknown|"(devel)")
      printf '%s\n' "$first_word"
      ;;
    *)
      printf 'not-reported\n'
      ;;
  esac
}

go_build_module_info() {
  local binary="$1"
  command -v go >/dev/null 2>&1 || return 1
  go version -m "$binary" 2>/dev/null | \
    awk '$1 == "mod" { print $2 "|" $3; exit }'
}

require_exact_version() {
  local tool_name="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$actual" != "$expected" ]]; then
    fail "${tool_name} 版本漂移：需要 ${expected}，发现 ${actual:-unknown}。请显式运行 ./scripts/verify-dev.sh --bootstrap。"
  fi
}

require_go_tool_version() {
  local tool_name="$1"
  local expected="$2"
  local expected_module="$3"
  local binary="$4"
  local actual="$5"
  local metadata metadata_module metadata_version_value

  actual="${actual#v}"
  if [[ "$actual" == "$expected" ]]; then
    return 0
  fi

  case "$actual" in
    dev|devel|unknown|"(devel)"|not-reported|"")
      ;;
    *)
      fail "${tool_name} 版本漂移：需要 ${expected}，CLI 报告 ${actual}。请显式运行 ./scripts/verify-dev.sh --bootstrap。"
      ;;
  esac

  metadata="$(go_build_module_info "$binary" || true)"
  metadata_module="${metadata%%|*}"
  metadata_version_value="${metadata#*|}"
  if [[ -z "$metadata" || "$metadata_module" != "$expected_module" || \
        "$metadata_version_value" != "v${expected}" ]]; then
    fail "${tool_name} CLI 未报告 release 版本，且 Go build metadata 不匹配：需要 ${expected_module} v${expected}，发现 ${metadata:-unavailable}。请显式运行 ./scripts/verify-dev.sh --bootstrap。"
  fi
  printf '%s：CLI 为 %s，已通过 Go build metadata 确认 %s %s\n' \
    "$tool_name" "$actual" "$metadata_module" "$metadata_version_value"
}

check_common_environment() {
  local version isolation
  if [[ ! -x "$VENV_PYTHON" ]]; then
    fail "隔离环境不存在：${VENV_DIR}。请显式运行 ./scripts/verify-dev.sh --bootstrap --python /path/to/python。"
  fi
  version="$(python_version "$VENV_PYTHON" || true)"
  [[ -n "$version" ]] || fail "隔离环境 Python 不受支持，仅支持 3.12-3.14。请显式重新运行 --bootstrap。"
  isolation="$("$VENV_PYTHON" -c 'import sys; print(int(sys.prefix != sys.base_prefix))')"
  [[ "$isolation" == "1" ]] || fail "隔离环境中的 Python 不是 venv：${VENV_PYTHON}"

  if [[ ! -d "$COLLECTIONS_DIR/ansible_collections" ]]; then
    fail "缺少隔离 collections：${COLLECTIONS_DIR}。请显式运行 ./scripts/verify-dev.sh --bootstrap。"
  fi
  "$VENV_PYTHON" "${ROOT_DIR}/scripts/verify-collection-lock.py" \
    --lock "${ROOT_DIR}/ansible/collections.lock.json" \
    --requirements "${ROOT_DIR}/ansible/requirements.yml" \
    --installed "$COLLECTIONS_DIR"

  export PATH="${VENV_BIN}:${GO_BIN}:${PATH}"
  export VIRTUAL_ENV="$VENV_DIR"
  export ANSIBLE_COLLECTIONS_PATH="$COLLECTIONS_DIR"

  for tool in ansible-playbook ansible-galaxy; do
    [[ -x "$VENV_BIN/$tool" ]] || fail "缺少工具 ${VENV_BIN}/${tool}。请显式运行 --bootstrap。"
  done
  require_exact_version "ansible-core" "$ANSIBLE_CORE_VERSION" "$(metadata_version ansible-core)"
}

check_go_tool_versions() {
  local actionlint_actual gitleaks_actual
  [[ -x "$ACTIONLINT_BIN" ]] || fail "缺少工具 ${ACTIONLINT_BIN}。请显式运行 --bootstrap。"
  [[ -x "$GITLEAKS_BIN" ]] || fail "缺少工具 ${GITLEAKS_BIN}。请显式运行 --bootstrap。"
  actionlint_actual="$(binary_cli_version "$ACTIONLINT_BIN" --version)" || \
    fail "actionlint CLI 版本查询失败：${ACTIONLINT_BIN}"
  gitleaks_actual="$(binary_cli_version "$GITLEAKS_BIN" version)" || \
    fail "gitleaks CLI 版本查询失败：${GITLEAKS_BIN}"
  require_go_tool_version \
    "actionlint" "$ACTIONLINT_VERSION" \
    "github.com/rhysd/actionlint" "$ACTIONLINT_BIN" "$actionlint_actual"
  require_go_tool_version \
    "gitleaks" "$GITLEAKS_VERSION" \
    "github.com/zricethezav/gitleaks/v8" "$GITLEAKS_BIN" "$gitleaks_actual"
}

check_quality_environment() {
  check_common_environment
  for tool in ansible-lint yamllint ruff shellcheck; do
    [[ -x "$VENV_BIN/$tool" ]] || fail "缺少工具 ${VENV_BIN}/${tool}。请显式运行 --bootstrap。"
  done
  [[ -x "$ACTIONLINT_BIN" ]] || fail "缺少工具 ${ACTIONLINT_BIN}。请显式运行 --bootstrap。"
  [[ -x "$GITLEAKS_BIN" ]] || fail "缺少工具 ${GITLEAKS_BIN}。请显式运行 --bootstrap。"

  require_exact_version "ansible-lint" "$ANSIBLE_LINT_VERSION" "$(metadata_version ansible-lint)"
  require_exact_version "yamllint" "$YAMLLINT_VERSION" "$(metadata_version yamllint)"
  require_exact_version "ruff" "$RUFF_VERSION" "$(metadata_version ruff)"
  require_exact_version "shellcheck-py" "$SHELLCHECK_PY_VERSION" "$(metadata_version shellcheck-py)"

  local shellcheck_actual
  shellcheck_actual="$("$VENV_BIN/shellcheck" --version | awk '/^version:/ { print $2; exit }')"
  require_exact_version "shellcheck" "$SHELLCHECK_VERSION" "$shellcheck_actual"
  check_go_tool_versions
}

discover_sources() {
  local file path first_line
  SHELL_FILES=()
  PYTHON_FILES=()
  YAML_FILES=()
  SOURCE_FILES=()

  while IFS= read -r -d '' file; do
    case "$file" in
      archive/*|.verify-dev/*|.review/*|.venv/*|collections/*)
        continue
        ;;
    esac
    path="${ROOT_DIR}/${file}"
    [[ -f "$path" ]] || continue
    if [[ "$path" == "${STATE_DIR}/"* ]]; then
      continue
    fi
    SOURCE_FILES+=("$path")
    first_line=""
    IFS= read -r first_line <"$path" || true

    case "$file" in
      *.sh)
        SHELL_FILES+=("$path")
        ;;
      *)
        case "$first_line" in
          '#!/bin/bash'|'#!/bin/sh'|'#!/usr/bin/bash'|'#!/usr/bin/sh'|'#!/usr/bin/env bash'|'#!/usr/bin/env sh'|'#!/usr/bin/env bash '*|'#!/usr/bin/env sh '*)
            SHELL_FILES+=("$path")
            ;;
        esac
        ;;
    esac

    case "$file" in
      *.py)
        PYTHON_FILES+=("$path")
        ;;
      *)
        case "$first_line" in
          '#!/usr/bin/env python'|'#!/usr/bin/env python3'|'#!/usr/bin/python'|'#!/usr/bin/python3'|'#!/usr/bin/env python '*|'#!/usr/bin/env python3 '*)
            PYTHON_FILES+=("$path")
            ;;
        esac
        ;;
    esac

    case "$file" in
      *.yml|*.yaml)
        YAML_FILES+=("$path")
        ;;
    esac
  done < <(git ls-files -z -c -o --exclude-standard -- .)

  (( ${#SHELL_FILES[@]} > 0 )) || fail "未发现可验证的 shell 文件。"
  (( ${#PYTHON_FILES[@]} > 0 )) || fail "未发现可验证的 Python 文件。"
  (( ${#YAML_FILES[@]} > 0 )) || fail "未发现可验证的 YAML 文件。"
}

SOURCE_SCAN_DIR=""
cleanup_source_scan() {
  if [[ -n "$SOURCE_SCAN_DIR" ]]; then
    rm -rf -- "$SOURCE_SCAN_DIR"
    SOURCE_SCAN_DIR=""
  fi
}
trap cleanup_source_scan EXIT

scan_gitleaks_candidate_sources() {
  local path relative destination
  SOURCE_SCAN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/devopstoolkit-source-scan.XXXXXX")"
  for path in "${SOURCE_FILES[@]}"; do
    relative="${path#"${ROOT_DIR}/"}"
    destination="${SOURCE_SCAN_DIR}/${relative}"
    mkdir -p "$(dirname "$destination")"
    cp "$path" "$destination"
  done
  "$GITLEAKS_BIN" detect \
    --no-git \
    --source "$SOURCE_SCAN_DIR" \
    --redact \
    --no-banner
}

run_quality_checks() {
  discover_sources
  printf 'ShellCheck：%d 个 shell 文件\n' "${#SHELL_FILES[@]}"
  "$VENV_BIN/shellcheck" "${SHELL_FILES[@]}"

  printf 'ansible-lint：ansible/\n'
  "$VENV_BIN/ansible-lint" --offline ansible

  printf 'yamllint：%d 个 YAML 文件\n' "${#YAML_FILES[@]}"
  "$VENV_BIN/yamllint" "${YAML_FILES[@]}"

  printf 'ruff：%d 个 Python 文件\n' "${#PYTHON_FILES[@]}"
  "$VENV_BIN/ruff" check "${PYTHON_FILES[@]}"

  printf 'actionlint：.github/workflows/\n'
  "$ACTIONLINT_BIN"

  printf 'gitleaks：Git 历史扫描\n'
  "$GITLEAKS_BIN" detect --source "$ROOT_DIR" --redact --no-banner
  printf 'gitleaks：dirty/untracked 源候选扫描（%d 个文件）\n' "${#SOURCE_FILES[@]}"
  scan_gitleaks_candidate_sources
}

run_ansible_checks() {
  printf 'Ansible 静态验证：tests/verify-ansible.sh\n'
  "${ROOT_DIR}/tests/verify-ansible.sh"
}

if [[ "$bootstrap" == true ]]; then
  bootstrap_environment
  exit 0
fi

if [[ "$ansible_only" != true ]]; then
  check_quality_environment
  run_quality_checks
else
  check_common_environment
fi
run_ansible_checks
printf '开发验证通过。\n'
