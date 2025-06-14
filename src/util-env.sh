#!/usr/bin/env bash
# Utility: util-env.sh
# Description: Environment detection and system info utilities
# Last Updated: 2025-06-14
# Version: 1.0.1

set -euo pipefail

# Load guard to prevent multiple sourcing
if [[ -n "${UTIL_ENV_SH_LOADED:-}" ]]; then
  return 0
fi
readonly UTIL_ENV_SH_LOADED=1

# ------------------------------------------------------------------------------
# Global Constants and Variables
# ------------------------------------------------------------------------------

# Initialize common global variables with safe conditional pattern
_init_global_vars() {
  # Script directory (only declare once globally)
  if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    readonly SCRIPT_DIR
  fi

  # Version & timestamp (only declare once globally)
  if [[ -z "${VERSION:-}" ]]; then
    VERSION="1.0.1"
    readonly VERSION
  fi

  if [[ -z "${LAST_UPDATED:-}" ]]; then
    LAST_UPDATED="2025-06-14"
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
}

# Initialize global variables
_init_global_vars

# ------------------------------------------------------------------------------
# Dependencies: Load required utilities
# ------------------------------------------------------------------------------

_source_utility() {
  local utility_name="$1"
  local utility_path="${SCRIPT_DIR}/${utility_name}"

  if [[ -z "${UTIL_LOG_SH_LOADED:-}" && -f "$utility_path" ]]; then
    source "$utility_path" || {
      echo "[ERROR] Failed to source $utility_name" >&2
      exit 1
    }
  fi
}

# Source logging utilities if available
_source_utility "util-log.sh"

# ------------------------------------------------------------------------------
# Environment Type Constants
# ------------------------------------------------------------------------------

# Environment types with safe declaration guard
_init_environment_constants() {
  if [[ -z "${ENV_WSL:-}" ]]; then
    readonly ENV_WSL="WSL2"
  fi

  if [[ -z "${ENV_DESKTOP:-}" ]]; then
    readonly ENV_DESKTOP="DESKTOP"
  fi

  if [[ -z "${ENV_HEADLESS:-}" ]]; then
    readonly ENV_HEADLESS="HEADLESS"
  fi
}

# Initialize environment constants
_init_environment_constants

# ------------------------------------------------------------------------------
# Resource Monitoring Configuration
# ------------------------------------------------------------------------------

# Resource monitoring with caching and comprehensive metrics
declare -A RESOURCE_CACHE=()
declare -A CACHE_TIMESTAMPS=()
readonly CACHE_TTL=300 # 5 minutes

# ------------------------------------------------------------------------------
# Core Environment Detection Functions
# ------------------------------------------------------------------------------

# Enhanced environment detection with multiple validation methods
detect_environment() {
  local env_type=""
  local confidence_score=0

  # WSL Detection with multiple methods
  if _detect_wsl_environment; then
    env_type="$ENV_WSL"
    confidence_score=90
  # Desktop detection with comprehensive checks
  elif _detect_desktop_environment; then
    env_type="$ENV_DESKTOP"
    confidence_score=85
  # Headless as fallback
  else
    env_type="$ENV_HEADLESS"
    confidence_score=70
  fi

  # Validate detection confidence
  if [[ $confidence_score -lt 80 ]] && [[ "${DEBUG_LOGGING:-false}" == "true" ]]; then
    if command -v log_debug >/dev/null 2>&1; then
      log_debug "Environment detection confidence low ($confidence_score%): $env_type"
    fi
  fi

  echo "$env_type"
}

# Internal WSL detection function
_detect_wsl_environment() {
  [[ -f "/proc/version" ]] && grep -qi "microsoft" "/proc/version" 2>/dev/null
}

# Internal desktop environment detection function
_detect_desktop_environment() {
  [[ -n "${DISPLAY:-}" ]] || [[ -n "${WAYLAND_DISPLAY:-}" ]] || [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]
}

