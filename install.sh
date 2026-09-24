#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY="sunpcm/DevOpsToolkit"
readonly ARCHIVE_NAME="devops-toolkit.tar.gz"
readonly CHECKSUM_NAME="${ARCHIVE_NAME}.sha256"
readonly BUNDLE_NAME="${ARCHIVE_NAME}.sigstore.json"
readonly COSIGN_VERSION="v3.1.1"
readonly ANSIBLE_CORE_VERSION="2.21.4"
readonly ANSIBLE_CORE_PIP_SPEC="ansible-core==${ANSIBLE_CORE_VERSION}"
readonly MAX_DOWNLOAD_BYTES=$((512 * 1024 * 1024))
readonly MAX_EXTRACT_BYTES=$((1024 * 1024 * 1024))
readonly MAX_ARCHIVE_MEMBERS=20000

INSTALL_MODE=""
REQUESTED_VERSION="${DEVOPS_TOOLKIT_VERSION:-}"
RUN_AFTER_INSTALL=true
TEMP_DIR=""

usage() {
  cat <<'EOF'
DevOpsToolkit installer

Usage:
  install.sh [--version v0.1.0] [--no-run] [--user|--system]

Options:
  --version VERSION  Install a specific GitHub Release tag.
  --no-run           Install only; do not launch the interactive wizard.
  --user             Install below ~/.local without privilege escalation.
  --system           Install below /opt and /usr/local/bin; requires root.
  --capabilities-json  Print machine-readable installer capabilities; no changes.
  -h, --help         Show this help.

Environment:
  DEVOPS_TOOLKIT_VERSION        Alternative to --version.
  DEVOPS_TOOLKIT_DOWNLOAD_BASE  Override the release asset directory (testing/mirror).
  DEVOPS_TOOLKIT_COSIGN_BASE    Override the pinned Cosign asset directory (mirror).
EOF
}

fail() {
  printf '错误：%s\n' "$*" >&2
  exit 1
}

info() {
  printf '==> %s\n' "$*"
}

effective_uid() {
  id -u
}

cleanup() {
  if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
    rm -rf "${TEMP_DIR}"
  fi
}

parse_args() {
  if [[ "${1:-}" == "--capabilities-json" && $# -eq 1 ]]; then
    printf '{"schema":1,"component":"installer","version":null,"ansible_core":"%s","installation_modes":["user","system"],"controller":{"macos":{"architectures":["arm64","x86_64"],"python":"3.12-3.14"},"ubuntu":{"versions":["24.04"],"architectures":["aarch64","x86_64"],"python":"3.12-3.14"}},"verification":["sha256","sigstore-identity"]}\n' "${ANSIBLE_CORE_VERSION}"
    exit 0
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        [[ $# -ge 2 ]] || fail "--version 需要版本号。"
        REQUESTED_VERSION="$2"
        shift 2
        ;;
      --no-run)
        RUN_AFTER_INSTALL=false
        shift
        ;;
      --user|--system)
        local requested_mode="${1#--}"
        if [[ -n "${INSTALL_MODE}" && "${INSTALL_MODE}" != "${requested_mode}" ]]; then
          fail "--user 与 --system 不能同时使用。"
        fi
        INSTALL_MODE="${requested_mode}"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --capabilities-json)
        fail "--capabilities-json 不能与安装参数组合。"
        ;;
      *)
        fail "未知参数：$1"
        ;;
    esac
  done

  if [[ -n "${REQUESTED_VERSION}" && ! "${REQUESTED_VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([._-][A-Za-z0-9.-]+)?$ ]]; then
    fail "版本格式无效：${REQUESTED_VERSION}，应类似 v0.1.0。"
  fi

  if [[ -z "${INSTALL_MODE}" ]]; then
    if [[ "$(effective_uid)" -eq 0 ]]; then
      INSTALL_MODE="system"
    else
      INSTALL_MODE="user"
    fi
  fi
  if [[ "${INSTALL_MODE}" == "system" && "$(effective_uid)" -ne 0 ]]; then
    fail "--system 需要 root；请使用 sudo 或改用 --user。"
  fi
}

missing_core_commands() {
  local command_name
  for command_name in curl tar python3 git openssl; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
      printf '%s\n' "${command_name}"
    fi
  done
  if command -v python3 >/dev/null 2>&1 && \
     ! python3 -c 'import ensurepip' >/dev/null 2>&1; then
    printf '%s\n' python3-venv
  fi
}

run_apt_get() {
  apt-get "$@"
}

apt_get_available() {
  command -v apt-get >/dev/null 2>&1
}

check_controller_python() {
  command -v python3 >/dev/null 2>&1 || fail "缺少 Python 3.12–3.14 控制端运行时。"
  python3 -c 'import sys; sys.exit(0 if (3, 12) <= sys.version_info[:2] <= (3, 14) else 1)' || \
    fail "控制端需要 Python 3.12–3.14；Ubuntu 22.04/Python 3.10 仅支持作为远程受管目标。"
}

read_controller_os_release() {
  local key value os_id="" os_version=""
  [[ -r /etc/os-release ]] || fail "Linux 控制端缺少 /etc/os-release，拒绝安装。"
  while IFS='=' read -r key value; do
    value="${value#\"}"
    value="${value%\"}"
    case "${key}" in
      ID) os_id="${value}" ;;
      VERSION_ID) os_version="${value}" ;;
    esac
  done </etc/os-release
  printf '%s %s\n' "${os_id}" "${os_version}"
}

