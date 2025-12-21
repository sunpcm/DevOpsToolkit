#!/usr/bin/env bash
set -e

error() {
  echo "❌ $1"
  exit 1
}

info() {
  echo "✅ $1"
}

warn() {
  echo "⚠️  $1"
}

echo "🔍 Checking prerequisites..."
echo

# 1. Must be running inside WSL
if ! grep -qi microsoft /proc/version; then
  error "Not running inside WSL. Please run this script inside WSL (Ubuntu)."
fi
info "Running inside WSL"

# 2. Check WSL version
if ! grep -qi "WSL2" /proc/version && ! grep -qi "microsoft.*2" /proc/version; then
  warn "May not be WSL2. WSL2 is recommended for best performance."
else
  info "Running inside WSL2"
fi

# 3. Check Ubuntu version
if [ -f /etc/os-release ]; then
  . /etc/os-release
  VERSION_NUM=$(echo "$VERSION_ID" | cut -d. -f1)
  if [ "$VERSION_NUM" -lt 22 ]; then
    error "Ubuntu version $VERSION_ID detected. Ubuntu 22.04 or higher required."
  fi
  info "Ubuntu $VERSION_ID detected"
else
  warn "Cannot detect Ubuntu version"
fi

# 4. Docker CLI must be available
if ! command -v docker >/dev/null 2>&1; then
  error "Docker CLI not found.
Please install Docker Desktop for Windows and enable WSL integration."
fi

# 5. Docker daemon must be reachable (Docker Desktop running)
if ! docker version >/dev/null 2>&1; then
  error "Docker is installed but not running.
Please start Docker Desktop and wait until it is ready."
fi
info "Docker CLI available and running"

# 6. Docker Compose v2 check
if ! docker compose version >/dev/null 2>&1; then
  error "Docker Compose v2 not available.
Please ensure you are using Docker Desktop with Compose v2 enabled."
fi
info "Docker Compose v2 available"

# 7. Check Windows interop
if ! command -v powershell.exe >/dev/null 2>&1; then
  warn "Windows interop not fully enabled. Run:
  echo '[interop]' | sudo tee -a /etc/wsl.conf
  echo 'enabled=true' | sudo tee -a /etc/wsl.conf
Then restart WSL."
else
  info "Windows interop enabled"
fi

# 8. Check systemd (optional)
if systemctl --version >/dev/null 2>&1; then
  info "systemd enabled"
else
  warn "systemd not enabled (optional feature)"
fi

# 9. Check available disk space
AVAILABLE=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$AVAILABLE" -lt 10 ]; then
  error "Insufficient disk space. Need at least 10GB, got ${AVAILABLE}GB available"
fi
info "Sufficient disk space (${AVAILABLE}GB available)"

# 10. Check if curl is available
if ! command -v curl >/dev/null 2>&1; then
  error "curl is not installed. Please run: sudo apt update && sudo apt install -y curl"
fi
info "curl available"

# 11. Check if git is available
if ! command -v git >/dev/null 2>&1; then
  warn "git not installed. Will be installed during setup."
else
  info "git available"
fi

echo
info "All critical prerequisites satisfied! 🎉"
echo