# --- Advanced WSL Integration and Windows Host Detection ---
get_wsl_detailed_info() {
  if [[ "$(get_wsl_version)" == "0" ]]; then
    echo "{\"wsl_version\": \"0\", \"error\": \"Not running in WSL\"}"
    return 1
  fi

  local wsl_info=()

  # WSL version detection
  local wsl_version
  wsl_version=$(get_wsl_version)
  wsl_info+=("\"wsl_version\": \"$wsl_version\"")

  # Distribution information
  local distro_name="${WSL_DISTRO_NAME:-unknown}"
  wsl_info+=("\"distro_name\": \"$distro_name\"")

  # Windows host information
  local windows_info
  windows_info=$(get_windows_host_info)
  wsl_info+=("\"windows_host\": $windows_info")

  # WSL configuration
  local wsl_config
  wsl_config=$(get_wsl_configuration)
  wsl_info+=("\"configuration\": $wsl_config")

  # Network configuration
  local network_info
  network_info=$(get_wsl_network_info)
  wsl_info+=("\"network\": $network_info")

  # Interop capabilities
  local interop_info
  interop_info=$(get_wsl_interop_info)
  wsl_info+=("\"interop\": $interop_info")

  # Combine into JSON
  local IFS=','
  echo "{${wsl_info[*]}}"
}

get_windows_host_info() {
  local host_info=()

  # Windows hostname
  local hostname
  hostname=$(get_windows_hostname)
  host_info+=("\"hostname\": \"$hostname\"")

  # Windows version
  local windows_version
  if command -v cmd.exe >/dev/null 2>&1; then
    windows_version=$(cmd.exe /c "ver" 2>/dev/null | tr -d '\r\n' | sed 's/.*\[\(.*\)\].*/\1/' || echo "unknown")
  else
    windows_version="unknown"
  fi
  host_info+=("\"version\": \"$windows_version\"")

  # Windows user information
  local windows_user
  if command -v cmd.exe >/dev/null 2>&1; then
    windows_user=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' || echo "unknown")
  else
    windows_user="unknown"
  fi
  host_info+=("\"user\": \"$windows_user\"")

  # Available Windows drives
  local drives=()
  if command -v cmd.exe >/dev/null 2>&1; then
    while IFS= read -r drive; do
      [[ -n "$drive" ]] && drives+=("\"$drive\"")
    done < <(cmd.exe /c "wmic logicaldisk get caption" 2>/dev/null | grep -E "^[A-Z]:" | awk '{print $1}' | tr -d '\r')
  fi

  local drives_json
  drives_json="[$(
    IFS=','
    echo "${drives[*]}"
  )]"
  host_info+=("\"available_drives\": $drives_json")

  # Docker Desktop detection
  local docker_desktop="false"
  if [[ -f "/mnt/c/Program Files/Docker/Docker/Docker Desktop.exe" ]] ||
    [[ -f "/mnt/c/Users/$windows_user/AppData/Local/Docker/Docker Desktop.exe" ]]; then
    docker_desktop="true"
  fi
  host_info+=("\"docker_desktop_installed\": $docker_desktop")

  # VS Code installations
  local vscode_installations=()
  if [[ -f "/mnt/c/Program Files/Microsoft VS Code/bin/code.cmd" ]]; then
    vscode_installations+=("\"stable\"")
  fi
  if [[ -f "/mnt/c/Program Files/Microsoft VS Code Insiders/bin/code-insiders.cmd" ]]; then
    vscode_installations+=("\"insiders\"")
  fi

  local vscode_json
  vscode_json="[$(
    IFS=','
    echo "${vscode_installations[*]}"
  )]"
  host_info+=("\"vscode_installations\": $vscode_json")

  local IFS=','
  echo "{${host_info[*]}}"
}

get_wsl_configuration() {
  local config_info=()

  # Systemd status
  local systemd_enabled="false"
  if [[ -f /etc/wsl.conf ]] && grep -q "systemd=true" /etc/wsl.conf; then
    systemd_enabled="true"
  fi
  config_info+=("\"systemd_enabled\": $systemd_enabled")

  # Systemd running status
  local systemd_running="false"
  if is_systemd_running; then
    systemd_running="true"
  fi
  config_info+=("\"systemd_running\": $systemd_running")

  # Mount configuration
  local mount_config="{}"
  if [[ -f /etc/wsl.conf ]]; then
    local mount_enabled="true"
    local mount_root="/"

    if grep -q "enabled.*=.*false" /etc/wsl.conf; then
      mount_enabled="false"
    fi

    local root_line
    root_line=$(grep "^root" /etc/wsl.conf 2>/dev/null || echo "")
    if [[ -n "$root_line" ]]; then
      mount_root="${root_line#*=}"
      mount_root="${mount_root// /}"
    fi

    mount_config="{\"enabled\": $mount_enabled, \"root\": \"$mount_root\"}"
  fi
  config_info+=("\"mount\": $mount_config")

  # Network configuration
  local network_config="{}"
  if [[ -f /etc/wsl.conf ]]; then
    local generate_hosts="true"
    local generate_resolv_conf="true"

    if grep -q "generateHosts.*=.*false" /etc/wsl.conf; then
      generate_hosts="false"
    fi
    if grep -q "generateResolvConf.*=.*false" /etc/wsl.conf; then
      generate_resolv_conf="false"
    fi

    network_config="{\"generateHosts\": $generate_hosts, \"generateResolvConf\": $generate_resolv_conf}"
  fi
  config_info+=("\"network\": $network_config")

  local IFS=','
  echo "{${config_info[*]}}"
}