controller_kernel_release() {
  [[ -r /proc/sys/kernel/osrelease ]] || fail "无法确认 Linux 内核版本，拒绝安装。"
  cat /proc/sys/kernel/osrelease
}

check_controller_platform() {
  local operating_system architecture os_id os_version kernel_release
  operating_system="$(uname -s)"
  architecture="$(uname -m)"
  case "${operating_system}" in
    Darwin)
      [[ "${architecture}" == x86_64 || "${architecture}" == arm64 ]] || \
        fail "macOS 控制端只支持 x86_64 或 arm64。"
      ;;
    Linux)
      read -r os_id os_version < <(read_controller_os_release)
      [[ "${os_id}" == ubuntu && "${os_version}" == 24.04 ]] || \
        fail "Linux 控制端只支持 Ubuntu 24.04；Ubuntu 22.04 仅支持作为远程受管目标。"
      [[ "${architecture}" == x86_64 || "${architecture}" == aarch64 ]] || \
        fail "Ubuntu 控制端只支持 x86_64 或 aarch64。"
      kernel_release="$(controller_kernel_release)"
      if [[ "$(printf '%s' "${kernel_release}" | tr '[:upper:]' '[:lower:]')" == *microsoft* ]]; then
        [[ "$(printf '%s' "${kernel_release}" | tr '[:upper:]' '[:lower:]')" == *microsoft*wsl2* ]] || \
          fail "检测到 WSL1 或无法验证的 WSL 内核；只支持 WSL2。"
      fi
      ;;
    *) fail "不支持的控制端系统：${operating_system}。" ;;
  esac
}

managed_runtime_dir() {
  printf '%s/runtime/ansible-core-%s\n' "$(toolkit_base_dir)" "${ANSIBLE_CORE_VERSION}"
}

managed_ansible_command() {
  printf '%s/bin/%s\n' "$(managed_runtime_dir)" "$1"
}

validate_system_install_paths() {
  [[ "${INSTALL_MODE}" == "system" ]] || return 0
  python3 - "$(toolkit_base_dir)" <<'PY'
import stat
import sys
from pathlib import Path

base = Path(sys.argv[1])
if not base.is_absolute() or ".." in base.parts:
    raise SystemExit("system install base must be an absolute path without '..'")


def trusted(path: Path, *, allow_link: bool = False) -> None:
    entry = path.lstat()
    if entry.st_uid != 0 or entry.st_mode & 0o022:
        raise SystemExit(f"untrusted system install path: {path}")
    if stat.S_ISLNK(entry.st_mode):
        if not allow_link:
            raise SystemExit(f"symlink in system install path: {path}")
        target = path.resolve(strict=True)
        # An external venv interpreter may be linked, but must itself be in a
        # root-owned, non-writable path. External directory links are refused.
        if target.is_dir() and not target.is_relative_to(base / "runtime"):
            raise SystemExit(f"external directory link in runtime: {path}")
        for parent in reversed(target.parents):
            trusted(parent)
        trusted(target)
    elif not (stat.S_ISDIR(entry.st_mode) or stat.S_ISREG(entry.st_mode)):
        raise SystemExit(f"unsupported system install entry: {path}")


current = Path("/")
trusted(current)
for part in base.parts[1:]:
    current /= part
    if not current.exists() and not current.is_symlink():
        break
    trusted(current)

for tree in (base / "runtime", base / "tools"):
    if not tree.exists() and not tree.is_symlink():
        continue
    trusted(tree)
    if not tree.is_dir():
        raise SystemExit(f"system install path is not a directory: {tree}")
    for entry in tree.rglob("*"):
        trusted(entry, allow_link=tree.name == "runtime")
PY
}

