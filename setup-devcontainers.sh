#!/usr/bin/env bash
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
  sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
  sudo apt update
  safe_install ca-certificates curl gnupg lsb-release apt-transport-https

  # Download latest Docker Desktop .deb
  echo "🔍 Fetching Docker Desktop download URL..."
  DESKTOP_URL=$(curl -s https://api.github.com/repos/docker/desktop/releases/latest |
    grep browser_download_url | grep 'docker-desktop-.*-amd64.deb' | head -1 | cut -d '"' -f 4)

  if [[ -z "$DESKTOP_URL" ]]; then
    echo "❌ Failed to fetch Docker Desktop download URL."
    echo "👉 Please install Docker Desktop manually from https://docs.docker.com/desktop/install/linux-install/"
    return 1
  fi

  echo "📦 Downloading Docker Desktop..."
  if wget -q -O /tmp/docker-desktop.deb "$DESKTOP_URL"; then
    echo "🔧 Installing Docker Desktop..."
    if sudo apt install -y /tmp/docker-desktop.deb 2>/dev/null; then
      rm -f /tmp/docker-desktop.deb
      systemctl --user start docker-desktop 2>/dev/null || true
      echo "✅ Docker Desktop for Linux installed."
      return 0
    else
      echo "⚠️ Docker Desktop installation failed, trying to fix dependencies..."
      sudo apt --fix-broken install -y 2>/dev/null || true
      rm -f /tmp/docker-desktop.deb
      return 1
    fi
  else
    echo "❌ Failed to download Docker Desktop"
    rm -f /tmp/docker-desktop.deb
    return 1
  fi
}

# Function to safely install packages
safe_install() {
    local packages=("$@")
    for pkg in "${packages[@]}"; do
        if sudo apt install -y "$pkg" 2>/dev/null; then
            echo "✅ Installed $pkg"
        else
            echo "⚠️ Could not install $pkg"
        fi
    done
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
