#!/usr/bin/env bash
set -e

error() {
  echo "❌ $1"
  exit 1
}

info() {
  echo "✅ $1"
}

echo "Checking prerequisites..."

# 1. Must be running inside WSL
if ! grep -qi microsoft /proc/version; then
  error "Not running inside WSL. Please run this script inside WSL (Ubuntu)."
fi
info "Running inside WSL"

# 2. Docker CLI must be available
if ! command -v docker >/dev/null 2>&1; then
  error "Docker CLI not found.
Please install Docker Desktop for Windows and enable WSL integration."
fi

# 3. Docker daemon must be reachable (Docker Desktop running)
if ! docker version >/dev/null 2>&1; then
  error "Docker is installed but not running.
Please start Docker Desktop and wait until it is ready."
fi
info "Docker CLI available"

# 4. Docker Compose v2 check
if ! docker compose version >/dev/null 2>&1; then
  error "Docker Compose v2 not available.
Please ensure you are using Docker Desktop with Compose v2 enabled."
fi
info "Docker Compose v2 available"

echo
info "All prerequisites satisfied."