managed_runtime_valid() {
  local runtime_dir version
  runtime_dir="$(managed_runtime_dir)"
  [[ -f "${runtime_dir}/.ready" && -x "${runtime_dir}/bin/ansible-playbook" && \
     -x "${runtime_dir}/bin/ansible-galaxy" ]] || return 1
  [[ "$(cat "${runtime_dir}/.ready")" == "${ANSIBLE_CORE_VERSION}" ]] || return 1
  version="$(ANSIBLE_LOCAL_TEMP="${TEMP_DIR:-${TMPDIR:-/tmp}}" \
    "${runtime_dir}/bin/ansible-playbook" --version 2>/dev/null | \
    sed -nE '1s/.*\[core ([0-9]+\.[0-9]+\.[0-9]+)\].*/\1/p')"
  [[ "${version}" == "${ANSIBLE_CORE_VERSION}" ]]
}

ensure_managed_runtime() {
  local runtime_dir
  check_controller_python
  validate_system_install_paths || fail "系统安装路径或已有 runtime 权限不安全。"
  runtime_dir="$(managed_runtime_dir)"
  if managed_runtime_valid; then
    info "复用隔离的 ${ANSIBLE_CORE_PIP_SPEC} runtime"
    return 0
  fi
  [[ ! -e "${runtime_dir}" && ! -L "${runtime_dir}" ]] || \
    fail "隔离 runtime ${runtime_dir} 不完整或版本不符；请先人工检查，安装器不会覆盖。"
  mkdir -p "$(dirname "${runtime_dir}")"
  chmod 0755 "$(dirname "${runtime_dir}")"
  python3 -m venv "${runtime_dir}" || fail "创建隔离 runtime 失败；请安装 python3-venv。"
  "${runtime_dir}/bin/python" -m pip install "${ANSIBLE_CORE_PIP_SPEC}" || \
    fail "隔离 runtime 安装 ${ANSIBLE_CORE_PIP_SPEC} 失败；current 未切换。"
  printf '%s\n' "${ANSIBLE_CORE_VERSION}" >"${runtime_dir}/.ready"
  validate_system_install_paths || fail "新建 runtime 权限不安全；current 未切换。"
  managed_runtime_valid || fail "隔离 runtime 自检失败；current 未切换。"
  chmod -R a+rX "${runtime_dir}"
  info "隔离 runtime 已就绪：${runtime_dir}"
}

install_system_dependencies() {
  apt_get_available || \
    fail "系统模式只能在支持 apt-get 的 Ubuntu/WSL 自动安装依赖。"
  info "安装系统依赖"
  run_apt_get update
  DEBIAN_FRONTEND=noninteractive run_apt_get install -y \
    python3 python3-venv git curl ca-certificates openssl sshpass
}

ensure_dependencies() {
  local missing
  missing="$(missing_core_commands)"
  if [[ "${INSTALL_MODE}" == "system" && -n "${missing}" ]]; then
    install_system_dependencies
    missing="$(missing_core_commands)"
  fi
  if [[ -n "${missing}" ]]; then
    printf '缺少命令：\n%s\n' "${missing}" >&2
    if [[ "${INSTALL_MODE}" == "user" ]]; then
      printf '普通用户安装不会提权。请让管理员安装 Python 3.12–3.14（含 venv）、git、curl 和 openssl。\n' >&2
    fi
    exit 1
  fi
  if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    fail "找不到 sha256sum 或 shasum。"
  fi
}

download_base_url() {
  if [[ -n "${DEVOPS_TOOLKIT_DOWNLOAD_BASE:-}" ]]; then
    printf '%s\n' "${DEVOPS_TOOLKIT_DOWNLOAD_BASE%/}"
  elif [[ -n "${REQUESTED_VERSION}" ]]; then
    printf 'https://github.com/%s/releases/download/%s\n' "${REPOSITORY}" "${REQUESTED_VERSION}"
  else
    printf 'https://github.com/%s/releases/latest/download\n' "${REPOSITORY}"
  fi
}

