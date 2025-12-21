#!/usr/bin/env bash
# Ubuntu Server Bootstrap Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Ubuntu Server Configuration Bootstrap"
echo "=========================================="
echo

# Check if host.ini exists
if [ ! -f "$SCRIPT_DIR/host.ini" ]; then
  echo "❌ Error: host.ini not found"
  echo "📝 Please create host.ini from host.ini.example:"
  echo "   cp host.ini.example host.ini"
  echo "   # Then edit host.ini with your server details"
  exit 1
fi

# Check if Ansible is installed
if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "❌ Ansible not found"
  echo "📦 Installing Ansible..."
  sudo apt update
  sudo apt install -y ansible
fi

echo "✅ Prerequisites checked"
echo

# Display configuration summary
echo "📋 Configuration Summary:"
echo "  - Inventory: host.ini"
echo "  - Playbook: ansible/playbook.yml"
echo "  - Config: ansible/group_vars/all.yml"
echo

# Confirm before proceeding
read -p "Continue with server configuration? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
  echo "❌ Configuration cancelled"
  exit 0
fi

# Run Ansible playbook
echo "🔧 Running Ansible playbook..."
echo
ansible-playbook -i host.ini ansible/playbook.yml

echo
echo "✅ Bootstrap complete!"
echo "📖 See README.md for next steps"