get_wsl_network_info() {
  local network_info=()

  # WSL IP address
  local wsl_ip
  wsl_ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || echo "unknown")
  network_info+=("\"wsl_ip\": \"$wsl_ip\"")

  # Windows host IP (from WSL perspective)
  local host_ip
  host_ip=$(ip route | grep default | awk '{print $3}' | head -1 || echo "unknown")
  network_info+=("\"windows_host_ip\": \"$host_ip\"")

  # DNS servers
  local dns_servers=()
  if [[ -f /etc/resolv.conf ]]; then
    while IFS= read -r dns; do
      dns_servers+=("\"$dns\"")
    done < <(grep "^nameserver" /etc/resolv.conf | awk '{print $2}')
  fi

  local dns_json
  dns_json="[$(
    IFS=','
    echo "${dns_servers[*]}"
  )]"
  network_info+=("\"dns_servers\": $dns_json")

  # Network interfaces
  local interfaces=()
  while IFS= read -r interface; do
    interfaces+=("\"$interface\"")
  done < <(ip -o link show | awk -F': ' '{print $2}' | grep -v lo)

  local interfaces_json
  interfaces_json="[$(
    IFS=','
    echo "${interfaces[*]}"
  )]"
  network_info+=("\"interfaces\": $interfaces_json")

  local IFS=','
  echo "{${network_info[*]}}"
}

get_wsl_interop_info() {
  local interop_info=()

  # Interop enabled status
  local interop_enabled="false"
  if [[ -n "${WSL_INTEROP:-}" ]] || command -v cmd.exe >/dev/null 2>&1; then
    interop_enabled="true"
  fi
  interop_info+=("\"enabled\": $interop_enabled")

  # Windows PATH integration
  local windows_path_integrated="false"
  if echo "$PATH" | grep -q "/mnt/c/"; then
    windows_path_integrated="true"
  fi
  interop_info+=("\"windows_path_integrated\": $windows_path_integrated")

  # Available Windows commands
  local windows_commands=()
  local common_windows_commands=("cmd.exe" "powershell.exe" "notepad.exe" "explorer.exe")

  for cmd in "${common_windows_commands[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      windows_commands+=("\"$cmd\"")
    fi
  done

  local commands_json
  commands_json="[$(
    IFS=','
    echo "${windows_commands[*]}"
  )]"
  interop_info+=("\"available_commands\": $commands_json")

  local IFS=','
  echo "{${interop_info[*]}}"
}

# --- Performance Monitoring and System Health Diagnostics ---
get_system_health() {
  local check_type="${1:-basic}" # basic, detailed, performance
  local format="${2:-json}"      # json, text, summary

  case "$check_type" in
  "basic")
    get_basic_system_health "$format"
    ;;
  "detailed")
    get_detailed_system_health "$format"
    ;;
  "performance")
    get_performance_metrics "$format"
    ;;
  *)
    echo "Invalid check type: $check_type" >&2
    return 1
    ;;
  esac
}