# 从 GitHub 拉产物时，中国大陆网络常见 TLS 连接被重置（curl 56 unexpected eof）。
# 对远程 URL 加有限重试 + 退避；--retry-all-errors 让连接类错误也参与重试。
# 本地 file://（测试用例）没有瞬时错误，跳过重试以免拖慢失败路径。
curl_download() {
  local url="$1" output="$2"
  if [[ "${url}" == file://* ]]; then
    curl --fail --silent --show-error --location \
      --max-filesize "${MAX_DOWNLOAD_BYTES}" \
      "${url}" --output "${output}"
  else
    # --speed-limit/--speed-time：传输速率低于 1KB/s 持续 30s 就中止本次尝试，
    # 避免连上后数据流卡死导致无限挂起；配合 --retry 让停滞的尝试自动重来。
    curl --fail --silent --show-error --location \
      --retry 5 --retry-delay 2 --retry-all-errors \
      --max-filesize "${MAX_DOWNLOAD_BYTES}" \
      --connect-timeout 30 --speed-limit 1024 --speed-time 30 \
      "${url}" --output "${output}"
  fi
}

download_assets() {
  local base_url="$1"
  info "下载 DevOpsToolkit Release"
  curl_download "${base_url}/${ARCHIVE_NAME}" "${TEMP_DIR}/${ARCHIVE_NAME}"
  curl_download "${base_url}/${CHECKSUM_NAME}" "${TEMP_DIR}/${CHECKSUM_NAME}"
  curl_download "${base_url}/${BUNDLE_NAME}" "${TEMP_DIR}/${BUNDLE_NAME}"
  chmod 0600 \
    "${TEMP_DIR}/${ARCHIVE_NAME}" \
    "${TEMP_DIR}/${CHECKSUM_NAME}" \
    "${TEMP_DIR}/${BUNDLE_NAME}"
}

calculate_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

toolkit_base_dir() {
  if [[ "${INSTALL_MODE}" == "system" ]]; then
    printf '%s\n' "${DEVOPS_TOOLKIT_INSTALL_BASE:-/opt/devops-toolkit}"
  else
    printf '%s\n' "${DEVOPS_TOOLKIT_INSTALL_BASE:-${HOME}/.local/share/devops-toolkit}"
  fi
}

verify_checksum() {
  local expected actual expected_lower actual_lower
  expected="$(awk 'NR == 1 {print $1}' "${TEMP_DIR}/${CHECKSUM_NAME}")"
  [[ "${expected}" =~ ^[0-9a-fA-F]{64}$ ]] || fail "Release checksum 文件格式无效。"
  actual="$(calculate_sha256 "${TEMP_DIR}/${ARCHIVE_NAME}")"
  expected_lower="$(printf '%s' "${expected}" | tr '[:upper:]' '[:lower:]')"
  actual_lower="$(printf '%s' "${actual}" | tr '[:upper:]' '[:lower:]')"
  [[ "${actual_lower}" == "${expected_lower}" ]] || fail "Release SHA256 校验失败。"
  printf '%s\n' "${actual_lower}" >"${TEMP_DIR}/verified.sha256"
  info "SHA256 校验通过"
}

cosign_asset_name() {
  local operating_system architecture
  operating_system="$(uname -s | tr '[:upper:]' '[:lower:]')"
  architecture="$(uname -m)"
  case "${operating_system}" in
    linux|darwin) ;;
    *) fail "Cosign 暂不支持当前系统：${operating_system}。" ;;
  esac
  case "${architecture}" in
    x86_64|amd64) architecture="amd64" ;;
    arm64|aarch64) architecture="arm64" ;;
    *) fail "Cosign 暂不支持当前架构：${architecture}。" ;;
  esac
  printf 'cosign-%s-%s\n' "${operating_system}" "${architecture}"
}

cosign_expected_sha256() {
  case "$1" in
    cosign-darwin-amd64) printf '%s\n' '14d2678dfbfde18798151e86fbd91ebdadbb7424b18412a42a155dd8a2df4c7a' ;;
    cosign-darwin-arm64) printf '%s\n' '94b42a9e697be95675f6160ab031a9a5f1ec1e646d6f648d7b2f5cd59ececbc5' ;;
    cosign-linux-amd64) printf '%s\n' 'ae1ecd212663f3693ad9edf8b1a183900c9a52d3155ba6e354237f9a0f6463fc' ;;
    cosign-linux-arm64) printf '%s\n' '2ec865872e331c32fd12b08dae15332d3f92c0aa029219589684a4903ca85d11' ;;
    *) fail "没有 $1 的 Cosign 校验值。" ;;
  esac
}

cosign_download_base() {
  # DEVOPS_TOOLKIT_COSIGN_BASE 允许墙内用户把 cosign 二进制指向可达镜像；
  # SHA256 仍会强校验，镜像不影响安全性。基址需包含到版本目录，形如
  # https://<mirror>/https://github.com/sigstore/cosign/releases/download/vX.Y.Z
  if [[ -n "${DEVOPS_TOOLKIT_COSIGN_BASE:-}" ]]; then
    printf '%s\n' "${DEVOPS_TOOLKIT_COSIGN_BASE%/}"
  else
    printf 'https://github.com/sigstore/cosign/releases/download/%s\n' "${COSIGN_VERSION}"
  fi
}

