#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The source path is computed so the test works from any cwd.
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../acme-check.sh"

# The product check runs on Ubuntu with GNU stat. Adapt only this test's stat
# calls on macOS so the same permission cases can run in the local gate.
stat() {
  if [[ "$(uname -s)" == Darwin && "$1" == -c ]]; then
    case "$2" in
      '%U:%G') command stat -f '%Su:%Sg' "$3" ;;
      '%a') command stat -f '%Lp' "$3" ;;
      '%h') command stat -f '%l' "$3" ;;
      *) return 2 ;;
    esac
  else
    command stat "$@"
  fi
}

temporary="$(mktemp -d)"
trap 'rm -rf -- "${temporary}"' EXIT
owner="$(id -un):$(id -gn)"
current="${temporary}/issue-example.com.log"
rotated="${temporary}/issue-example.com.log.1.gz"
touch "${current}" "${rotated}"
chmod 0600 "${current}" "${rotated}"

check_client_logs "${temporary}" "${owner}"
((FAILURES == 0))

FAILURES=0
check_client_logs "${temporary}" "__unexpected_owner__:__unexpected_group__"
((FAILURES == 2))

chmod 0644 "${rotated}"
FAILURES=0
check_client_logs "${temporary}" "${owner}"
((FAILURES == 1))
chmod 0600 "${rotated}"

ln -s "${current}" "${temporary}/linked.log"
FAILURES=0
check_client_logs "${temporary}" "${owner}"
((FAILURES == 1))
rm -- "${temporary}/linked.log"

ln "${current}" "${temporary}/hardlinked.log"
FAILURES=0
check_client_logs "${temporary}" "${owner}"
((FAILURES >= 2))

FAILURES=0
check_client_logs "${temporary}/missing" "${owner}"
((FAILURES == 1))

printf 'ACME 当前与轮替日志权限测试通过。\n'
