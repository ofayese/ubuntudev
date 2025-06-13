#!/usr/bin/env bash
# util-env.sh - Unified environment detection and system info utilities
set -euo pipefail

# Guard against multiple sourcing
if [[ "${UTIL_ENV_LOADED:-}" == "true" ]]; then
  return 0
fi
readonly UTIL_ENV_LOADED="true"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/util-log.sh" ]]; then
  source "$SCRIPT_DIR/util-log.sh"
fi

# --- Environment Types (with guards to prevent redeclaration) ---
if [[ -z "${ENV_WSL:-}" ]]; then
  readonly ENV_WSL="WSL2"
fi

if [[ -z "${ENV_DESKTOP:-}" ]]; then
  readonly ENV_DESKTOP="DESKTOP"
fi

if [[ -z "${ENV_HEADLESS:-}" ]]; then
  readonly ENV_HEADLESS="HEADLESS"
fi

# Resource monitoring with caching and comprehensive metrics
declare -A RESOURCE_CACHE=()
declare -A CACHE_TIMESTAMPS=()
readonly CACHE_TTL=300 # 5 minutes

# --- Enhanced environment detection with multiple validation methods ---
detect_environment() {
  local env_type=""
  local confidence_score=0

  # WSL Detection with multiple methods
  if detect_wsl_environment; then
    env_type="$ENV_WSL"
    confidence_score=90
  # Desktop detection with comprehensive checks
  elif detect_desktop_environment; then
    env_type="$ENV_DESKTOP"
    confidence_score=85
  # Headless as fallback
  else
    env_type="$ENV_HEADLESS"
    confidence_score=70
  fi

  # Validate detection confidence
  if [[ $confidence_score -lt 80 ]] && [[ "${DEBUG_LOGGING:-false}" == "true" ]]; then
    log_debug "Environment detection confidence low ($confidence_score%): $env_type"
  fi

  echo "$env_type"
}

detect_wsl_environment() {
  local wsl_indicators=0

  # Method 1: Check /proc/version
  if [[ -f /proc/version ]] && grep -qi microsoft /proc/version 2>/dev/null; then
    ((wsl_indicators++))
  fi

  # Method 2: Check kernel release
  if [[ -f /proc/sys/kernel/osrelease ]] && grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
    ((wsl_indicators++))
  fi

  # Method 3: Check WSL environment variables
  if [[ -n "${WSL_DISTRO_NAME:-}" ]] || [[ -n "${WSL_INTEROP:-}" ]]; then
    ((wsl_indicators++))
  fi

  # Method 4: Check for Windows filesystem mounts
  if mount | grep -q "/mnt/c" 2>/dev/null; then
    ((wsl_indicators++))
  fi

  # Method 5: Check for wslpath command
  if command -v wslpath >/dev/null 2>&1; then
    ((wsl_indicators++))
  fi

  # Require at least 2 indicators for confidence
  [[ $wsl_indicators -ge 2 ]]
}