prepare_cosign() {
  local asset_name expected_sha actual_sha download_base cache_dir cached_cosign cache_tmp
  asset_name="$(cosign_asset_name)"
  expected_sha="$(cosign_expected_sha256 "${asset_name}")"
  download_base="$(cosign_download_base)"

  cache_dir="$(toolkit_base_dir)/tools"
  cached_cosign="${cache_dir}/cosign-${COSIGN_VERSION}-${asset_name}"
  if [[ -f "${cached_cosign}" && \
        "$(calculate_sha256 "${cached_cosign}")" == "${expected_sha}" ]]; then
    info "复用已校验的 Cosign ${COSIGN_VERSION}"
    printf '%s\n' "${cached_cosign}"
    return 0
  fi

  info "下载并校验 Cosign ${COSIGN_VERSION}"
  curl_download "${download_base}/${asset_name}" "${TEMP_DIR}/cosign"
  chmod 0700 "${TEMP_DIR}/cosign"
  actual_sha="$(calculate_sha256 "${TEMP_DIR}/cosign")"
  [[ "${actual_sha}" == "${expected_sha}" ]] || fail "Cosign SHA256 校验失败。"
  mkdir -p "${cache_dir}"
  chmod 0755 "$(toolkit_base_dir)" "${cache_dir}"
  cache_tmp="${cache_dir}/.cosign-$$"
  cp "${TEMP_DIR}/cosign" "${cache_tmp}"
  chmod 0755 "${cache_tmp}"
  python3 - "${cache_tmp}" "${cached_cosign}" <<'PY'
import os
import sys

os.replace(sys.argv[1], sys.argv[2])
PY
  printf '%s\n' "${cached_cosign}"
}

verify_sigstore_signature() {
  local release_version="$1" cosign identity workflow_ref
  cosign="$(prepare_cosign | tail -n 1)"
  identity="https://github.com/${REPOSITORY}/.github/workflows/release.yml@refs/tags/${release_version}"
  workflow_ref="refs/tags/${release_version}"
  info "验证 Sigstore 签名与 GitHub Actions 身份"
  "${cosign}" verify-blob \
    --timeout 2m \
    --bundle "${TEMP_DIR}/${BUNDLE_NAME}" \
    --certificate-identity "${identity}" \
    --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
    --certificate-github-workflow-repository "${REPOSITORY}" \
    --certificate-github-workflow-ref "${workflow_ref}" \
    --certificate-github-workflow-trigger push \
    "${TEMP_DIR}/${ARCHIVE_NAME}" >/dev/null || \
      fail "Sigstore 签名验证失败，拒绝安装。"
  info "Sigstore 身份验证通过"
}

read_archive_version() {
  python3 - "${TEMP_DIR}/${ARCHIVE_NAME}" "${MAX_ARCHIVE_MEMBERS}" "${MAX_EXTRACT_BYTES}" <<'PY'
import sys
import tarfile

archive, max_members, max_bytes = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
total = 0
with tarfile.open(archive, "r|gz") as package:
    for count, member in enumerate(package, 1):
        if count > max_members:
            raise SystemExit("release archive has too many entries")
        total += member.size if member.isfile() else 0
        if total > max_bytes:
            raise SystemExit("release archive exceeds uncompressed size limit")
        if member.name != "devops-toolkit/VERSION":
            continue
        if not member.isfile() or not 1 <= member.size <= 64:
            raise SystemExit("invalid release VERSION entry")
        handle = package.extractfile(member)
        if handle is None:
            raise SystemExit("cannot read release VERSION entry")
        print(handle.read(65).decode("ascii").strip())
        break
    else:
        raise SystemExit("release archive is missing VERSION")
PY
}

extract_archive_safely() {
  mkdir -m 0700 "${TEMP_DIR}/extracted"
  python3 - "${TEMP_DIR}/${ARCHIVE_NAME}" "${TEMP_DIR}/extracted" \
    "${MAX_ARCHIVE_MEMBERS}" "${MAX_EXTRACT_BYTES}" <<'PY'
import os
import sys
import tarfile
from pathlib import PurePosixPath

archive, destination = sys.argv[1:3]
max_members, max_bytes = map(int, sys.argv[3:])
with tarfile.open(archive, "r:gz") as package:
    members = package.getmembers()
    if not members or len(members) > max_members:
        raise SystemExit("empty release archive or too many entries")
    seen = set()
    total = 0
    for member in members:
        if member.name in seen:
            raise SystemExit(f"duplicate archive path: {member.name}")
        seen.add(member.name)
        total += member.size if member.isfile() else 0
        if total > max_bytes:
            raise SystemExit("release archive exceeds uncompressed size limit")
        path = PurePosixPath(member.name)
        if path.is_absolute() or ".." in path.parts:
            raise SystemExit(f"unsafe archive path: {member.name}")
        if not path.parts or path.parts[0] != "devops-toolkit":
            raise SystemExit(f"unexpected archive root: {member.name}")
        if not (member.isfile() or member.isdir()):
            raise SystemExit(f"unsupported archive entry: {member.name}")
        # Release archives are built on a CI runner whose numeric UID/GID must
        # never become the owner of a root-installed executable directory.
        member.uid = os.geteuid()
        member.gid = os.getegid()
        member.uname = ""
        member.gname = ""
        member.mode = (member.mode & 0o755) | (0o700 if member.isdir() else 0o600)
    package.extractall(destination)
PY
}

