#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/ubuntu-dev-tools.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== [setup-wsl.sh] Started at $(date) ==="

# --- Detect WSL and WSL2 ---
IS_WSL=0
IS_WSL2=0
if grep -qi microsoft /proc/version 2>/dev/null || grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
  IS_WSL=1
  if grep -qi "microsoft-standard" /proc/sys/kernel/osrelease 2>/dev/null; then
    IS_WSL2=1
  fi
fi

# --- Detect Ubuntu ---
IS_UBUNTU=0
if [ -f /etc/os-release ] && grep -qi 'ubuntu' /etc/os-release; then
  IS_UBUNTU=1
fi

if [ "$IS_WSL" -eq 0 ]; then
  echo "🚫 This script is intended for WSL environments only. Exiting."
  exit 0
fi

if [ "$IS_UBUNTU" -eq 1 ]; then
  echo "🐧 Ubuntu detected inside WSL."
else
  echo "⚠️  Non-Ubuntu distribution detected inside WSL."
fi

if [ "$IS_WSL2" -eq 1 ]; then
  echo "🔎 WSL2 environment detected."
else
  echo "🔎 WSL1 environment detected."
fi

# --- Determine Windows Hostname for Consistency ---
if command -v cmd.exe >/dev/null; then
  WIN_HOSTNAME=$(cmd.exe /c "hostname" | tr -d '\r')
else
  WIN_HOSTNAME="wsl-devbox"
fi

echo "📛 Using Windows hostname: $WIN_HOSTNAME"

# --- Configure /etc/wsl.conf ---
echo "📝 Writing optimized wsl.conf..."
sudo tee /etc/wsl.conf > /dev/null << EOF
[boot]
systemd=true

[automount]
enabled = false
root = /mnt/
options=metadata,uid=1000,gid=1000,umask=022,fmask=111
mountFsTab = true

[interop]
enabled=true
appendWindowsPath=false

[network]
hostname = ${WIN_HOSTNAME}
generateHosts = true
generateResolvConf = false
EOF

echo "✅ /etc/wsl.conf configured."

# --- Configure resolv.conf DNS ---
echo "🌐 Setting DNS to Cloudflare and Google..."
sudo tee /etc/resolv.conf > /dev/null << 'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
sudo chattr +i /etc/resolv.conf
echo "✅ DNS configuration complete."

# --- VS Code WSL integration ---
echo "💻 Configuring VS Code Remote - WSL..."

if command -v code >/dev/null 2>&1; then
  code --install-extension ms-vscode-remote.remote-wsl || true
fi
if command -v code-insiders >/dev/null 2>&1; then
  code-insiders --install-extension ms-vscode-remote.remote-wsl || true
fi

mkdir -p ~/.vscode-server/data/Machine
mkdir -p ~/.vscode-server-insiders/data/Machine

# --- Symlink readable folder names ---
echo "🔗 Creating symlinks for human-readable WSL machine names..."
WSL_REMOTE_NAME="${WIN_HOSTNAME:-wsl-devbox}"

for variant in ".vscode-server" ".vscode-server-insiders"; do
  SERVER_DIR="$HOME/$variant/data/Machine"
  mkdir -p "$SERVER_DIR"

  HASHED=$(find "$SERVER_DIR" -maxdepth 1 -type d | grep -Ev "/Machine\$" | head -n 1)
  if [ -n "$HASHED" ]; then
    LINK_NAME="${SERVER_DIR}/${WSL_REMOTE_NAME}"
    if [ ! -L "$LINK_NAME" ]; then
      ln -s "$HASHED" "$LINK_NAME"
      echo "🔗 Linked: $LINK_NAME → $HASHED"
    fi
  fi
done

# --- Interop Enhancements ---
echo "🔄 Adding Windows host alias..."
WINDOWS_HOST_IP=$(ip route | grep default | awk '{print $3}')
if [ -n "$WINDOWS_HOST_IP" ]; then
  if ! grep -q "windows-host" /etc/hosts; then
    echo "$WINDOWS_HOST_IP windows-host" | sudo tee -a /etc/hosts > /dev/null
  fi
fi

# --- System Tuning for WSL ---
echo "🧠 Optimizing WSL system behavior..."
sudo tee /etc/sysctl.d/99-wsl.conf > /dev/null << 'EOF'
# Memory
vm.swappiness=10
vm.vfs_cache_pressure=50

# Network
net.core.somaxconn=4096
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
EOF
sudo sysctl --system

echo "✅ WSL configuration complete!"
echo "🚨 Please run: wsl --shutdown from PowerShell or CMD to apply all changes."
