#!/usr/bin/env bash
# Utility: util-wsl.sh
# Description: WSL-specific configuration and optimizations
# Last Updated: 2025-06-13
# Version: 1.0.0

set -euo pipefail

# Load guard to prevent multiple sourcing
if [[ -n "${UTIL_WSL_SH_LOADED:-}" ]]; then
  return 0
fi
readonly UTIL_WSL_SH_LOADED=1

# ------------------------------------------------------------------------------
# Global Variable Initialization (Safe conditional pattern)
# ------------------------------------------------------------------------------

# Script directory (only declare once globally)
if [[ -z "${SCRIPT_DIR:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  readonly SCRIPT_DIR
fi

# Version & timestamp (only declare once globally)
if [[ -z "${VERSION:-}" ]]; then
  VERSION="1.0.0"
  readonly VERSION
fi

if [[ -z "${LAST_UPDATED:-}" ]]; then
  LAST_UPDATED="2025-06-13"
  readonly LAST_UPDATED
fi

# OS detection (only declare once globally)
if [[ -z "${OS_TYPE:-}" ]]; then
  OS_TYPE="$(uname -s)"
  readonly OS_TYPE
fi

# Dry run support (only declare once globally)
if [[ -z "${DRY_RUN:-}" ]]; then
  DRY_RUN="false"
  readonly DRY_RUN
fi

# ------------------------------------------------------------------------------
# Dependencies: Load required utilities
# ------------------------------------------------------------------------------

if [[ -z "${UTIL_LOG_SH_LOADED:-}" && -f "${SCRIPT_DIR}/util-log.sh" ]]; then
  source "${SCRIPT_DIR}/util-log.sh" || {
    echo "[ERROR] Failed to source util-log.sh" >&2
    exit 1
  }
fi

if [[ -z "${UTIL_ENV_SH_LOADED:-}" && -f "${SCRIPT_DIR}/util-env.sh" ]]; then
  source "${SCRIPT_DIR}/util-env.sh" || {
    echo "[ERROR] Failed to source util-env.sh" >&2
    exit 1
  }
fi

# ------------------------------------------------------------------------------
# Module Functions
# ------------------------------------------------------------------------------

# --- Configure optimal WSL.conf settings ---
setup_wsl_conf() {
  init_logging

  # Check if running in WSL
  if ! grep -qi microsoft /proc/version 2>/dev/null && ! grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
    log_info "Not running in WSL environment. Skipping WSL configuration."
    finish_logging
    return 0
  fi

  log_info "Setting up optimal WSL configuration..."

  # Get Windows hostname for consistency
  local WIN_HOSTNAME
  WIN_HOSTNAME=$(get_windows_hostname)
  log_info "Using Windows hostname: $WIN_HOSTNAME"

  # Create optimized wsl.conf
  log_info "Writing optimized wsl.conf..."
  sudo tee /etc/wsl.conf >/dev/null <<EOF
# Ubuntu Development Environment - Optimized WSL Configuration
# Generated at $(date)

[boot]
systemd=true

[automount]
enabled = true
root = /mnt/
options = "metadata,umask=22,fmask=11"
mountFsTab = true

[interop]
enabled = true
appendWindowsPath = false

[network]
hostname = ${WIN_HOSTNAME}-wsl
generateHosts = true
generateResolvConf = true

[user]
default = $(whoami)
EOF

  log_success "Wrote optimized /etc/wsl.conf"

  # Check if systemd is enabled
  if is_wsl_systemd_enabled; then
    if is_systemd_running; then
      log_success "systemd is correctly configured and running"
    else
      log_warning "systemd is configured but not running. WSL restart required"
      log_info "Run this in PowerShell: wsl --shutdown"
    fi
  else
    log_warning "systemd is not enabled in WSL. Restart required after configuration"
    log_info "Run this in PowerShell: wsl --shutdown"
  fi

  finish_logging
  return 0
}

# --- DNS Configuration ---
setup_wsl_dns() {
  init_logging

  # Check if running in WSL
  if ! grep -qi microsoft /proc/version; then
    log_info "Not running in WSL environment. Skipping WSL DNS configuration."
    finish_logging
    return 0
  fi

  log_info "Setting up WSL DNS configuration..."

  # Check if we need custom DNS (only if current DNS is not working)
  if nslookup github.com >/dev/null 2>&1; then
    log_success "DNS is working correctly, no changes needed"
    finish_logging
    return 0
  fi

  log_warning "DNS appears to be having issues, applying custom configuration..."

  # Disable WSL's automatic DNS generation in wsl.conf
  if ! grep -q "generateResolvConf.*false" /etc/wsl.conf 2>/dev/null; then
    log_info "Disabling automatic DNS generation in wsl.conf..."
    sudo sed -i '/^\[network\]/,/^\[/ { s/generateResolvConf.*/generateResolvConf = false/; }' /etc/wsl.conf 2>/dev/null || {
      # Add network section if it doesn't exist
      echo -e "\n[network]\ngenerateResolvConf = false" | sudo tee -a /etc/wsl.conf >/dev/null
    }
  fi

  # Remove immutable attribute if set
  # Make resolv.conf writable, but don't fail if chattr isn't supported
  sudo chattr -i /etc/resolv.conf 2>/dev/null || true

  # Create our custom resolv.conf
  sudo tee /etc/resolv.conf >/dev/null <<'EOF'
# Ubuntu Development Environment - Custom DNS Configuration
# Applied due to DNS connectivity issues
nameserver 1.1.1.1  # Cloudflare
nameserver 8.8.8.8  # Google
nameserver 9.9.9.9  # Quad9
EOF

  # Make it immutable to prevent WSL from overwriting it
  sudo chattr +i /etc/resolv.conf 2>/dev/null || {
    log_warning "Cannot set immutable attribute on /etc/resolv.conf (chattr not supported)"
    log_info "DNS configuration applied but may be overwritten by WSL"
    # Don't fail the entire script for this
  }

  log_success "Custom DNS resolvers configured (Cloudflare, Google, Quad9)"
  log_warning "WSL restart required for DNS changes to take full effect"
  finish_logging
}

# --- Symlink Windows Paths ---
setup_windows_symlinks() {
  init_logging

  # Check if running in WSL
  if ! grep -qi microsoft /proc/version; then
    log_info "Not running in WSL environment. Skipping Windows path symlinks."
    finish_logging
    return 0
  fi

  log_info "Setting up Windows path symlinks..."

  # Get Windows username
  local WIN_USERNAME
  WIN_USERNAME=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r' || echo "User")
  log_info "Windows username detected: $WIN_USERNAME"

  # Get Windows hostname
  local WIN_HOSTNAME
  WIN_HOSTNAME=$(get_windows_hostname)

  # Create Home Directory Symlinks
  log_info "Creating common Windows path symlinks..."

  # Define essential paths to link (commonly used directories)
  local WIN_PATHS
  WIN_PATHS=(
    "/c/Users/$WIN_USERNAME/Desktop:$HOME/Desktop"
    "/c/Users/$WIN_USERNAME/Documents:$HOME/Documents"
    "/c/Users/$WIN_USERNAME/Downloads:$HOME/Downloads"
    "/c/Users/$WIN_USERNAME/source:$HOME/source"
  )

  # Define optional paths (may not exist or may cause permission issues)
  local OPTIONAL_PATHS
  OPTIONAL_PATHS=(
    "/c/Users/$WIN_USERNAME/Pictures:$HOME/Pictures"
    "/c/Users/$WIN_USERNAME/AppData/Local:$HOME/AppData"
  )

  # Create essential symlinks
  for path_pair in "${WIN_PATHS[@]}"; do
    WIN_PATH="${path_pair%%:*}"
    WSL_PATH="${path_pair##*:}"

    if [ -d "$WIN_PATH" ]; then
      if [ ! -e "$WSL_PATH" ]; then
        ln -s "$WIN_PATH" "$WSL_PATH"
        log_success "Created symlink: $WSL_PATH -> $WIN_PATH"
      else
        log_info "Symlink or directory already exists: $WSL_PATH"
      fi
    else
      log_warning "Windows path doesn't exist: $WIN_PATH"
    fi
  done

  # Create optional symlinks (with extra checks)
  for path_pair in "${OPTIONAL_PATHS[@]}"; do
    WIN_PATH="${path_pair%%:*}"
    WSL_PATH="${path_pair##*:}"

    if [ -d "$WIN_PATH" ] && [ ! -e "$WSL_PATH" ]; then
      ln -s "$WIN_PATH" "$WSL_PATH"
      log_success "Created optional symlink: $WSL_PATH -> $WIN_PATH"
    fi
  done
  log_success "VS Code integration handled by Windows installations"
  finish_logging
}

# --- Configure WSL Git Integration ---
setup_wsl_git() {
  init_logging

  # Check if running in WSL
  if ! grep -qi microsoft /proc/version; then
    log_info "Not running in WSL environment. Skipping WSL Git configuration."
    finish_logging
    return 0
  fi

  log_info "Setting up WSL Git configuration..."

  # Configure Git to use Windows Credential Manager
  git config --global credential.helper "/mnt/c/Program\ Files/Git/mingw64/bin/git-credential-manager.exe"

  # Use VS Code Insiders from Windows for Git
  git config --global core.editor "/mnt/c/Program\ Files/Microsoft\ VS\ Code\ Insiders/bin/code-insiders.exe --wait"

  # Configure Git to use LF line endings in the repo but CRLF on checkout
  git config --global core.autocrlf input

  log_success "Git configured for WSL/Windows integration"
  finish_logging
}

# --- Configure Windows Terminal Integration ---
setup_windows_terminal() {
  init_logging

  # Check if running in WSL
  if ! grep -qi microsoft /proc/version; then
    log_info "Not running in WSL environment. Skipping Windows Terminal configuration."
    finish_logging
    return 0
  fi

  log_info "Setting up Windows Terminal integration..."

  # Create a simple script to help launch Windows Terminal
  local WT_SCRIPT="$HOME/bin/wt"
  mkdir -p "$HOME/bin"

  cat >"$WT_SCRIPT" <<'EOF'
#!/bin/bash
# Helper to launch Windows Terminal from WSL
if command -v wt.exe >/dev/null 2>&1; then
  wt.exe "$@" >/dev/null 2>&1 &
else
  cmd.exe /c start wt.exe "$@" >/dev/null 2>&1
fi
EOF

  chmod +x "$WT_SCRIPT"

  # Add to PATH if not already there
  if ! grep -q "$HOME/bin" "$HOME/.bashrc"; then
    echo 'export PATH="$HOME/bin:$PATH"' >>"$HOME/.bashrc"
  fi

  # Also create an alias for launching new WSL tabs
  if ! grep -q "alias wsl-here" "$HOME/.bashrc"; then
    echo 'alias wsl-here="wt.exe -d ."' >>"$HOME/.bashrc"
  fi

  log_success "Windows Terminal integration configured"
  log_info "You can now type 'wt' to launch Windows Terminal or 'wsl-here' for current directory"

  finish_logging
}

# --- Configure performance optimizations ---
optimize_wsl_performance() {
  init_logging

  # Check if running in WSL
  if ! grep -qi microsoft /proc/version; then
    log_info "Not running in WSL environment. Skipping WSL performance optimizations."
    finish_logging
    return 0
  fi

  log_info "Applying WSL performance optimizations..."

  # Create .wslconfig in Windows home if it doesn't exist
  local WIN_USERNAME
  WIN_USERNAME=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r')
  local WSLCONFIG_PATH
  WSLCONFIG_PATH="/mnt/c/Users/$WIN_USERNAME/.wslconfig"

  if [ ! -f "$WSLCONFIG_PATH" ]; then
    log_info "Creating .wslconfig in Windows home directory..."

    # Get system memory and compute 50% for WSL
    local TOTAL_MEM_KB
    TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local TOTAL_MEM_GB
    TOTAL_MEM_GB=$(echo "scale=1; $TOTAL_MEM_KB / 1024 / 1024" | bc)
    local WSL_MEM_GB
    WSL_MEM_GB=$(echo "scale=0; $TOTAL_MEM_GB / 2" | bc)

    # Ensure we allocate at least 4GB but not more than 16GB
    if (($(echo "$WSL_MEM_GB < 4" | bc -l))); then
      WSL_MEM_GB=4
    elif (($(echo "$WSL_MEM_GB > 16" | bc -l))); then
      WSL_MEM_GB=16
    fi

    cat >"$WSLCONFIG_PATH" <<EOF
# WSL2 Configuration - Created by Ubuntu Dev Environment Setup
[wsl2]
memory=${WSL_MEM_GB}GB
processors=4
swap=4GB
localhostForwarding=true
EOF

    log_success "Created optimized .wslconfig file (WSL memory: ${WSL_MEM_GB}GB)"
  else
    log_info ".wslconfig already exists in Windows home directory"
  fi

  # Optimize I/O performance
  log_info "Applying I/O performance tweaks..."

  # Add to fstab if not already there
  if [ ! -f /etc/fstab ] || ! grep -q "tmpfs /tmp" /etc/fstab; then
    echo "tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0" | sudo tee -a /etc/fstab >/dev/null
    log_success "Added tmpfs mount for /tmp in fstab"
  fi

  # Mount tmpfs for /tmp now if not already mounted
  if ! mount | grep -q "tmpfs on /tmp"; then
    sudo mount -t tmpfs -o defaults,noatime,mode=1777 tmpfs /tmp
    log_success "Mounted tmpfs for /tmp"
  else
    log_info "/tmp already using tmpfs"
  fi

  # Add Linux swap file if needed
  if [ ! -f /swapfile ]; then
    log_info "Creating 2GB swap file..."
    sudo fallocate -l 2G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab >/dev/null
    log_success "Swap file created and enabled"
  fi

  # Add I/O optimizations to sysctl
  log_info "Applying sysctl optimizations..."

  SYSCTL_CONF="/etc/sysctl.d/99-wsl-io-perf.conf"
  sudo tee "$SYSCTL_CONF" >/dev/null <<'EOF'
# WSL I/O Performance Optimizations
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_background_ratio=5
vm.dirty_ratio=10
EOF

  # Apply optimizations now
  sudo sysctl -p "$SYSCTL_CONF"

  log_success "WSL performance optimizations applied"
  finish_logging
}

# --- Configure WSL2 environment (main function) ---
setup_wsl_environment() {
  # Only proceed if we're in WSL
  if ! grep -qi microsoft /proc/version 2>/dev/null; then
    echo "Not running in WSL environment. Skipping WSL configuration."
    return 0
  fi

  init_logging
  log_info "Setting up complete WSL2 environment..."

  # Run all WSL configuration functions
  setup_wsl_conf
  setup_wsl_dns
  setup_windows_symlinks
  setup_wsl_git
  setup_windows_terminal
  optimize_wsl_performance

  log_success "WSL2 environment fully configured"
  log_warning "Some changes require a WSL restart to take effect"
  log_info "Run 'wsl --shutdown' in PowerShell then restart your WSL terminal"

  finish_logging
}

# Main function for demonstration
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  setup_wsl_environment
fi