read_release_version() {
  local source_dir="${TEMP_DIR}/extracted/devops-toolkit"
  [[ -f "${source_dir}/VERSION" ]] || fail "Release 缺少 VERSION。"
  [[ -x "${source_dir}/bin/devops-toolkit" ]] || fail "Release 缺少可执行入口。"
  [[ -f "${source_dir}/ansible/requirements.yml" ]] || fail "Release 缺少 Ansible requirements。"
  local release_version
  release_version="$(tr -d '[:space:]' <"${source_dir}/VERSION")"
  [[ "${release_version}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([._-][A-Za-z0-9.-]+)?$ ]] || \
    fail "Release VERSION 格式无效。"
  if [[ -n "${REQUESTED_VERSION}" && "${release_version}" != "${REQUESTED_VERSION}" ]]; then
    fail "请求 ${REQUESTED_VERSION}，但 Release 内容为 ${release_version}。"
  fi
  printf '%s\n' "${release_version}"
}

bundled_collections_valid() {
  local collection_dir="$1"
  local lock_file="$2"
  python3 - "${collection_dir}" "${lock_file}" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
lock_path = Path(sys.argv[2])
marker = root / ".bundled-collections"
try:
    marker_lines = marker.read_text(encoding="utf-8").splitlines()
    if marker_lines and marker_lines[0].startswith("lock-sha256="):
        lock_bytes = lock_path.read_bytes()
        lock_digest = hashlib.sha256(lock_bytes).hexdigest()
        if marker_lines[0] != f"lock-sha256={lock_digest}":
            raise ValueError("collection lock digest mismatch")
        lock = json.loads(lock_bytes)["collections"]
        expected = {str(item["name"]): str(item["version"]) for item in lock}
        expected_lines = [f"{name}={version}" for name, version in sorted(expected.items())]
        if marker_lines[1:] != expected_lines:
            raise ValueError("collection marker mismatch")
    else:
        # Historical signed bundles predate collections.lock.json. Preserve
        # compatibility by requiring their marker and manifests to agree exactly.
        expected = dict(line.split("=", 1) for line in marker_lines)
        if not expected:
            raise ValueError("empty historical collection marker")
    actual = {}
    for manifest in root.glob("ansible_collections/*/*/MANIFEST.json"):
        info = json.loads(manifest.read_text(encoding="utf-8"))["collection_info"]
        actual[f"{info['namespace']}.{info['name']}"] = str(info["version"])
except (KeyError, OSError, ValueError, json.JSONDecodeError):
    raise SystemExit(1)
raise SystemExit(0 if actual == expected else 1)
PY
}

allows_legacy_galaxy_fallback() {
  # Only these already-published, signed Releases predate bundled collections.
  # A future tag without a bundle must fail closed, even if its VERSION is valid.
  case "$1" in
    v0.1.2|v0.1.3|v0.1.4|v0.1.5|v0.1.7) return 0 ;;
    *) return 1 ;;
  esac
}

system_release_tree_valid() {
  local release_root="$1"
  python3 - "${release_root}" <<'PY'
import os
import stat
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve(strict=True)
for path in (root, *root.rglob("*")):
    entry = path.lstat()
    if entry.st_uid != 0 or entry.st_gid != 0:
        raise SystemExit(f"non-root owner: {path}")
    if stat.S_ISLNK(entry.st_mode):
        try:
            target = path.resolve(strict=True)
            target.relative_to(root)
        except (OSError, RuntimeError, ValueError):
            raise SystemExit(f"unsafe symlink: {path}") from None
        continue
    if entry.st_mode & 0o022 or not (stat.S_ISDIR(entry.st_mode) or stat.S_ISREG(entry.st_mode)):
        raise SystemExit(f"unsafe mode or file type: {path}")
PY
}

