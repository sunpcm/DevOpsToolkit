#!/usr/bin/env bash
set -euo pipefail
status=0
trap 'status=$?; printf "offline_exit_code=%s\n" "$status"' EXIT
id
test "$(id -u)" -ne 0
ip -brief address
test -z "$(ip route show)"
if curl --noproxy '*' --connect-timeout 3 --max-time 5 https://github.com/ >/dev/null 2>&1; then
  echo '错误：隔离命名空间仍能访问外网。' >&2
  exit 1
fi
printf 'network_isolation=confirmed\n'
# shellcheck source=/dev/null
source "$HOME/devops-toolkit-install.sh"
parse_args --user --no-run --version v0.1.10
marker="$HOME/.local/share/devops-toolkit/runtime/ansible-core-2.21.4/.ready"
before="$(stat -c '%i:%Y:%s' "$marker")"
ensure_managed_runtime
ensure_managed_runtime
test "$before" = "$(stat -c '%i:%Y:%s' "$marker")"
base="$HOME/.local/share/devops-toolkit"
"$base/current/bin/ansible-playbook" --version
"$base/current/bin/user-only" localhost, --syntax-check -c local
"$HOME/.local/bin/devops-toolkit" --version
printf 'offline_runtime_reuse=passed\n'
