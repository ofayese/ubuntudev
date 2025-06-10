#!/usr/bin/env bash
# setup-wsl.sh - Configure WSL-specific optimizations
set -euo pipefail

# Use shared utility functions for WSL and environment detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-log.sh"
source "$SCRIPT_DIR/util-env.sh"
source "$SCRIPT_DIR/util-wsl.sh"

# Initialize logging
init_logging
log_info "Setting up WSL optimizations"

# Verify we're running in WSL
ENV_TYPE=$(detect_environment)
WSL_VERSION=$(get_wsl_version)

if [[ "$ENV_TYPE" != "$ENV_WSL" ]]; then
  log_error "This script is intended for WSL environments only. Exiting."
  finish_logging
  exit 0
fi

# Show environment info
ubuntu_version=$(get_ubuntu_version)
if [[ "$ubuntu_version" != "non-ubuntu" && "$ubuntu_version" != "unknown" ]]; then
  log_info "Ubuntu $ubuntu_version detected inside WSL."
else
  log_warning "Non-Ubuntu distribution detected inside WSL."
fi

if [[ "$WSL_VERSION" == "2" ]]; then
  log_info "WSL2 environment detected."
else
  log_warning "WSL1 environment detected. Some features may not work properly."
fi

# Get Windows hostname
WIN_HOSTNAME=$(get_windows_hostname)
log_info "Using Windows hostname: $WIN_HOSTNAME"

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

# Check if VS Code is installed in WSL and uninstall if found
if command -v code >/dev/null 2>&1 || command -v code-insiders >/dev/null 2>&1; then
    echo "🔍 VS Code installation detected in WSL. Removing redundant installation..."
    
    if command -v code >/dev/null 2>&1; then
        echo "🗑️ Removing VS Code from WSL..."
        sudo DEBIAN_FRONTEND=noninteractive apt remove -y code
    fi
    
    if command -v code-insiders >/dev/null 2>&1; then
        echo "🗑️ Removing VS Code Insiders from WSL..."
        sudo DEBIAN_FRONTEND=noninteractive apt remove -y code-insiders
    fi
    
    # Clean up any leftover dependencies
    sudo DEBIAN_FRONTEND=noninteractive apt autoremove -y
    
    echo "✅ Removed redundant VS Code installation from WSL."
    echo "   Remote-WSL extension in Windows VS Code handles the connection automatically."
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