install_release() {
  local release_version="$1" verified_sha source_dir base_dir bin_dir
  source_dir="${TEMP_DIR}/extracted/devops-toolkit"
  verified_sha="$(cat "${TEMP_DIR}/verified.sha256")"
  if [[ "${INSTALL_MODE}" == "system" ]]; then
    base_dir="$(toolkit_base_dir)"
    bin_dir="${DEVOPS_TOOLKIT_BIN_DIR:-/usr/local/bin}"
  else
    base_dir="$(toolkit_base_dir)"
    bin_dir="${DEVOPS_TOOLKIT_BIN_DIR:-${HOME}/.local/bin}"
  fi

  local releases_dir target_dir staging_dir current_link launcher_link
  releases_dir="${base_dir}/releases"
  target_dir="${releases_dir}/${release_version}"
  staging_dir="${releases_dir}/.install-${release_version}-$$"
  current_link="${base_dir}/current"
  launcher_link="${bin_dir}/devops-toolkit"
  if [[ "${INSTALL_MODE}" == "system" ]]; then
    [[ ! -L "${base_dir}" && ! -L "${releases_dir}" ]] || \
      fail "系统安装根目录或 releases 目录不能是符号链接。"
  fi
  mkdir -p "${releases_dir}"
  chmod 0755 "${base_dir}" "${releases_dir}"
  if [[ "${INSTALL_MODE}" == "system" ]]; then
    local unsafe_root
    unsafe_root="$(find "${base_dir}" "${releases_dir}" -maxdepth 0 \
      \( ! -uid 0 -o ! -gid 0 -o -perm -020 -o -perm -002 \) -print -quit)"
    [[ -z "${unsafe_root}" ]] || \
      fail "系统安装目录必须由 root 持有且不可由组/其他用户写入：${unsafe_root}。"
  fi
  if [[ ! -d "${bin_dir}" ]]; then
    mkdir -p "${bin_dir}"
    chmod 0755 "${bin_dir}"
  fi

  if [[ -e "${current_link}" && ! -L "${current_link}" ]]; then
    fail "${current_link} 已存在且不是符号链接，拒绝覆盖。"
  fi
  if [[ -e "${launcher_link}" && ! -L "${launcher_link}" ]]; then
    fail "${launcher_link} 已存在且不是符号链接，拒绝覆盖。"
  fi

  local collection_root
  if [[ -e "${target_dir}" || -L "${target_dir}" ]]; then
    [[ ! -L "${target_dir}" && -d "${target_dir}" ]] || \
      fail "版本目录不能是符号链接或非目录：${target_dir}。"
    [[ -f "${target_dir}/.release-sha256" ]] || \
      fail "版本目录 ${target_dir} 已存在但缺少校验记录，拒绝覆盖。"
    [[ "$(cat "${target_dir}/.release-sha256")" == "${verified_sha}" ]] || \
      fail "版本 ${release_version} 的 Release 内容已变化，拒绝覆盖不可变版本。"
    info "版本 ${release_version} 已安装，复用现有文件"
    collection_root="${target_dir}"
  else
    rm -rf "${staging_dir}"
    mkdir -m 0755 "${staging_dir}"
    cp -a "${source_dir}/." "${staging_dir}/"
    if [[ "${INSTALL_MODE}" == "system" ]]; then
      chown -R 0:0 "${staging_dir}"
    fi
    chmod 0755 "${staging_dir}"
    printf '%s\n' "${verified_sha}" >"${staging_dir}/.release-sha256"
    chmod 0755 "${staging_dir}/bin/devops-toolkit"
    collection_root="${staging_dir}"
  fi

  if [[ "${INSTALL_MODE}" == "system" ]]; then
    if [[ "${collection_root}" != "${staging_dir}" ]] && \
      ! system_release_tree_valid "${collection_root}"; then
      fail "已有系统版本存在不安全所有权、权限或逃逸链接，拒绝复用；请先从可信 Release 重建该版本。"
    fi
  fi

  local bundle_marker="${collection_root}/collections/.bundled-collections"
  if [[ -f "${bundle_marker}" ]]; then
    if ! bundled_collections_valid \
      "${collection_root}/collections" \
      "${collection_root}/ansible/collections.lock.json"; then
      [[ "${collection_root}" != "${staging_dir}" ]] || rm -rf "${staging_dir}"
      fail "Release 内置 Ansible collections 不完整，current 未切换。"
    fi
  elif ! allows_legacy_galaxy_fallback "${release_version}"; then
    [[ "${collection_root}" != "${staging_dir}" ]] || rm -rf "${staging_dir}"
    fail "版本 ${release_version} 缺少内置 Ansible collections 标记，拒绝回退到 Galaxy。"
  fi

  if [[ -f "${collection_root}/.collections-ready" ]]; then
    info "Ansible collections 已就绪，跳过安装"
  elif [[ -f "${bundle_marker}" ]]; then
    info "使用 Release 内置 Ansible collections"
    printf '%s\n' "${verified_sha}" >"${collection_root}/.collections-ready"
  else
    info "旧版 Release 未内置 collections，使用 Ansible Galaxy 兼容安装"
    mkdir -p "${collection_root}/collections"
    if ! ANSIBLE_COLLECTIONS_PATH="${collection_root}/collections" \
      ANSIBLE_COLLECTIONS_PATHS="${collection_root}/collections" \
      "$(managed_ansible_command ansible-galaxy)" collection install \
        --requirements-file "${collection_root}/ansible/requirements.yml" \
        --collections-path "${collection_root}/collections"; then
      [[ "${collection_root}" != "${staging_dir}" ]] || rm -rf "${staging_dir}"
      fail "Ansible collections 安装失败，current 未切换。"
    fi
    printf '%s\n' "${verified_sha}" >"${collection_root}/.collections-ready"
  fi

  find "${collection_root}" -type d -exec chmod a+rx,go-w {} +
  find "${collection_root}" -type f -exec chmod a+r,go-w {} +
  chmod 0600 "${collection_root}/.release-sha256" "${collection_root}/.collections-ready"

  if [[ "${INSTALL_MODE}" == "system" ]]; then
    system_release_tree_valid "${collection_root}" || \
      fail "系统版本权限验证失败，current 未切换。"
  fi

  if [[ "${collection_root}" == "${staging_dir}" ]]; then
    mv "${staging_dir}" "${target_dir}"
  fi

  local current_tmp launcher_tmp
  current_tmp="${base_dir}/.current-$$"
  launcher_tmp="${bin_dir}/.devops-toolkit-$$"
  # macOS applies umask to symlink modes. Keep private download files under the
  # process-wide 077 umask, but make public launcher links traversable by the
  # non-root user that invokes an installation performed through sudo.
  (umask 022; ln -s "releases/${release_version}" "${current_tmp}")
  (umask 022; ln -s "${current_link}/bin/devops-toolkit" "${launcher_tmp}")
  python3 - "${current_tmp}" "${current_link}" "${launcher_tmp}" "${launcher_link}" <<'PY'
import os
import sys

current_tmp, current_link, launcher_tmp, launcher_link = sys.argv[1:]
os.replace(current_tmp, current_link)
os.replace(launcher_tmp, launcher_link)
PY

  printf '%s\n' "${launcher_link}"
}

