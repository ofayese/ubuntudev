#!/bin/bash
set -euo pipefail

echo "=== [validate-docker-desktop.sh] Started at $(date) ==="

# --- Check Docker CLI ---
if ! command -v docker >/dev/null 2>&1; then
  echo "❌ Docker CLI is not installed in this environment."
  exit 1
fi

# --- Check Docker Daemon ---
if ! docker info >/dev/null 2>&1; then
  echo "❌ Docker daemon is not running or not accessible."
  echo "👉 Please start Docker Desktop (Windows/Linux) and ensure WSL2 integration is enabled."
  exit 1
else
  echo "✅ Docker daemon is running and accessible."
fi

# --- Check Docker context (for WSL2) ---
if grep -qi microsoft /proc/version; then
  echo "🔍 Checking Docker context in WSL2..."

  CONTEXT=$(docker context show)
  if [[ "$CONTEXT" != "default" && "$CONTEXT" != *"wsl"* ]]; then
    echo "⚠️  Unexpected Docker context: $CONTEXT"
    echo "👉 Use 'docker context use default' or ensure WSL integration is active in Docker Desktop."
    exit 1
  else
    echo "✅ Docker context: $CONTEXT (WSL-compatible)"
  fi
fi

# --- Check systemd (for WSL2) ---
if grep -qi microsoft /proc/version; then
  echo "🔍 Checking systemd status in WSL2..."

  if pidof systemd >/dev/null 2>&1 && systemctl is-system-running --quiet; then
    echo "✅ systemd is running inside WSL2."
  else
    echo "❌ systemd is not running inside WSL2."
    echo "👉 Ensure you have 'systemd=true' under [boot] in /etc/wsl.conf and restart WSL."
    exit 1
  fi
fi

echo "✅ All checks passed! Docker Desktop with WSL2/systemd is ready."
