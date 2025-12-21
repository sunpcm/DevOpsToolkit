#!/usr/bin/env bash
set -e

./scripts/check-prerequisites.sh

# ===============================
# WSL Environment Sanity Check
# ===============================

# Must be WSL
if ! grep -qi microsoft /proc/version; then
  echo "❌ This script must be run inside WSL"
  exit 1
fi

# Must be WSL2
if ! uname -r | grep -qi "microsoft-standard"; then
  echo "❌ WSL1 detected"
  echo "👉 Please upgrade to WSL2:"
  echo "   https://learn.microsoft.com/windows/wsl/install"
  exit 1
fi

# Must be Ubuntu
if ! grep -qi ubuntu /etc/os-release; then
  echo "❌ Unsupported Linux distribution"
  echo "👉 Only Ubuntu 22.04+ is officially supported"
  exit 1
fi

command -v docker >/dev/null || {
  echo "Docker CLI not found. Install Docker Desktop first."
  exit 1
}

# Ubuntu version >= 22.04
UBUNTU_VERSION=$(lsb_release -rs)
REQUIRED_VERSION="22.04"

if dpkg --compare-versions "$UBUNTU_VERSION" lt "$REQUIRED_VERSION"; then
  echo "❌ Ubuntu $UBUNTU_VERSION detected"
  echo "👉 Please upgrade to Ubuntu $REQUIRED_VERSION or newer"
  exit 1
fi

echo "🚀 WSL Dev Bootstrap"

# ===============================
# Bootstrap
# ===============================

sudo apt update
sudo apt install -y ansible curl git ca-certificates

ansible-playbook ansible/playbook.yml

# ===============================
# Installation Summary
# ===============================

echo ""
echo "🎉 WSL Dev Environment Ready!"
echo ""

echo "Installed:"

if command -v brew >/dev/null 2>&1; then
  echo " ✅ Homebrew"
fi

if command -v uv >/dev/null 2>&1; then
  echo " ✅ Python (uv)"
fi

if [ -s "$HOME/.nvm/nvm.sh" ]; then
  echo " ✅ Node.js (nvm)"
fi

if command -v go >/dev/null 2>&1; then
  echo " ✅ Go"
fi

if command -v docker >/dev/null 2>&1; then
  echo " ✅ Docker CLI (WSL mode)"
fi

echo ""
echo "Next steps:"
echo " 1. Restart your shell:"
echo "    exec zsh"
echo ""

if command -v uv >/dev/null 2>&1; then
  echo " 2. Python (uv):"
  echo "    uv python install 3.12"
  echo "    uv venv"
  echo ""
fi

if [ -s "$HOME/.nvm/nvm.sh" ]; then
  echo " 3. Node.js (nvm):"
  echo "    nvm install --lts"
  echo "    nvm use --lts"
  echo ""
fi

if command -v docker >/dev/null 2>&1; then
  echo " 4. Docker:"
  echo "    Start Docker Desktop on Windows"
  echo ""
fi

echo "Docs:"
echo " 👉 README.md"
echo ""
echo "✅ All done."