main() {
  parse_args "$@"
  check_controller_platform || return 1
  check_controller_python
  validate_system_install_paths || fail "系统安装路径或已有 runtime 权限不安全。"
  ensure_dependencies
  umask 077
  TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/devops-toolkit-install.XXXXXX")"
  chmod 0700 "${TEMP_DIR}"
  trap cleanup EXIT INT TERM

  local base_url release_version launcher
  base_url="$(download_base_url)"
  download_assets "${base_url}"
  verify_checksum
  release_version="$(read_archive_version)"
  [[ "${release_version}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([._-][A-Za-z0-9.-]+)?$ ]] || \
    fail "Release VERSION 格式无效。"
  if [[ -n "${REQUESTED_VERSION}" && "${release_version}" != "${REQUESTED_VERSION}" ]]; then
    fail "请求 ${REQUESTED_VERSION}，但 Release 内容为 ${release_version}。"
  fi
  verify_sigstore_signature "${release_version}"
  extract_archive_safely
  [[ "$(read_release_version)" == "${release_version}" ]] || \
    fail "Release 归档中的 VERSION 不一致。"
  ensure_managed_runtime
  launcher="$(install_release "${release_version}" | tail -n 1)"

  info "DevOpsToolkit ${release_version} 已安装：${launcher}"
  if [[ "${INSTALL_MODE}" == "user" && ":${PATH}:" != *":$(dirname "${launcher}"):"* ]]; then
    printf '提示：请将 %s 加入 PATH。\n' "$(dirname "${launcher}")"
  fi
  if [[ "${RUN_AFTER_INSTALL}" == true && -t 0 && -t 1 ]]; then
    exec "${launcher}"
  fi
  if [[ "${RUN_AFTER_INSTALL}" == true ]]; then
    info "当前不是交互终端，已跳过启动向导；稍后运行 devops-toolkit。"
  fi
}

# 通过 `bash -c "$(curl ... install.sh)"` 运行时 BASH_SOURCE 为空，set -u 会因未绑定变量报错。
# 用 ${BASH_SOURCE[0]:-$0} 兜底：直接执行或管道执行都运行 main，仅在被 source 时不运行。
if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
  main "$@"
fi
