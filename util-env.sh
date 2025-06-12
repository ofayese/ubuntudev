#!/usr/bin/env bash
# util-env.sh - Unified environment detection and system info utilities
set -euo pipefail

# --- Environment Types ---
readonly ENV_WSL="WSL2"
readonly ENV_DESKTOP="DESKTOP"
readonly ENV_HEADLESS="HEADLESS"

# --- Detect environment type ---
detect_environment() {
  if grep -qi microsoft /proc/version 2>/dev/null || grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
    echo "$ENV_WSL"
  elif command -v gnome-shell >/dev/null 2>&1 && \
       (echo "${XDG_SESSION_TYPE:-}" | grep -qE 'x11|wayland'); then
    echo "$ENV_DESKTOP"
  else
    echo "$ENV_HEADLESS"
  fi
}

# --- Detect WSL version ---
get_wsl_version() {
  if grep -qi microsoft /proc/version 2>/dev/null || grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
    if grep -qi "microsoft-standard" /proc/sys/kernel/osrelease 2>/dev/null; then
      echo "2"
    else
      echo "1"
    fi
  else
    echo "0"
  fi
}

# --- Check if systemd is running ---
is_systemd_running() {
  if pidof systemd >/dev/null 2>&1 && systemctl is-system-running >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# --- Get Windows host details (in WSL) ---
get_windows_hostname() {
  if command -v cmd.exe >/dev/null 2>&1; then
    cmd.exe /c "hostname" 2>/dev/null | tr -d '\r' || echo "winhost"
  else
    echo "winhost"
  fi
}

# --- Get Ubuntu version ---
get_ubuntu_version() {
  if [ -f /etc/os-release ]; then
    source /etc/os-release
    if [[ "$ID" == "ubuntu" ]]; then
      echo "$VERSION_ID"
    else
      echo "non-ubuntu"
    fi
  else
    echo "unknown"
  fi
}

# --- Get available memory in GB ---
get_available_memory() {
  local mem_available
  mem_available=$(free -m | awk '/^Mem:/ {print $7}')
  echo "scale=1; $mem_available/1024" | bc
}

# --- Get available disk space in GB ---
get_available_disk() {
  local disk_available
  disk_available=$(df -BG "$HOME" | tail -1 | awk '{print $4}' | tr -d 'G')
  echo "$disk_available"
}

# --- Check if command exists ---
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# --- Print colorized environment banner ---
print_env_banner() {
  local env_type
  env_type=$(detect_environment)
  case "$env_type" in
    "$ENV_WSL")
      echo -e "\033[1;36m💻 WSL2 Environment\033[0m" ;;
    "$ENV_DESKTOP")
      echo -e "\033[1;32m🖥️ Desktop Environment\033[0m" ;;
    *)
      echo -e "\033[1;33m🔧 Headless Environment\033[0m" ;;
  esac
}

# --- Is this a privileged WSL2 distro? ---
is_wsl_systemd_enabled() {
  if [ -f "/etc/wsl.conf" ] && grep -q "systemd=true" /etc/wsl.conf; then
    return 0
  else
    return 1
  fi
}

# Direct usage example: detect_environment
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  detect_environment
fi