detect_desktop_environment() {
  local desktop_indicators=0

  # Method 1: Display server check
  if [[ -n "${DISPLAY:-}" ]] || [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    ((desktop_indicators++))
  fi

  # Method 2: Desktop environment variables
  if [[ -n "${XDG_SESSION_TYPE:-}" ]] && echo "${XDG_SESSION_TYPE}" | grep -qE 'x11|wayland'; then
    ((desktop_indicators++))
  fi

  # Method 3: Desktop-specific processes
  if pgrep -x "gnome-shell\|kde-plasma\|xfce4-session\|lxsession" >/dev/null 2>&1; then
    ((desktop_indicators++))
  fi

  # Method 4: GUI toolkit availability
  if command -v gtk-launch >/dev/null 2>&1 || command -v kdialog >/dev/null 2>&1; then
    ((desktop_indicators++))
  fi

  # Method 5: X11 or Wayland compositor running
  if command -v xrandr >/dev/null 2>&1 && xrandr >/dev/null 2>&1; then
    ((desktop_indicators++))
  elif command -v weston-info >/dev/null 2>&1 && weston-info >/dev/null 2>&1; then
    ((desktop_indicators++))
  fi

  # Require at least 2 indicators for confidence
  [[ $desktop_indicators -ge 2 ]]
}

# --- System resource monitoring with caching ---
get_system_resources() {
  local resource_type="$1"
  local format="${2:-GB}" # GB, MB, KB, bytes
  local force_refresh="${3:-false}"

  local cache_key="${resource_type}_${format}"
  local current_time
  current_time=$(date +%s)

  # Check cache validity
  if [[ "$force_refresh" != "true" ]] && [[ -n "${RESOURCE_CACHE[$cache_key]:-}" ]]; then
    local cache_time="${CACHE_TIMESTAMPS[$cache_key]:-0}"
    if [[ $((current_time - cache_time)) -lt $CACHE_TTL ]]; then
      echo "${RESOURCE_CACHE[$cache_key]}"
      return 0
    fi
  fi

  # Get fresh resource data
  local result
  case "$resource_type" in
  "memory_available")
    result=$(get_memory_available_detailed "$format")
    ;;
  "memory_total")
    result=$(get_memory_total_detailed "$format")
    ;;
  "disk_available")
    result=$(get_disk_available_detailed "$format")
    ;;
  "disk_total")
    result=$(get_disk_total_detailed "$format")
    ;;
  "cpu_usage")
    result=$(get_cpu_usage_detailed)
    ;;
  *)
    echo "0"
    return 1
    ;;
  esac

  # Cache the result
  RESOURCE_CACHE["$cache_key"]="$result"
  CACHE_TIMESTAMPS["$cache_key"]="$current_time"

  echo "$result"
}

get_memory_available_detailed() {
  local format="$1"
  local mem_available_kb=0

  # Try multiple methods for memory detection
  if [[ -f /proc/meminfo ]]; then
    # Method 1: Use MemAvailable if present (Linux 3.14+)
    if grep -q "MemAvailable:" /proc/meminfo; then
      mem_available_kb=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
    else
      # Method 2: Calculate from MemFree + Buffers + Cached
      local mem_free mem_buffers mem_cached
      mem_free=$(awk '/MemFree:/ {print $2}' /proc/meminfo)
      mem_buffers=$(awk '/Buffers:/ {print $2}' /proc/meminfo)
      mem_cached=$(awk '/^Cached:/ {print $2}' /proc/meminfo)
      mem_available_kb=$((mem_free + mem_buffers + mem_cached))
    fi
  elif command -v free >/dev/null 2>&1; then
    # Method 3: Use free command
    mem_available_kb=$(free -k | awk '/^Mem:/ {print $7}')
    [[ -z "$mem_available_kb" ]] && mem_available_kb=$(free -k | awk '/^Mem:/ {print $4}')
  else
    echo "0"
    return 1
  fi

  convert_memory_units "$mem_available_kb" "KB" "$format"
}

get_memory_total_detailed() {
  local format="$1"
  local mem_total_kb=0

  # Try multiple methods
  if [[ -f /proc/meminfo ]]; then
    mem_total_kb=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
  elif command -v free >/dev/null 2>&1; then
    mem_total_kb=$(free -k | awk '/^Mem:/ {print $2}')
  else
    echo "0"
    return 1
  fi

  convert_memory_units "$mem_total_kb" "KB" "$format"
}

get_disk_available_detailed() {
  local format="$1"
  local target_path="${2:-$HOME}"

  # Validate target path exists
  if [[ ! -d "$target_path" ]]; then
    target_path="/"
  fi

  local available_kb=0

  # Try multiple methods for disk space detection
  if command -v df >/dev/null 2>&1; then
    # Method 1: Use df with POSIX format
    available_kb=$(df -Pk "$target_path" 2>/dev/null | awk 'NR==2 {print $4}')
  elif command -v stat >/dev/null 2>&1; then
    # Method 2: Use stat for filesystem info (less portable)
    local fs_info
    fs_info=$(stat -f "$target_path" 2>/dev/null)
    if [[ -n "$fs_info" ]]; then
      # This is system-dependent and may need adjustment
      available_kb=$(echo "$fs_info" | awk '/Available blocks:/ {print $3 * 4}') # Assuming 4KB blocks
    fi
  else
    echo "0"
    return 1
  fi

  convert_memory_units "$available_kb" "KB" "$format"
}

