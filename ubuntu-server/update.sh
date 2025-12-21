#!/usr/bin/env bash
# Ubuntu Server Update Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔄 Updating Ubuntu Server Configuration..."
echo

if [ ! -f "$SCRIPT_DIR/host.ini" ]; then
  echo "❌ Error: host.ini not found"
  exit 1
fi

# Re-run Ansible playbook
echo "⚙️  Re-running Ansible configuration..."
ansible-playbook -i host.ini ansible/playbook.yml

echo
echo "✅ Update complete!"
