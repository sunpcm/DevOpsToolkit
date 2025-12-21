#!/usr/bin/env bash
set -e

echo "🔍 Checking dev environment consistency"

# core tools
command -v brew
command -v uv
command -v go
command -v node
command -v npm

# versions (basic sanity)
git --version
uv --version
go version
node --version

# nvm check
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
nvm current

# docker principle check (no daemon in WSL)
if command -v dockerd >/dev/null 2>&1; then
  echo "❌ dockerd should NOT be installed in WSL"
  exit 1
fi

echo "✅ Environment looks good"