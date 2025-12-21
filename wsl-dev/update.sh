#!/usr/bin/env bash
# WSL Dev Environment Update Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔄 Updating WSL Dev Environment..."
echo

# Update system packages
echo "📦 Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Update Homebrew and packages
if command -v brew >/dev/null 2>&1; then
  echo "🍺 Updating Homebrew..."
  brew update
  brew upgrade
  brew cleanup
else
  echo "⚠️  Homebrew not found, skipping..."
fi

# Update Oh My Zsh
if [ -d "$HOME/.oh-my-zsh" ]; then
  echo "💤 Updating Oh My Zsh..."
  cd "$HOME/.oh-my-zsh" && git pull
  cd "$SCRIPT_DIR"
else
  echo "⚠️  Oh My Zsh not found, skipping..."
fi

# Update zsh plugins
if [ -d "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ]; then
  echo "🔌 Updating zsh-autosuggestions..."
  cd "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" && git pull
  cd "$SCRIPT_DIR"
fi

if [ -d "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ]; then
  echo "🔌 Updating zsh-syntax-highlighting..."
  cd "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" && git pull
  cd "$SCRIPT_DIR"
fi

# Update nvm
if [ -d "$HOME/.nvm" ]; then
  echo "📦 Updating nvm..."
  cd "$HOME/.nvm" && git fetch --tags && git checkout $(git describe --tags $(git rev-list --tags --max-count=1))
  cd "$SCRIPT_DIR"
else
  echo "⚠️  nvm not found, skipping..."
fi

# Update goenv
if [ -d "$HOME/.goenv" ]; then
  echo "📦 Updating goenv..."
  cd "$HOME/.goenv" && git pull
  cd "$SCRIPT_DIR"
else
  echo "⚠️  goenv not found, skipping..."
fi

# Re-run Ansible playbook
if [ -f "$SCRIPT_DIR/ansible/playbook.yml" ]; then
  echo "⚙️  Re-running Ansible configuration..."
  ansible-playbook "$SCRIPT_DIR/ansible/playbook.yml"
else
  echo "⚠️  Ansible playbook not found, skipping..."
fi

echo
echo "✅ Update complete!"
echo "💡 Run 'source ~/.zshrc' to reload your shell configuration"