get_disk_total_detailed() {
  local format="$1"
  local target_path="${2:-$HOME}"

  # Validate target path exists
  if [[ ! -d "$target_path" ]]; then
    target_path="/"
  fi

  local total_kb=0

  # Try multiple methods for disk space detection
  if command -v df >/dev/null 2>&1; then
    # Method 1: Use df with POSIX format
    total_kb=$(df -Pk "$target_path" 2>/dev/null | awk 'NR==2 {print $2}')
  else
    echo "0"
    return 1
  fi

  convert_memory_units "$total_kb" "KB" "$format"
}

convert_memory_units() {
  local value="$1"
  local from_unit="$2"
  local to_unit="$3"

  # Convert everything to bytes first
  local bytes
  case "$from_unit" in
  "KB") bytes=$((value * 1024)) ;;
  "MB") bytes=$((value * 1024 * 1024)) ;;
  "GB") bytes=$((value * 1024 * 1024 * 1024)) ;;
  "bytes") bytes="$value" ;;
  *)
    echo "0"
    return 1
    ;;
  esac

  # Convert from bytes to target unit
  case "$to_unit" in
  "bytes") echo "$bytes" ;;
  "KB") echo "scale=2; $bytes/1024" | bc -l 2>/dev/null || echo $((bytes / 1024)) ;;
  "MB") echo "scale=2; $bytes/1024/1024" | bc -l 2>/dev/null || echo $((bytes / 1024 / 1024)) ;;
  "GB") echo "scale=2; $bytes/1024/1024/1024" | bc -l 2>/dev/null || echo $((bytes / 1024 / 1024 / 1024)) ;;
  *)
    echo "0"
    return 1
    ;;
  esac
}

get_cpu_usage_detailed() {
  # Get CPU usage over a short sampling period
  if [[ -f /proc/stat ]]; then
    local cpu1 cpu2
    cpu1=$(grep '^cpu ' /proc/stat)
    sleep 0.5
    cpu2=$(grep '^cpu ' /proc/stat)

    # Calculate CPU usage percentage
    local cpu1_idle cpu1_total cpu2_idle cpu2_total
    cpu1_idle=$(echo "$cpu1" | awk '{print $5}')
    cpu1_total=$(echo "$cpu1" | awk '{sum=0; for(i=2;i<=NF;i++) sum+=$i; print sum}')
    cpu2_idle=$(echo "$cpu2" | awk '{print $5}')
    cpu2_total=$(echo "$cpu2" | awk '{sum=0; for(i=2;i<=NF;i++) sum+=$i; print sum}')

    local idle_diff=$((cpu2_idle - cpu1_idle))
    local total_diff=$((cpu2_total - cpu1_total))

    if [[ $total_diff -gt 0 ]]; then
      echo "scale=1; 100 * (1 - $idle_diff/$total_diff)" | bc -l 2>/dev/null || echo "0"
    else
      echo "0"
    fi
  else
    echo "0"
  fi
}

# Convenience functions with caching
get_available_memory() {
  get_system_resources "memory_available" "GB"
}

get_available_disk() {
  get_system_resources "disk_available" "GB"
}

clear_resource_cache() {
  RESOURCE_CACHE=()
  CACHE_TIMESTAMPS=()
}

