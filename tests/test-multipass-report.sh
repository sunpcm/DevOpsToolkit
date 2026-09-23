#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

# shellcheck source=tests/multipass-smoke.sh
source "${ROOT_DIR}/tests/multipass-smoke.sh"

SOURCE_SHA="0123456789abcdef0123456789abcdef01234567"
SOURCE_DIRTY=false
ANSIBLE_CORE_VERSION=2.21.4
TEST_FAULTS=1
ACTIVE_INSTANCES=(devops-toolkit-2204-test-20260922010101-123)
CREATED_INSTANCES=("${ACTIVE_INSTANCES[@]}")
REPORT_FILE="${TMP_DIR}/success-report.txt"
WORK_DIR="${TMP_DIR}/success-work"
SSH_CONTROL_DIR="${TMP_DIR}/success-control"
mkdir -p "${WORK_DIR}" "${SSH_CONTROL_DIR}"

instance_exists() { return 0; }
multipass() {
  printf '%s\n' "$*" >>"${TMP_DIR}/multipass.log"
  return 0
}

if ! (report_exit 0); then
  echo "错误：成功退出被错误标记为失败。" >&2
  exit 1
fi
grep -Fxq 'result=passed' "${REPORT_FILE}"
grep -Fxq 'source_dirty=false' "${REPORT_FILE}"
grep -Fxq 'test_faults=1' "${REPORT_FILE}"
grep -Fxq 'cleanup_status=passed' "${REPORT_FILE}"
[[ ! -e "${WORK_DIR}" && ! -e "${SSH_CONTROL_DIR}" ]]
grep -Fq 'delete --purge devops-toolkit-2204-test-20260922010101-123' \
  "${TMP_DIR}/multipass.log"

REPORT_FILE="${TMP_DIR}/failure-report.txt"
WORK_DIR="${TMP_DIR}/failure-work"
SSH_CONTROL_DIR="${TMP_DIR}/failure-control"
mkdir -p "${WORK_DIR}" "${SSH_CONTROL_DIR}"
set +e
(report_exit 7)
failure_status=$?
set -e
[[ "${failure_status}" == 7 ]]
grep -Fxq 'result=failed' "${REPORT_FILE}"
grep -Fxq 'cleanup_status=passed' "${REPORT_FILE}"
[[ ! -e "${WORK_DIR}" && ! -e "${SSH_CONTROL_DIR}" ]]

CREATED_INSTANCES=(production-server)
if cleanup_created_instances >/dev/null 2>&1; then
  echo "错误：自动清理接受了非临时实例名。" >&2
  exit 1
fi

echo "Multipass 报告与清理边界测试通过。"
