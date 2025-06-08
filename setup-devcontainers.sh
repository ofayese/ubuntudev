#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/ubuntu-dev-tools.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== [setup-devcontainers.sh] Started at $(date) ==="

# --- Detect environment ---
if grep -qi microsoft /proc/version; then
  IS_WSL=1
  echo "🧠 WSL2 environment detected."
else
  IS_WSL=0
  echo "🖥️ Native Linux environment detected."
fi

# --- Function: Check Docker availability ---
check_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "❌ Docker CLI not found."
    return 1
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker daemon not accessible. Is Docker Desktop running?"
    return 1
  fi
  echo "✅ Docker is installed and accessible."
  return 0
}

# --- Install Docker Desktop on Ubuntu (native only) ---
install_docker_desktop_linux() {
  echo "⬇️ Installing Docker Desktop for Linux..."

  # Remove conflicting versions
  sudo apt remove -y docker docker-engine docker.io containerd runc || true
  sudo apt update
  sudo apt install -y ca-certificates curl gnupg lsb-release apt-transport-https

  # Download latest Docker Desktop .deb
  DESKTOP_URL=$(curl -s https://api.github.com/repos/docker/desktop/releases/latest |
    grep browser_download_url | grep 'docker-desktop-.*-amd64.deb' | cut -d '"' -f 4)

  if [[ -z "$DESKTOP_URL" ]]; then
    echo "❌ Failed to fetch Docker Desktop download URL."
    exit 1
  fi

  curl -L -o /tmp/docker-desktop.deb "$DESKTOP_URL"
  sudo apt install -y /tmp/docker-desktop.deb
  rm -f /tmp/docker-desktop.deb

  systemctl --user start docker-desktop || true
  echo "✅ Docker Desktop for Linux installed."
}

# --- Main logic ---
if [ "$IS_WSL" -eq 1 ]; then
  echo "⚙️ Validating Docker Desktop for Windows integration..."

  if ! check_docker; then
    echo "❌ Docker not running in Windows or not connected to WSL2."
    echo "👉 Please launch Docker Desktop in Windows and enable WSL integration."
    exit 1
  fi

else
  echo "🔧 Installing Docker Desktop for Ubuntu Desktop..."
  install_docker_desktop_linux
fi

# --- Add current user to docker group ---
USERNAME=$(logname || echo "${SUDO_USER:-$USER}")
echo "👥 Adding $USERNAME to docker group..."
sudo groupadd -f docker
sudo usermod -aG docker "$USERNAME"

echo "✅ Docker Desktop setup complete. Please log out and log in again for group changes to apply."
