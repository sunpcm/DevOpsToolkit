#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../acme-init.sh"

# Mock fail function to prevent process termination if fail is ever invoked
fail() {
  return 1
}

failures=0

test_valid_email() {
  local email="$1"
  if validate_email "${email}"; then
    printf '[PASS] valid email accepted: %s\n' "${email}"
  else
    printf '[FAIL] valid email rejected: %s\n' "${email}" >&2
    failures=$((failures + 1))
  fi
}

test_invalid_email() {
  local email="$1"
  if ! validate_email "${email}"; then
    printf '[PASS] invalid email rejected: %s\n' "${email}"
  else
    printf '[FAIL] invalid email accepted: %s\n' "${email}" >&2
    failures=$((failures + 1))
  fi
}

valid_emails=(
  "user@example.com"
  "admin@sub.domain.org"
  "user.name@example.com"
  "user+tag@domain.co.uk"
  "user_123%test@domain.com"
  "123456@numeric.com"
  "a.b.c@d.e.com"
)

invalid_emails=(
  ""
  "invalid"
  "user@"
  "@domain.com"
  "user@.domain.com"
  ".user@domain.com"
  "user..name@domain.com"
  "user@domain..com"
  "user@domain"
  "user@domain.c"
  "user@domain.123"
  "user name@domain.com"
  "user@domain.com."
  "user@domain.com\n"
)

printf '== 运行 validate_email 单元测试 ==\n'

for email in "${valid_emails[@]}"; do
  test_valid_email "${email}"
done

for email in "${invalid_emails[@]}"; do
  test_invalid_email "${email}"
done

if ((failures == 0)); then
  printf 'validate_email 单元测试全部通过。\n'
  exit 0
else
  printf 'validate_email 单元测试失败：%d 个错误。\n' "${failures}" >&2
  exit 1
fi
