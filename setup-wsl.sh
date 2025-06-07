#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/ubuntu-dev-tools.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== [setup-wsl.sh] Started at $(date) ==="

# Check if running in WSL
if ! grep -qi microsoft /proc/version 2>/dev/null && ! grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
  echo "🚫 This script is intended for WSL environments only. Exiting."
  exit 0
fi

echo "🐧 WSL environment detected. Configuring WSL-specific settings..."

# --- WSL.conf Optimization ---
echo "📝 Creating optimized wsl.conf..."

sudo tee /etc/wsl.conf > /dev/null << 'EOF'
[boot]
systemd=true

[automount]
enabled = false
root = /
options=metadata,uid=1000,gid=1000,umask=022,fmask=111
mountFsTab = true

[interop]
enabled=true
appendWindowsPath=false

[network]
hostname = hpdevcore
generateHosts = true
generateResolvConf = true
EOF

echo "✅ WSL.conf has been optimized."

# --- Configure DNS for better WSL networking ---
echo "🌐 Configuring DNS for better WSL networking..."

# Create resolv.conf with CloudFlare and Google DNS
sudo tee /etc/resolv.conf > /dev/null << 'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

# Make resolv.conf immutable to prevent WSL from overwriting it
sudo chattr +i /etc/resolv.conf

# --- Setup VS Code integration for both regular and Insiders ---
echo "💻 Setting up VS Code WSL integration..."

# Install VS Code server components for both regular and Insiders
if command -v code >/dev/null 2>&1; then
  echo "VS Code detected, ensuring WSL compatibility..."
  code --install-extension ms-vscode-remote.remote-wsl >/dev/null 2>&1 || true
fi

if command -v code-insiders >/dev/null 2>&1; then
  echo "VS Code Insiders detected, ensuring WSL compatibility..."
  code-insiders --install-extension ms-vscode-remote.remote-wsl >/dev/null 2>&1 || true
fi

# Create VS Code configuration directory
mkdir -p ~/.vscode-server/data/Machine
mkdir -p ~/.vscode-server-insiders/data/Machine

# --- Windows Interoperability Optimizations ---
echo "🔄 Optimizing Windows interoperability..."

# Add Windows host to hosts file for faster name resolution
WINDOWS_HOST_IP=$(ip route | grep default | awk '{print $3}')
if [ -n "$WINDOWS_HOST_IP" ]; then
  if ! grep -q "windows-host" /etc/hosts; then
    echo "$WINDOWS_HOST_IP windows-host" | sudo tee -a /etc/hosts > /dev/null
  fi
fi

# Optimize memory usage for WSL
sudo tee /etc/sysctl.d/99-wsl.conf > /dev/null << 'EOF'
# Reduce memory usage
vm.swappiness=10
vm.vfs_cache_pressure=50

# Increase network performance
net.core.somaxconn=4096
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
EOF

sudo sysctl --system

echo "✅ WSL configuration completed! Changes will take full effect after restarting your WSL instance."
echo "To restart WSL, run 'wsl --shutdown' in PowerShell or Command Prompt, then reopen your WSL terminal."