get_basic_system_health() {
  local format="$1"
  local health_data=()

  # System load
  local load_avg
  if [[ -f /proc/loadavg ]]; then
    load_avg=$(cut -d' ' -f1-3 /proc/loadavg)
  else
    load_avg="unknown"
  fi
  health_data+=("\"load_average\": \"$load_avg\"")

  # Memory usage
  local memory_usage
  memory_usage=$(get_memory_usage_percentage)
  health_data+=("\"memory_usage_percent\": $memory_usage")

  # Disk usage - pass HOME as default argument
  local disk_usage
  disk_usage=$(get_disk_usage_percentage "$HOME")
  health_data+=("\"disk_usage_percent\": $disk_usage")

  # System uptime
  local uptime_seconds
  if [[ -f /proc/uptime ]]; then
    uptime_seconds=$(cut -d' ' -f1 /proc/uptime | cut -d'.' -f1)
  else
    uptime_seconds="0"
  fi
  health_data+=("\"uptime_seconds\": $uptime_seconds")

  # Process count
  local process_count
  process_count=$(ps aux | wc -l)
  health_data+=("\"process_count\": $process_count")

  # System health score (0-100)
  local health_score
  health_score=$(calculate_system_health_score "$memory_usage" "$disk_usage" "$load_avg")
  health_data+=("\"health_score\": $health_score")

  case "$format" in
  "json")
    local IFS=','
    echo "{${health_data[*]}}"
    ;;
  "text")
    echo "System Health Summary:"
    echo "  Load Average: $load_avg"
    echo "  Memory Usage: ${memory_usage}%"
    echo "  Disk Usage: ${disk_usage}%"
    echo "  Uptime: $(format_uptime "$uptime_seconds")"
    echo "  Processes: $process_count"
    echo "  Health Score: ${health_score}/100"
    ;;
  "summary")
    echo "$health_score"
    ;;
  esac
}

get_detailed_system_health() {
  local format="$1"
  local detailed_data=()

  # Get basic health data
  local basic_health
  basic_health=$(get_basic_system_health "json")
  detailed_data+=("\"basic\": $basic_health")

  # CPU information
  local cpu_info
  cpu_info=$(get_cpu_information)
  detailed_data+=("\"cpu\": $cpu_info")

  # Memory breakdown
  local memory_info
  memory_info=$(get_memory_breakdown)
  detailed_data+=("\"memory\": $memory_info")

  # Disk information
  local disk_info
  disk_info=$(get_disk_information)
  detailed_data+=("\"storage\": $disk_info")

  # Network status - pass format argument
  local network_info
  network_info=$(get_network_status "$format")
  detailed_data+=("\"network\": $network_info")

  # System services status
  local services_info
  services_info=$(get_critical_services_status "json")
  detailed_data+=("\"services\": $services_info")

  case "$format" in
  "json")
    local IFS=','
    echo "{${detailed_data[*]}}"
    ;;
  "text")
    echo "Detailed System Health Report:"
    echo "================================"
    get_basic_system_health "text"
    echo ""
    echo "CPU Information:"
    get_cpu_information "text"
    echo ""
    echo "Memory Breakdown:"
    get_memory_breakdown "text"
    echo ""
    echo "Storage Information:"
    get_disk_information "text"
    ;;
  esac
}

calculate_system_health_score() {
  local memory_usage="$1"
  local disk_usage="$2"
  local load_avg="$3"

  local score=100

  # Memory usage impact (0-40 points deduction)
  local memory_penalty
  memory_penalty=$(echo "scale=0; $memory_usage * 0.4" | bc -l 2>/dev/null || echo "0")
  score=$((score - memory_penalty))

  # Disk usage impact (0-30 points deduction)
  local disk_penalty
  disk_penalty=$(echo "scale=0; $disk_usage * 0.3" | bc -l 2>/dev/null || echo "0")
  score=$((score - disk_penalty))

  # Load average impact (0-30 points deduction)
  local load_1min
  load_1min=$(echo "$load_avg" | cut -d' ' -f1)
  local cpu_cores
  cpu_cores=$(nproc 2>/dev/null || echo "1")

  local load_ratio
  load_ratio=$(echo "scale=2; $load_1min / $cpu_cores" | bc -l 2>/dev/null || echo "0")

  if (($(echo "$load_ratio > 1.0" | bc -l 2>/dev/null || echo "0"))); then
    local load_penalty
    load_penalty=$(echo "scale=0; ($load_ratio - 1) * 30" | bc -l 2>/dev/null || echo "0")
    score=$((score - load_penalty))
  fi

  # Ensure score doesn't go below 0
  [[ $score -lt 0 ]] && score=0

  echo "$score"
}

