#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--" ]]; then
  shift
fi

if [[ "$#" -eq 0 ]]; then
  cat >&2 <<'EOF'
用法：
  ./tests/verify-idempotence.sh -- <bootstrap 命令及参数>

示例：
  ./tests/verify-idempotence.sh -- \
    ./bin/user-only ansible/inventories/user-only.ini --private-key ~/.ssh/id_ed25519

脚本会真实执行两次配置。请只对测试机或已确认可重复执行的目标使用。
EOF
  exit 2
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

echo "第一次执行：建立期望状态"
"$@" | tee "${TMP_DIR}/first-run.log"

echo "第二次执行：验证幂等性"
"$@" | tee "${TMP_DIR}/second-run.log"

recap="$(grep -E 'changed=[0-9]+.*unreachable=[0-9]+.*failed=[0-9]+' \
  "${TMP_DIR}/second-run.log" | tail -n 1 || true)"

if [[ -z "${recap}" ]]; then
  echo "错误：无法从第二次执行输出中识别 Ansible PLAY RECAP。" >&2
  exit 1
fi

if grep -Eq 'changed=[1-9][0-9]*|unreachable=[1-9][0-9]*|failed=[1-9][0-9]*' <<<"${recap}"; then
  echo "错误：第二次执行不是零变更：${recap}" >&2
  exit 1
fi

echo "幂等验证通过：${recap}"
