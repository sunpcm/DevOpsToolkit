#!/usr/bin/env bash
set -euo pipefail
export http_proxy=http://192.168.252.1:7897
export https_proxy="$http_proxy"
export NO_PROXY=localhost,127.0.0.1,::1
base="$HOME/.local/share/devops-toolkit"
stage=preflight
status=0
trap 'status=$?; printf "final_stage=%s exit_code=%s\n" "$stage" "$status"' EXIT
run_install() {
  stage="install-$1"
  bash "$HOME/devops-toolkit-install.sh" --user --no-run --version "$1"
  printf 'stage=%s exit_code=0\n' "$stage"
  "$HOME/.local/bin/devops-toolkit" --version
}
id
python3 --version
sha256sum "$HOME/devops-toolkit-install.sh"
run_install v0.1.9
run_install v0.1.10
run_install v0.1.10
stage=current-wrapper
"$base/current/bin/ansible-playbook" --version
"$base/current/bin/user-only" localhost, --syntax-check -c local
"$HOME/.local/bin/devops-toolkit" doctor --json
stage=rollback
test -d "$base/releases/v0.1.9"
test -d "$base/releases/v0.1.10"
ln -s releases/v0.1.9 "$base/current.rollback-test"
mv -Tf "$base/current.rollback-test" "$base/current"
"$HOME/.local/bin/devops-toolkit" --version
test "$(readlink "$base/current")" = releases/v0.1.9
printf 'stage=rollback exit_code=0\n'
run_install v0.1.10
test "$(readlink "$base/current")" = releases/v0.1.10
stage=runtime-negative
marker="$base/runtime/ansible-core-2.21.4/.ready"
mv "$marker" "$marker.acceptance-backup"
restore_marker() { mv "$marker.acceptance-backup" "$marker"; }
trap 'status=$?; restore_marker; printf "final_stage=%s exit_code=%s\n" "$stage" "$status"' EXIT
set +e
"$base/current/bin/ansible-playbook" --version
negative_status=$?
set -e
test "$negative_status" -ne 0
printf 'stage=runtime-negative expected_failure_exit=%s\n' "$negative_status"
restore_marker
trap 'status=$?; printf "final_stage=%s exit_code=%s\n" "$stage" "$status"' EXIT
"$base/current/bin/ansible-playbook" --version
stage=complete
printf 'acceptance=passed\n'