get_cpu_information() {
  local format="${1:-json}"
  local cpu_data=()

  # CPU model and count
  local cpu_model cpu_cores cpu_threads
  if [[ -f /proc/cpuinfo ]]; then
    cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d':' -f2 | sed 's/^ *//')
    cpu_cores=$(grep "cpu cores" /proc/cpuinfo | head -1 | cut -d':' -f2 | sed 's/^ *//')
    cpu_threads=$(grep "processor" /proc/cpuinfo | wc -l)
  else
    cpu_model="unknown"
    cpu_cores="unknown"
    cpu_threads="unknown"
  fi

  # CPU usage
  local cpu_usage
  cpu_usage=$(get_system_resources "cpu_usage")

  # CPU frequency
  local cpu_freq="unknown"
  if [[ -f /proc/cpuinfo ]]; then
    cpu_freq=$(grep "cpu MHz" /proc/cpuinfo | head -1 | cut -d':' -f2 | sed 's/^ *//' | cut -d'.' -f1)
    [[ -n "$cpu_freq" ]] && cpu_freq="${cpu_freq} MHz"
  fi

  case "$format" in
  "json")
    cpu_data+=("\"model\": \"$cpu_model\"")
    cpu_data+=("\"cores\": \"$cpu_cores\"")
    cpu_data+=("\"threads\": \"$cpu_threads\"")
    cpu_data+=("\"usage_percent\": \"$cpu_usage\"")
    cpu_data+=("\"frequency\": \"$cpu_freq\"")

    local IFS=','
    echo "{${cpu_data[*]}}"
    ;;
  "text")
    echo "  Model: $cpu_model"
    echo "  Cores: $cpu_cores"
    echo "  Threads: $cpu_threads"
    echo "  Usage: ${cpu_usage}%"
    echo "  Frequency: $cpu_freq"
    ;;
  esac
}

get_memory_breakdown() {
  local format="${1:-json}"

  if [[ ! -f /proc/meminfo ]]; then
    echo "{\"error\": \"Memory information not available\"}"
    return 1
  fi

  local mem_total mem_free mem_available mem_buffers mem_cached mem_swap_total mem_swap_free
  mem_total=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
  mem_free=$(awk '/MemFree:/ {print $2}' /proc/meminfo)
  mem_available=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
  mem_buffers=$(awk '/Buffers:/ {print $2}' /proc/meminfo)
  mem_cached=$(awk '/^Cached:/ {print $2}' /proc/meminfo)
  mem_swap_total=$(awk '/SwapTotal:/ {print $2}' /proc/meminfo)
  mem_swap_free=$(awk '/SwapFree:/ {print $2}' /proc/meminfo)

  # Convert to MB for readability
  local mem_total_mb mem_free_mb mem_available_mb mem_buffers_mb mem_cached_mb
  local mem_swap_total_mb mem_swap_free_mb

  mem_total_mb=$((mem_total / 1024))
  mem_free_mb=$((mem_free / 1024))
  mem_available_mb=${mem_available:=0}
  mem_available_mb=$((mem_available_mb / 1024))
  mem_buffers_mb=$((mem_buffers / 1024))
  mem_cached_mb=$((mem_cached / 1024))
  mem_swap_total_mb=$((mem_swap_total / 1024))
  mem_swap_free_mb=$((mem_swap_free / 1024))

  local mem_used_mb=$((mem_total_mb - mem_available_mb))
  local mem_swap_used_mb=$((mem_swap_total_mb - mem_swap_free_mb))

  case "$format" in
  "json")
    cat <<EOF
{
  "total_mb": $mem_total_mb,
  "used_mb": $mem_used_mb,
  "free_mb": $mem_free_mb,
  "available_mb": $mem_available_mb,
  "buffers_mb": $mem_buffers_mb,
  "cached_mb": $mem_cached_mb,
  "swap": {
    "total_mb": $mem_swap_total_mb,
    "used_mb": $mem_swap_used_mb,
    "free_mb": $mem_swap_free_mb
  }
}
EOF
    ;;
  "text")
    echo "  Total: ${mem_total_mb}MB"
    echo "  Used: ${mem_used_mb}MB"
    echo "  Available: ${mem_available_mb}MB"
    echo "  Buffers: ${mem_buffers_mb}MB"
    echo "  Cached: ${mem_cached_mb}MB"
    echo "  Swap Total: ${mem_swap_total_mb}MB"
    echo "  Swap Used: ${mem_swap_used_mb}MB"
    ;;
  esac
}