# --- WSL version detection ---
get_wsl_version() {
  # Not in WSL
  if ! detect_wsl_environment; then
    echo "0"
    return 0
  fi

  # Check for WSL2 indicators
  local wsl2_indicators=0

  # Method 1: Check kernel version for WSL2
  if [[ -f /proc/version ]] && grep -q "microsoft.*WSL2" /proc/version 2>/dev/null; then
    ((wsl2_indicators++))
  fi

  # Method 2: Check for systemd availability (WSL2 feature)
  if [[ -d /run/systemd/system ]]; then
    ((wsl2_indicators++))
  fi

  # Method 3: Check for WSL2-specific network configuration
  if ip addr show eth0 >/dev/null 2>&1; then
    ((wsl2_indicators++))
  fi

  # Method 4: Check for WSL2 environment variable
  if [[ "${WSL_DISTRO_NAME:-}" != "" ]]; then
    ((wsl2_indicators++))
  fi

  # Determine version based on indicators
  if [[ $wsl2_indicators -ge 2 ]]; then
    echo "2"
  else
    echo "1"
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

# --- Is this a privileged WSL2 distro? ---
is_wsl_systemd_enabled() {
  if [ -f "/etc/wsl.conf" ] && grep -q "systemd=true" /etc/wsl.conf; then
    return 0
  else
    return 1
  fi
}

# --- Distribution identification ---
get_distribution_id() {
  local distro_id="unknown"

  # Method 1: /etc/os-release (preferred)
  if [[ -f /etc/os-release ]]; then
    distro_id=$(grep "^ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"')
  # Method 2: lsb_release command
  elif command -v lsb_release >/dev/null 2>&1; then
    distro_id=$(lsb_release -si 2>/dev/null | tr '[:upper:]' '[:lower:]')
  # Method 3: Legacy files
  elif [[ -f /etc/debian_version ]]; then
    distro_id="debian"
  elif [[ -f /etc/redhat-release ]]; then
    distro_id="rhel"
  fi

  echo "$distro_id"
}

get_distribution_name() {
  local distro_name="unknown"

  # Method 1: /etc/os-release
  if [[ -f /etc/os-release ]]; then
    distro_name=$(grep "^NAME=" /etc/os-release | cut -d'=' -f2 | tr -d '"')
  # Method 2: lsb_release
  elif command -v lsb_release >/dev/null 2>&1; then
    distro_name=$(lsb_release -sd 2>/dev/null | tr -d '"')
  fi

  echo "$distro_name"
}

get_distribution_version() {
  local version="unknown"

  # Method 1: /etc/os-release
  if [[ -f /etc/os-release ]]; then
    version=$(grep "^VERSION_ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"')
  # Method 2: lsb_release
  elif command -v lsb_release >/dev/null 2>&1; then
    version=$(lsb_release -sr 2>/dev/null)
  # Method 3: Ubuntu-specific
  elif [[ -f /etc/lsb-release ]]; then
    version=$(grep "DISTRIB_RELEASE=" /etc/lsb-release | cut -d'=' -f2)
  # Method 4: Debian version
  elif [[ -f /etc/debian_version ]]; then
    version=$(cat /etc/debian_version)
  fi

  echo "$version"
}

get_distribution_codename() {
  local codename="unknown"

  # Method 1: /etc/os-release
  if [[ -f /etc/os-release ]]; then
    codename=$(grep "^VERSION_CODENAME=" /etc/os-release | cut -d'=' -f2)
    [[ -z "$codename" ]] && codename=$(grep "^UBUNTU_CODENAME=" /etc/os-release | cut -d'=' -f2)
  # Method 2: lsb_release
  elif command -v lsb_release >/dev/null 2>&1; then
    codename=$(lsb_release -sc 2>/dev/null)
  # Method 3: Ubuntu-specific
  elif [[ -f /etc/lsb-release ]]; then
    codename=$(grep "DISTRIB_CODENAME=" /etc/lsb-release | cut -d'=' -f2)
  fi

  echo "$codename"
}

is_ubuntu_lts() {
  local version="$1"

  # LTS versions are released in April of even years
  case "$version" in
  "24.04" | "22.04" | "20.04" | "18.04" | "16.04" | "14.04") echo "true" ;;
  *) echo "false" ;;
  esac
}

get_ubuntu_support_status() {
  local version="$1"
  local current_year
  current_year=$(date +%Y)
  local current_month
  current_month=$(date +%m)

  # Extract year and month from version
  local version_year="${version%.*}"
  local version_month="${version#*.}"

  # Convert to numeric for comparison
  version_year=$((10#$version_year + 2000))
  version_month=$((10#$version_month)) # Remove leading zero

  # Calculate support end dates
  local support_end_year
  local support_end_month=4 # April

  if [[ "$(is_ubuntu_lts "$version")" == "true" ]]; then
    # LTS versions have 5 years of support
    support_end_year=$((version_year + 5))
  else
    # Non-LTS versions have 9 months of support
    if [[ $version_month -le 4 ]]; then
      support_end_year=$((version_year + 1))
      support_end_month=1 # January
    else
      support_end_year=$((version_year + 1))
      support_end_month=7 # July
    fi
  fi

  # Determine current support status
  if [[ $current_year -lt $support_end_year ]] ||
    [[ $current_year -eq $support_end_year && $current_month -le $support_end_month ]]; then
    echo "supported"
  else
    local months_past_support=$(((current_year - support_end_year) * 12 + (current_month - support_end_month)))
    if [[ $months_past_support -le 12 ]]; then
      echo "recently_unsupported"
    else
      echo "unsupported"
    fi
  fi
}

# --- Windows host information for WSL ---
get_windows_hostname() {
  local hostname="unknown"

  # Try multiple methods to get Windows hostname
  if command -v cmd.exe >/dev/null 2>&1; then
    hostname=$(cmd.exe /c "hostname" 2>/dev/null | tr -d '\r\n' || echo "unknown")
  elif command -v powershell.exe >/dev/null 2>&1; then
    hostname=$(powershell.exe -Command "hostname" 2>/dev/null | tr -d '\r\n' || echo "unknown")
  elif [[ -f /proc/sys/kernel/hostname ]]; then
    # Fallback to Linux hostname if Windows methods fail
    hostname=$(cat /proc/sys/kernel/hostname 2>/dev/null || echo "unknown")
  fi

  echo "$hostname"
}

# --- System health monitoring ---
get_memory_usage_percentage() {
  if [[ -f /proc/meminfo ]]; then
    local mem_total mem_available
    mem_total=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
    mem_available=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)

    if [[ -z "$mem_available" ]]; then
      # Fallback calculation for older systems
      local mem_free mem_buffers mem_cached
      mem_free=$(awk '/MemFree:/ {print $2}' /proc/meminfo)
      mem_buffers=$(awk '/Buffers:/ {print $2}' /proc/meminfo)
      mem_cached=$(awk '/^Cached:/ {print $2}' /proc/meminfo)
      mem_available=$((mem_free + mem_buffers + mem_cached))
    fi

    local mem_used=$((mem_total - mem_available))
    echo "scale=1; $mem_used * 100 / $mem_total" | bc -l 2>/dev/null || echo "0"
  else
    echo "0"
  fi
}

get_disk_usage_percentage() {
  local target_path="${1:-$HOME}"

  if command -v df >/dev/null 2>&1; then
    df -h "$target_path" 2>/dev/null | awk 'NR==2 {gsub(/%/, "", $5); print $5}' || echo "0"
  else
    echo "0"
  fi
}

# --- Enhanced distribution information ---
get_distribution_info() {
  local format="${1:-json}" # json, text, version-only

  local dist_info=()

  # Distribution identification
  local distro_id distro_name distro_version distro_codename
  distro_id=$(get_distribution_id)
  distro_name=$(get_distribution_name)
  distro_version=$(get_distribution_version)
  distro_codename=$(get_distribution_codename)

  # LTS status for Ubuntu
  local is_lts="false"
  if [[ "$distro_id" == "ubuntu" ]]; then
    is_lts=$(is_ubuntu_lts "$distro_version")
  fi

  case "$format" in
  "json")
    cat <<EOF
{
  "distribution": {
    "id": "$distro_id",
    "name": "$distro_name",
    "version": "$distro_version",
    "codename": "$distro_codename"
  },
  "is_lts": $is_lts
}
EOF
    ;;
  "text")
    echo "Distribution: $distro_name $distro_version ($distro_codename)"
    [[ "$distro_id" == "ubuntu" ]] && echo "Ubuntu LTS: $is_lts"
    ;;
  "version-only")
    echo "$distro_version"
    ;;
  esac
}