get_disk_information() {
  local format="${1:-json}"
  # Remove unused disk_data array
  local filesystems=()

  while IFS= read -r line; do
    local filesystem size used avail use_percent mount_point
    read -r filesystem size used avail use_percent mount_point <<<"$line"

    # Skip special filesystems
    case "$mount_point" in
    /proc | /sys | /dev | /run | /tmp) continue ;;
    /snap/*) continue ;;
    esac

    # Skip if mount point is empty or device is tmpfs
    [[ -z "$mount_point" ]] && continue
    [[ "$filesystem" == "tmpfs" ]] && continue

    local fs_info="{\"device\": \"$filesystem\", \"mount_point\": \"$mount_point\", \"size\": \"$size\", \"used\": \"$used\", \"available\": \"$avail\", \"usage_percent\": \"${use_percent%\%}\"}"
    filesystems+=("$fs_info")

  done < <(df -h 2>/dev/null | tail -n +2)

  case "$format" in
  "json")
    local IFS=','
    echo "{\"filesystems\": [${filesystems[*]}]}"
    ;;
  "text")
    echo "  Mounted Filesystems:"
    df -h 2>/dev/null | grep -E '^/dev|^[A-Z]:' | while read -r line; do
      echo "    $line"
    done
    ;;
  esac
}

# Fix function that references arguments but none are passed
get_network_status() {
  # Accepts an optional format argument: json (default) or text.
  local format="${1:-json}"

  # Network interfaces
  local interfaces=()
  for netdev in /sys/class/net/*; do
    local interface
    interface=$(basename "$netdev")
    [[ "$interface" == "lo" ]] && continue
    local state
    state=$(cat "$netdev/operstate" 2>/dev/null || echo "unknown")
    interfaces+=("{\"name\": \"$interface\", \"state\": \"$state\"}")
  done

  # Internet connectivity test
  local internet_status="false"
  if timeout 5 ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    internet_status="true"
  fi

  # DNS resolution test
  local dns_status="false"
  if timeout 5 nslookup google.com >/dev/null 2>&1; then
    dns_status="true"
  fi

  case "$format" in
  "json")
    local interfaces_json
    local IFS=','
    interfaces_json="[${interfaces[*]}]"

    cat <<EOF
{
  "interfaces": $interfaces_json,
  "internet_connectivity": $internet_status,
  "dns_resolution": $dns_status
}
EOF
    ;;
  "text")
    echo "  Network Interfaces:"
    for interface_info in "${interfaces[@]}"; do
      local name state
      name=$(echo "$interface_info" | grep -o '"name": "[^"]*"' | cut -d'"' -f4)
      state=$(echo "$interface_info" | grep -o '"state": "[^"]*"' | cut -d'"' -f4)
      echo "    $name: $state"
    done
    echo "  Internet: $internet_status"
    echo "  DNS: $dns_status"
    ;;
  esac
}

get_critical_services_status() {
  local format="${1:-json}"
  local services=("ssh" "systemd-resolved" "networkd" "cron")
  local service_statuses=()

  # Only check if systemd is available
  if ! command -v systemctl >/dev/null 2>&1; then
    case "$format" in
    "json") echo "{\"error\": \"systemctl not available\"}" ;;
    "text") echo "  Service status checking not available (no systemctl)" ;;
    esac
    return 0
  fi

  for service in "${services[@]}"; do
    local status="unknown"
    if systemctl is-active --quiet "$service" 2>/dev/null; then
      status="active"
    elif systemctl is-enabled --quiet "$service" 2>/dev/null; then
      status="inactive"
    else
      status="disabled"
    fi

    service_statuses+=("{\"name\": \"$service\", \"status\": \"$status\"}")
  done

  case "$format" in
  "json")
    local IFS=','
    echo "{\"services\": [${service_statuses[*]}]}"
    ;;
  "text")
    echo "  Critical Services:"
    for service_info in "${service_statuses[@]}"; do
      local name status
      name=$(echo "$service_info" | grep -o '"name": "[^"]*"' | cut -d'"' -f4)
      status=$(echo "$service_info" | grep -o '"status": "[^"]*"' | cut -d'"' -f4)
      echo "    $name: $status"
    done
    ;;
  esac
}

format_uptime() {
  local seconds="$1"
  local days hours minutes

  days=$((seconds / 86400))
  hours=$(((seconds % 86400) / 3600))
  minutes=$(((seconds % 3600) / 60))

  if [[ $days -gt 0 ]]; then
    echo "${days}d ${hours}h ${minutes}m"
  elif [[ $hours -gt 0 ]]; then
    echo "${hours}h ${minutes}m"
  else
    echo "${minutes}m"
  fi
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

  # Method 3: Desktop-specific processes - use grep -c instead of grep | wc -l
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

  # Ubuntu-specific information
  local ubuntu_info
  ubuntu_info=$(get_ubuntu_specific_info)

  # LTS status
  local is_lts
  is_lts=$(is_ubuntu_lts "$distro_version")

  # Support status
  local support_status
  support_status=$(get_ubuntu_support_status "$distro_version")

  # Package manager information
  local package_managers
  package_managers=$(get_available_package_managers)

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
  "ubuntu": $ubuntu_info,
  "is_lts": $is_lts,
  "support_status": "$support_status",
  "package_managers": $package_managers
}
EOF
    ;;
  "text")
    echo "Distribution: $distro_name $distro_version ($distro_codename)"
    echo "Ubuntu LTS: $is_lts"
    echo "Support Status: $support_status"
    ;;
  "version-only")
    echo "$distro_version"
    ;;
  esac
}

get_ubuntu_specific_info() {
  local ubuntu_info=()

  # Check if this is actually Ubuntu or derivative
  local is_ubuntu="false"
  local ubuntu_derivative=""

  if [[ -f /etc/os-release ]]; then
    local id_like
    id_like=$(grep "^ID_LIKE=" /etc/os-release | cut -d'=' -f2 | tr -d '"')

    if grep -q "^ID=ubuntu" /etc/os-release; then
      is_ubuntu="true"
    elif echo "$id_like" | grep -q "ubuntu"; then
      is_ubuntu="false"
      ubuntu_derivative=$(grep "^ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"')
    fi
  fi

  ubuntu_info+=("\"is_ubuntu\": $is_ubuntu")
  ubuntu_info+=("\"derivative\": \"$ubuntu_derivative\"")

  # Ubuntu version classification
  local version
  version=$(get_distribution_version)
  local version_class
  version_class=$(classify_ubuntu_version "$version")
  ubuntu_info+=("\"version_class\": \"$version_class\"")

  # Architecture
  local architecture
  architecture=$(dpkg --print-architecture 2>/dev/null || uname -m)
  ubuntu_info+=("\"architecture\": \"$architecture\"")

  # Kernel information
  local kernel_version
  kernel_version=$(uname -r)
  ubuntu_info+=("\"kernel_version\": \"$kernel_version\"")

  local IFS=','
  echo "{${ubuntu_info[*]}}"
}

classify_ubuntu_version() {
  local version="$1"

  case "$version" in
  "24.04" | "24.10") echo "current" ;;
  "22.04" | "22.10") echo "recent" ;;
  "20.04" | "20.10") echo "supported" ;;
  "18.04" | "18.10") echo "legacy" ;;
  *) echo "unknown" ;;
  esac
}

get_available_package_managers() {
  local managers=()

  # Check for various package managers
  if command -v apt >/dev/null 2>&1; then
    managers+=("\"apt\"")
  fi

  if command -v snap >/dev/null 2>&1; then
    managers+=("\"snap\"")
  fi

  if command -v flatpak >/dev/null 2>&1; then
    managers+=("\"flatpak\"")
  fi

  if command -v dpkg >/dev/null 2>&1; then
    managers+=("\"dpkg\"")
  fi

  if command -v pip >/dev/null 2>&1 || command -v pip3 >/dev/null 2>&1; then
    managers+=("\"pip\"")
  fi

  if command -v npm >/dev/null 2>&1; then
    managers+=("\"npm\"")
  fi

  if command -v brew >/dev/null 2>&1; then
    managers+=("\"homebrew\"")
  fi

  local IFS=','
  echo "[${managers[*]}]"
}

# Enhanced Ubuntu version function for backward compatibility
get_ubuntu_version() {
  local dist_info
  dist_info=$(get_distribution_info "version-only")

  # Handle non-Ubuntu distributions
  local distro_id
  distro_id=$(get_distribution_id)

  if [[ "$distro_id" != "ubuntu" ]]; then
    echo "non-ubuntu"
  elif [[ "$dist_info" == "unknown" ]]; then
    echo "unknown"
  else
    echo "$dist_info"
  fi
}
