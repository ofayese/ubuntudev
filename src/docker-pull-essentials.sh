#!/usr/bin/env bash
# docker-pull-essentials.sh
# Pulls essential Docker images for development and AI/ML workloads.
# Version: 2.0.0
# Last updated: 2025-06-13
#
# Usage:
#   ./docker-pull-essentials.sh [OPTIONS]
#
# Options:
#   --config FILE     Specify configuration file (default: docker-pull-config.yaml)
#   --dry-run         Show what would be pulled without actually pulling
#   --parallel NUM    Number of parallel pulls (default: 4)
#   --retry NUM       Number of retry attempts per image (default: 2)
#   --timeout SEC     Timeout for each pull in seconds (default: 300)
#   --skip-ai         Skip AI/ML model pulls
#   --skip-windows    Skip Windows-specific images
#   --log-file FILE   Log output to file (default: docker-pull.log)
#   --resume          Resume from a previous interrupted operation
#   --advanced-cleanup  Run advanced Docker cleanup with volume management
#   --cleanup-volumes   Run Docker volume cleanup
#   --volume-status     Show Docker volume management status and configuration
#   --help            Show this help message

set -euo pipefail

# Script information
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
readonly SCRIPT_VERSION="2.0.0"
readonly LOG_PREFIX="[${SCRIPT_NAME}]"

# Default configuration
readonly DEFAULT_CONFIG_FILE="docker-pull-config.yaml"
readonly DEFAULT_TIMEOUT=300
readonly DEFAULT_RETRIES=2
readonly DEFAULT_PARALLEL=4
readonly DEFAULT_LOG_FILE="docker-pull.log"
readonly DISK_CHECK_INTERVAL=30
readonly MIN_FREE_SPACE_GB=2
readonly CLEANUP_THRESHOLD_PERCENT=90

# Configuration variables
CONFIG_FILE="${DEFAULT_CONFIG_FILE}"
DRY_RUN=false
SKIP_AI=false
SKIP_WINDOWS=false
RESUME_MODE=false
TIMEOUT="${DOCKER_PULL_TIMEOUT:-${DEFAULT_TIMEOUT}}"
RETRIES="${DOCKER_PULL_RETRIES:-${DEFAULT_RETRIES}}"
PARALLEL="${DOCKER_PULL_PARALLEL:-${DEFAULT_PARALLEL}}"
LOG_FILE="${DEFAULT_LOG_FILE}"
# shellcheck disable=SC2034  # These may be used in future security enhancements
ENABLE_CONTENT_TRUST="${DOCKER_CONTENT_TRUST:-false}"
# shellcheck disable=SC2034  # These may be used in future security enhancements
VULNERABILITY_SCAN="${ENABLE_VULN_SCAN:-false}"
ALLOWED_REGISTRIES="${DOCKER_ALLOWED_REGISTRIES:-}"

# Volume management configuration variables (can be overridden by config file)
VOLUME_MANAGEMENT_ENABLED=true
CACHE_MAX_SIZE_GB=50
CACHE_CLEANUP_THRESHOLD=85
AUTO_CLEANUP_ENABLED=true
ADVANCED_CLEANUP_ON_CRITICAL=true
SPACE_THRESHOLD_GB=5

# Counters for reporting (use file-based counters for thread safety)
declare -i TOTAL_IMAGES=0
declare -a FAILED_IMAGES=()

# Create temporary directory first
TEMP_DIR="$(mktemp -d)"
readonly TEMP_DIR

# Now define counters using the temp directory
readonly SUCCESSFUL_COUNTER="${TEMP_DIR}/successful_count"
readonly FAILED_COUNTER="${TEMP_DIR}/failed_count"

# Initialize counters
echo "0" >"${SUCCESSFUL_COUNTER}"
echo "0" >"${FAILED_COUNTER}"

# Thread-safe counter functions
increment_successful() {
  (
    flock -x 200
    local count
    count=$(cat "${SUCCESSFUL_COUNTER}")
    echo $((count + 1)) >"${SUCCESSFUL_COUNTER}"
  ) 200>"${SUCCESSFUL_COUNTER}.lock"
}

increment_failed() {
  (
    flock -x 200
    local count
    count=$(cat "${FAILED_COUNTER}")
    echo $((count + 1)) >"${FAILED_COUNTER}"
  ) 200>"${FAILED_COUNTER}.lock"
}

get_successful_count() {
  cat "${SUCCESSFUL_COUNTER}" 2>/dev/null || echo "0"
}

get_failed_count() {
  cat "${FAILED_COUNTER}" 2>/dev/null || echo "0"
}

# Temporary files for parallel processing
readonly PULL_QUEUE="${TEMP_DIR}/pull_queue"
readonly RESULTS_FILE="${TEMP_DIR}/results"
# shellcheck disable=SC2034  # Reserved for future state tracking
readonly STATE_FILE="${TEMP_DIR}/pull_state.json"
readonly COMPLETED_FILE="${TEMP_DIR}/completed_images"
readonly FAILED_FILE="${TEMP_DIR}/failed_images"
# shellcheck disable=SC2034  # Reserved for future security validation
readonly SECURITY_LOG="${TEMP_DIR}/security_validation.log"
readonly QUEUE_LOCK="${TEMP_DIR}/queue.lock"
readonly CONFIG_CACHE="${TEMP_DIR}/config.cache"
readonly PROGRESS_STATE="${TEMP_DIR}/progress.state"
readonly ERROR_CLASSIFICATION="${TEMP_DIR}/error_classes.log"

# Docker volume management
readonly DOCKER_PULL_CACHE_VOLUME="docker-pull-essentials-cache"
readonly DOCKER_PULL_STATE_VOLUME="docker-pull-essentials-state"

# Store start time for duration calculation
START_TIME="$(date +%s)"
readonly START_TIME

# Cleanup function
cleanup() {
  local exit_code=$?
  if [[ -d "${TEMP_DIR}" ]]; then
    # Don't remove temp directory if in resume mode and there were failures
    # shellcheck disable=SC2153
    if [[ "${RESUME_MODE}" == "true" ]] && [[ ${FAILED_PULLS} -gt 0 ]]; then
      log_info "Temporary files kept at ${TEMP_DIR} for resume capability"
    else
      rm -rf "${TEMP_DIR}"
    fi
  fi
  return ${exit_code}
}

# Set up cleanup trap
trap cleanup EXIT INT TERM

# Logging functions with timestamps
log_info() {
  local msg
  msg="$(date '+%Y-%m-%d %H:%M:%S') ${LOG_PREFIX} INFO: $*"
  echo "${msg}" | tee -a "${LOG_FILE}"
}

log_warn() {
  local msg
  msg="$(date '+%Y-%m-%d %H:%M:%S') ${LOG_PREFIX} WARN: $*"
  echo "${msg}" | tee -a "${LOG_FILE}" >&2
}

log_error() {
  local msg
  msg="$(date '+%Y-%m-%d %H:%M:%S') ${LOG_PREFIX} ERROR: $*"
  echo "${msg}" | tee -a "${LOG_FILE}" >&2
}

log_success() {
  local msg
  msg="$(date '+%Y-%m-%d %H:%M:%S') ${LOG_PREFIX} SUCCESS: $*"
  echo "${msg}" | tee -a "${LOG_FILE}"
}

log_debug() {
  if [[ "${DEBUG:-false}" == "true" ]]; then
    local msg
    msg="$(date '+%Y-%m-%d %H:%M:%S') ${LOG_PREFIX} DEBUG: $*"
    echo "${msg}" | tee -a "${LOG_FILE}" >&2
  fi
}

# Error classification system
classify_error() {
  local error_msg="$1"
  local image="$2"
  local error_type="UNKNOWN"

  case "${error_msg}" in
  *"no space left on device"*)
    error_type="DISK_SPACE"
    ;;
  *"network"* | *"timeout"* | *"connection"*)
    error_type="NETWORK"
    ;;
  *"authentication"* | *"authorization"* | *"denied"*)
    error_type="AUTH"
    ;;
  *"not found"* | *"does not exist"*)
    error_type="NOT_FOUND"
    ;;
  *"manifest"* | *"digest"*)
    error_type="MANIFEST"
    ;;
  *"rate"* | *"limit"*)
    error_type="RATE_LIMIT"
    ;;
  *)
    error_type="UNKNOWN"
    ;;
  esac

  echo "$(date '+%Y-%m-%d %H:%M:%S'):${image}:${error_type}:${error_msg}" >>"${ERROR_CLASSIFICATION}"
  echo "${error_type}"
}

# Progress indicator with size awareness
show_progress() {
  local current="$1"
  local total="$2"
  local bytes_downloaded="${3:-0}"
  local total_bytes="${4:-0}"

  local percentage=$((current * 100 / total))
  local size_info=""

  if [[ "${total_bytes}" -gt 0 ]]; then
    local bytes_percentage=$((bytes_downloaded * 100 / total_bytes))
    local mb_downloaded=$((bytes_downloaded / 1024 / 1024))
    local mb_total=$((total_bytes / 1024 / 1024))
    size_info=" (${mb_downloaded}/${mb_total}MB - ${bytes_percentage}%)"
  fi

  # Calculate ETA
  local eta_info=""
  if [[ -f "${PROGRESS_STATE}" ]] && [[ "${current}" -gt 0 ]]; then
    local start_time
    start_time=$(head -n1 "${PROGRESS_STATE}" 2>/dev/null || echo "${START_TIME}")
    local current_time
    current_time=$(date +%s)
    local elapsed=$((current_time - start_time))

    if [[ "${elapsed}" -gt 0 ]] && [[ "${current}" -gt 0 ]]; then
      local rate=$((current * 1000 / elapsed)) # images per second * 1000
      local remaining=$((total - current))
      local eta_seconds=$((remaining * 1000 / rate))
      local eta_minutes=$((eta_seconds / 60))
      eta_info=" ETA: ${eta_minutes}m"
    fi
  fi

  printf "\r${LOG_PREFIX} Progress: [%3d%%] %d/%d images%s%s" \
    "${percentage}" "${current}" "${total}" "${size_info}" "${eta_info}"
}

# Check prerequisites
check_prerequisites() {
  log_info "Checking prerequisites..."

  # Check if running in WSL2 vs native Ubuntu
  if [[ -f /proc/version ]] && grep -qi microsoft /proc/version; then
    log_info "Detected WSL2 environment"
    export WSL_ENV=true
  else
    log_info "Detected native Linux environment"
    export WSL_ENV=false
  fi

  # Check Docker availability
  if ! command -v docker >/dev/null 2>&1; then
    log_error "Docker is not installed or not in PATH"
    exit 2
  fi

  # Check Docker daemon
  if ! docker info >/dev/null 2>&1; then
    log_error "Docker daemon is not running or not accessible"
    log_info "Try: sudo systemctl start docker"
    exit 2
  fi

  # Check Docker version
  local docker_version
  docker_version="$(docker --version | cut -d' ' -f3 | tr -d ',')"
  log_info "Docker version: ${docker_version}"

  # Check for YAML parser
  if ! command -v yq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
    log_warn "No YAML parser (yq or python3) found, configuration loading may be limited"
  fi

  # Check available disk space
  check_disk_space

  log_info "Prerequisites check completed"
}

# Disk space check function
check_disk_space() {
  local available_gb
  available_gb=$(get_available_disk)

  log_info "Available disk space: ${available_gb}GB"

  if [[ "${available_gb}" -lt "${MIN_FREE_SPACE_GB}" ]]; then
    log_error "Insufficient disk space: ${available_gb}GB available (minimum ${MIN_FREE_SPACE_GB}GB required)"
    exit 1
  elif [[ "${available_gb}" -lt $((MIN_FREE_SPACE_GB * 2)) ]]; then
    log_warn "Low disk space: ${available_gb}GB available. Cleanup recommended."
  fi
}

# Get available disk space in GB
get_available_disk() {
  local docker_dir="/var/lib/docker"
  local available

  if [[ ! -d "${docker_dir}" ]]; then
    docker_dir="/" # Fall back to root if docker dir not found
  fi

  available=$(df -BG "${docker_dir}" 2>/dev/null | awk 'NR==2 {gsub("G", "", $4); print $4}' || echo "0")
  echo "${available}"
}

# Enhanced cleanup functions with volume management
cleanup_partial_downloads() {
  log_info "Cleaning up partial downloads..."
  docker image prune -f --filter "dangling=true" >/dev/null 2>&1 || true
  docker builder prune -f >/dev/null 2>&1 || true

  # Also check for volume usage issues
  if ! monitor_volume_usage; then
    if [[ "${AUTO_CLEANUP_ENABLED}" == "true" ]]; then
      cleanup_docker_volumes
    fi
  fi

  log_info "Partial download cleanup completed"
}

cleanup_old_images() {
  log_info "Cleaning up old unused images..."
  docker image prune -f --filter "until=168h" >/dev/null 2>&1 || true

  # Clean up volumes if space is getting tight
  if ! monitor_volume_usage; then
    if [[ "${AUTO_CLEANUP_ENABLED}" == "true" ]]; then
      cleanup_docker_volumes
    fi
  fi

  log_info "Old image cleanup completed"
}

# Docker volume management functions
setup_docker_volumes() {
  # Check if volume management is enabled
  if [[ "${VOLUME_MANAGEMENT_ENABLED}" != "true" ]]; then
    log_debug "Volume management disabled in configuration"
    return 0
  fi

  log_debug "Setting up Docker volumes for caching and state management"
  log_debug "Cache volume: ${DOCKER_PULL_CACHE_VOLUME} (max size: ${CACHE_MAX_SIZE_GB}GB)"
  log_debug "State volume: ${DOCKER_PULL_STATE_VOLUME}"

  # Create cache volume for layer caching if it doesn't exist
  if ! docker volume inspect "${DOCKER_PULL_CACHE_VOLUME}" >/dev/null 2>&1; then
    log_info "Creating Docker cache volume: ${DOCKER_PULL_CACHE_VOLUME}"
    docker volume create "${DOCKER_PULL_CACHE_VOLUME}" \
      --label "purpose=docker-pull-cache" \
      --label "created-by=${SCRIPT_NAME}" \
      --label "version=${SCRIPT_VERSION}" \
      --label "max-size-gb=${CACHE_MAX_SIZE_GB}" >/dev/null
  fi

  # Create state volume for persistent state if it doesn't exist
  if ! docker volume inspect "${DOCKER_PULL_STATE_VOLUME}" >/dev/null 2>&1; then
    log_info "Creating Docker state volume: ${DOCKER_PULL_STATE_VOLUME}"
    docker volume create "${DOCKER_PULL_STATE_VOLUME}" \
      --label "purpose=docker-pull-state" \
      --label "created-by=${SCRIPT_NAME}" \
      --label "version=${SCRIPT_VERSION}" >/dev/null
  fi
}

# Get Docker volume usage information
get_volume_usage() {
  local volume_name="$1"
  if docker volume inspect "${volume_name}" >/dev/null 2>&1; then
    docker system df --format "table {{.Type}}\t{{.TotalCount}}\t{{.Size}}\t{{.Reclaimable}}" |
      grep -i "volumes" | awk '{print $4}' | sed 's/[()]//g' || echo "0%"
  else
    echo "N/A"
  fi
}

# Clean up unused Docker volumes
cleanup_docker_volumes() {
  log_info "Cleaning up unused Docker volumes..."

  # Get volume usage before cleanup
  local total_volumes_before
  total_volumes_before=$(docker volume ls -q | wc -l)

  # Prune unused volumes (but preserve our managed volumes)
  docker volume prune -f --filter "label!=created-by=${SCRIPT_NAME}" >/dev/null 2>&1 || true

  # Get volume usage after cleanup
  local total_volumes_after
  total_volumes_after=$(docker volume ls -q | wc -l)
  local cleaned_count=$((total_volumes_before - total_volumes_after))

  log_info "Volume cleanup completed: removed ${cleaned_count} unused volumes"

  # Show current volume usage for our managed volumes
  local cache_usage
  cache_usage=$(get_volume_usage "${DOCKER_PULL_CACHE_VOLUME}")
  local state_usage
  state_usage=$(get_volume_usage "${DOCKER_PULL_STATE_VOLUME}")

  log_debug "Cache volume usage: ${cache_usage}, State volume usage: ${state_usage}"
}

# Advanced Docker cleanup with volume awareness
advanced_docker_cleanup() {
  log_info "Performing advanced Docker cleanup with volume management..."

  # Stop any containers using our volumes (if any)
  docker ps -a --filter "volume=${DOCKER_PULL_CACHE_VOLUME}" --format "{{.ID}}" |
    xargs -r docker stop >/dev/null 2>&1 || true

  # Clean up build cache
  docker builder prune -f >/dev/null 2>&1 || true

  # Clean up unused networks
  docker network prune -f >/dev/null 2>&1 || true

  # Clean up unused volumes (preserving our managed ones)
  cleanup_docker_volumes

  # Clean up unused images with more aggressive filtering
  docker image prune -af --filter "until=72h" >/dev/null 2>&1 || true

  log_info "Advanced Docker cleanup completed"
}

# Monitor Docker volume usage
monitor_volume_usage() {
  local volume_data
  volume_data=$(docker system df --format "{{.TotalCount}},{{.Size}},{{.Reclaimable}}" 2>/dev/null | tail -n +4 | head -n1 || echo "0,0B,0B")

  local volume_size
  volume_size=$(echo "${volume_data}" | cut -d',' -f2)
  local reclaimable
  reclaimable=$(echo "${volume_data}" | cut -d',' -f3)

  log_debug "Docker volumes: Total=${volume_size}, Reclaimable=${reclaimable}"

  # Check if reclaimable space is significant (>5GB)
  local reclaimable_gb
  reclaimable_gb=$(echo "${reclaimable}" | sed 's/GB.*//' | sed 's/[^0-9.]//g' 2>/dev/null || echo "0")

  if [[ -n "${reclaimable_gb}" ]] && (($(echo "${reclaimable_gb} > 5" | bc -l 2>/dev/null || echo "0"))); then
    log_warn "Significant reclaimable Docker volume space detected: ${reclaimable}"
    return 1
  fi

  return 0
}

# Background disk monitoring function with pull synchronization
monitor_disk_space() {
  local monitor_pid=$$
  local last_check=0
  local monitoring_active="${TEMP_DIR}/disk_monitoring_active"

  # Signal that monitoring is active
  echo "1" >"${monitoring_active}"

  log_debug "Starting disk space monitoring (PID: ${monitor_pid})"

  while [[ -f "${monitoring_active}" ]] && kill -0 $monitor_pid 2>/dev/null; do
    local current_time
    current_time=$(date +%s)

    if [[ $((current_time - last_check)) -ge ${DISK_CHECK_INTERVAL} ]]; then
      local available_gb
      available_gb=$(get_available_disk)
      local usage_percent
      usage_percent=$(df /var/lib/docker 2>/dev/null | awk 'NR==2 {gsub(/%/, "", $5); print $5}' || echo "0")

      log_debug "Disk check: ${available_gb}GB available, ${usage_percent}% used"

      # Update disk monitoring state
      echo "${current_time}:${available_gb}:${usage_percent}" >"${TEMP_DIR}/disk_state"

      # Check volume usage periodically
      if ! monitor_volume_usage; then
        log_debug "Volume cleanup recommended due to high usage"
      fi

      if [[ ${available_gb} -lt ${SPACE_THRESHOLD_GB} ]]; then
        log_error "Critical: Low disk space detected: ${available_gb}GB available (threshold: ${SPACE_THRESHOLD_GB}GB)"
        echo "CRITICAL_DISK_SPACE" >"${TEMP_DIR}/stop_pulls"
        # Enhanced cleanup including volumes if enabled
        if [[ "${ADVANCED_CLEANUP_ON_CRITICAL}" == "true" ]]; then
          advanced_docker_cleanup
        else
          cleanup_partial_downloads
        fi
        # Don't kill immediately, let workers finish current pulls
        break
      elif [[ ${usage_percent} -gt ${CLEANUP_THRESHOLD_PERCENT} ]]; then
        log_warn "High disk usage detected: ${usage_percent}% used"
        # Only cleanup if no active pulls to avoid interference
        if [[ ! -f "${TEMP_DIR}/pull_active" ]]; then
          cleanup_old_images
        fi
      fi

      last_check=$current_time
    fi

    sleep 10
  done

  rm -f "${monitoring_active}" 2>/dev/null || true
}

# Configuration loading function with caching
load_configuration() {
  local config_file="$1"
  local config_hash
  config_hash=$(sha256sum "${config_file}" 2>/dev/null | cut -d' ' -f1 || echo "no-hash")
  local cached_config="${CONFIG_CACHE}.${config_hash}"

  if [[ ! -f "${config_file}" ]]; then
    log_error "Configuration file not found: ${config_file}"
    return 1
  fi

  # Check if we have a valid cached version
  if [[ -f "${cached_config}" ]] && [[ "${cached_config}" -nt "${config_file}" ]]; then
    log_info "Using cached configuration from: ${cached_config}"
    # shellcheck disable=SC1090  # Dynamic config file sourcing
    source "${cached_config}"
    return 0
  fi

  log_info "Loading configuration from: ${config_file}"

  # Prefer Python for YAML parsing as it's more reliable across systems
  if command -v python3 >/dev/null 2>&1; then
    if parse_yaml_config_python "${config_file}" "${cached_config}"; then
      # shellcheck disable=SC1090  # Dynamic config file sourcing
      source "${cached_config}"
      return 0
    fi
  # Fallback to yq if available (check for modern yq v4+ syntax support)
  elif command -v yq >/dev/null 2>&1 && yq eval --version >/dev/null 2>&1; then
    if parse_yaml_config_yq "${config_file}" "${cached_config}"; then
      # shellcheck disable=SC1090  # Dynamic config file sourcing
      source "${cached_config}"
      return 0
    fi
  else
    log_error "No YAML parser available (python3 preferred, or yq v4+)"
    return 1
  fi
}

# Parse YAML with yq and cache results
parse_yaml_config_yq() {
  local config_file="$1"
  local cache_file="$2"

  # Create cache file with exported variables
  {
    echo "# Cached configuration from ${config_file}"
    echo "# Generated on $(date)"
    echo ""

    # Get global settings
    echo "export TIMEOUT=$(yq eval '.settings.timeout // 300' "${config_file}")"
    echo "export RETRIES=$(yq eval '.settings.retries // 2' "${config_file}")"
    echo "export PARALLEL=$(yq eval '.settings.parallel // 4' "${config_file}")"
    echo "export SKIP_AI=$(yq eval '.settings.skip_ai // false' "${config_file}")"
    echo "export SKIP_WINDOWS=$(yq eval '.settings.skip_windows // false' "${config_file}")"

    # Check for environment-specific overrides
    if [[ "${WSL_ENV}" == "true" ]] && yq eval '.environments.wsl2 | length > 0' "${config_file}" >/dev/null 2>&1; then
      echo "# WSL2-specific overrides"
      echo "export PARALLEL=$(yq eval '.environments.wsl2.parallel // .settings.parallel' "${config_file}")"
      echo "export SKIP_WINDOWS=$(yq eval '.environments.wsl2.skip_windows // .settings.skip_windows' "${config_file}")"
    elif [[ "${WSL_ENV}" == "false" ]] && yq eval '.environments.native_linux | length > 0' "${config_file}" >/dev/null 2>&1; then
      echo "# Native Linux overrides"
      echo "export PARALLEL=$(yq eval '.environments.native_linux.parallel // .settings.parallel' "${config_file}")"
    fi
  } >"${cache_file}"

  return 0
}

# Parse YAML with Python
parse_yaml_config_python() {
  local config_file="$1"
  local cache_file="$2"

  # Python script to parse YAML
  local py_script
  py_script=$(
    cat <<'EOF'
import sys
import yaml

try:
    with open(sys.argv[1], 'r') as f:
        config = yaml.safe_load(f)
    
    # Output key settings as env vars
    settings = config.get('settings', {})
    print(f"export CONFIG_TIMEOUT={settings.get('timeout', 300)}")
    print(f"export CONFIG_RETRIES={settings.get('retries', 2)}")
    print(f"export CONFIG_PARALLEL={settings.get('parallel', 4)}")
    print(f"export CONFIG_SKIP_AI={str(settings.get('skip_ai', False)).lower()}")
    print(f"export CONFIG_SKIP_WINDOWS={str(settings.get('skip_windows', False)).lower()}")
    
    # Parse Docker volume management settings
    docker_vol = config.get('docker_volume_management', {})
    if docker_vol.get('enabled', True):
        cache_vol = docker_vol.get('cache_volume', {})
        state_vol = docker_vol.get('state_volume', {})
        cleanup = docker_vol.get('cleanup_policies', {})
        
        print(f"export CONFIG_VOLUME_ENABLED=true")
        print(f"export CONFIG_CACHE_VOLUME_NAME={cache_vol.get('name', 'docker-pull-essentials-cache')}")
        print(f"export CONFIG_STATE_VOLUME_NAME={state_vol.get('name', 'docker-pull-essentials-state')}")
        print(f"export CONFIG_CACHE_MAX_SIZE_GB={cache_vol.get('max_size_gb', 50)}")
        print(f"export CONFIG_CACHE_CLEANUP_THRESHOLD={cache_vol.get('cleanup_threshold_percent', 85)}")
        print(f"export CONFIG_AUTO_CLEANUP_ENABLED={str(cleanup.get('auto_cleanup_enabled', True)).lower()}")
        
        # Advanced cleanup settings
        advanced = cleanup.get('advanced_cleanup', {})
        print(f"export CONFIG_ADVANCED_CLEANUP_ON_CRITICAL={str(advanced.get('enable_on_critical_space', True)).lower()}")
        print(f"export CONFIG_SPACE_THRESHOLD_GB={advanced.get('space_threshold_gb', 5)}")
    else:
        print(f"export CONFIG_VOLUME_ENABLED=false")
    
    # Check for environment overrides
    is_wsl = sys.argv[2].lower() == 'true'
    envs = config.get('environments', {})
    
    if is_wsl and 'wsl2' in envs:
        wsl_config = envs['wsl2']
        if 'parallel' in wsl_config:
            print(f"export CONFIG_PARALLEL={wsl_config['parallel']}")
        if 'skip_windows' in wsl_config:
            print(f"export CONFIG_SKIP_WINDOWS={str(wsl_config['skip_windows']).lower()}")
    elif not is_wsl and 'native_linux' in envs:
        linux_config = envs['native_linux']
        if 'parallel' in linux_config:
            print(f"export CONFIG_PARALLEL={linux_config['parallel']}")
    
    # Output categories info for building image list
    categories = config.get('categories', {})
    for cat_name, cat_data in categories.items():
        if cat_data.get('enabled', True):
            images = cat_data.get('images', [])
            for img in images:
                if isinstance(img, dict) and 'name' in img and 'tag' in img:
                    img_type = img.get('type', 'IMAGE').upper()
                    if img_type not in ('IMAGE', 'MODEL'):
                        img_type = 'IMAGE'
                    
                    # Extract human-readable names
                    friendly_name = img.get('friendly_name', f"{img['name']}:{img['tag']}")
                    short_name = img.get('short_name', img['name'].split('/')[-1])
                    description = img.get('description', '')
                    
                    print(f"CONFIG_IMAGE={img_type}:{img['name']}:{img['tag']}:{friendly_name}:{short_name}:{description}")
                elif isinstance(img, str):
                    print(f"CONFIG_IMAGE=IMAGE:{img}:::{img.split('/')[-1].split(':')[0]}:")
    
except Exception as e:
    print(f"CONFIG_ERROR={str(e)}", file=sys.stderr)
    sys.exit(1)
EOF
  )

  # Run Python script to parse YAML and write to cache file
  {
    echo "# Cached configuration from ${config_file}"
    echo "# Generated on $(date)"
    echo ""
    if ! python3 -c "${py_script}" "${config_file}" "${WSL_ENV}"; then
      log_error "Failed to parse configuration file with Python"
      return 1
    fi
  } >"${cache_file}"

  return 0
}

# Process configuration variables from parsed YAML
process_config_vars() {
  local config_vars="$1"

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue

    if [[ "${line}" == CONFIG_ERROR=* ]]; then
      log_error "Error parsing configuration: ${line#CONFIG_ERROR=}"
      return 1
    elif [[ "${line}" == CONFIG_TIMEOUT=* ]]; then
      TIMEOUT="${line#CONFIG_TIMEOUT=}"
    elif [[ "${line}" == CONFIG_RETRIES=* ]]; then
      RETRIES="${line#CONFIG_RETRIES=}"
    elif [[ "${line}" == CONFIG_PARALLEL=* ]]; then
      PARALLEL="${line#CONFIG_PARALLEL=}"
    elif [[ "${line}" == CONFIG_SKIP_AI=* ]]; then
      SKIP_AI="${line#CONFIG_SKIP_AI=}"
    elif [[ "${line}" == CONFIG_SKIP_WINDOWS=* ]]; then
      SKIP_WINDOWS="${line#CONFIG_SKIP_WINDOWS=}"
    elif [[ "${line}" == CONFIG_VOLUME_ENABLED=* ]]; then
      VOLUME_MANAGEMENT_ENABLED="${line#CONFIG_VOLUME_ENABLED=}"
    elif [[ "${line}" == CONFIG_CACHE_VOLUME_NAME=* ]]; then
      DOCKER_PULL_CACHE_VOLUME="${line#CONFIG_CACHE_VOLUME_NAME=}"
    elif [[ "${line}" == CONFIG_STATE_VOLUME_NAME=* ]]; then
      DOCKER_PULL_STATE_VOLUME="${line#CONFIG_STATE_VOLUME_NAME=}"
    elif [[ "${line}" == CONFIG_CACHE_MAX_SIZE_GB=* ]]; then
      CACHE_MAX_SIZE_GB="${line#CONFIG_CACHE_MAX_SIZE_GB=}"
    elif [[ "${line}" == CONFIG_CACHE_CLEANUP_THRESHOLD=* ]]; then
      CACHE_CLEANUP_THRESHOLD="${line#CONFIG_CACHE_CLEANUP_THRESHOLD=}"
    elif [[ "${line}" == CONFIG_AUTO_CLEANUP_ENABLED=* ]]; then
      AUTO_CLEANUP_ENABLED="${line#CONFIG_AUTO_CLEANUP_ENABLED=}"
    elif [[ "${line}" == CONFIG_ADVANCED_CLEANUP_ON_CRITICAL=* ]]; then
      ADVANCED_CLEANUP_ON_CRITICAL="${line#CONFIG_ADVANCED_CLEANUP_ON_CRITICAL=}"
    elif [[ "${line}" == CONFIG_SPACE_THRESHOLD_GB=* ]]; then
      SPACE_THRESHOLD_GB="${line#CONFIG_SPACE_THRESHOLD_GB=}"
    elif [[ "${line}" == CONFIG_IMAGE=* ]]; then
      echo "${line#CONFIG_IMAGE=}" >>"${TEMP_DIR}/config_images"
    fi
  done <<<"${config_vars}"

  return 0
}

# Build image list from configuration
build_image_list() {
  # Temporary file for image list
  local image_list="${TEMP_DIR}/image_list"
  true >"${image_list}"

  # Try to load from configuration file
  if load_configuration "${CONFIG_FILE}"; then
    log_info "Building image list from configuration"

    # Process config_images file if it exists
    if [[ -f "${TEMP_DIR}/config_images" ]]; then
      while IFS=: read -r type name tag friendly_name short_name description; do
        local full_image="${name}:${tag}"
        # Store metadata for display purposes
        echo "${type}:${full_image}:${friendly_name:-${full_image}}:${short_name:-${name##*/}}:${description}" >>"${image_list}"
      done <"${TEMP_DIR}/config_images"
    else
      log_warn "No images found in configuration, using default list"
      build_default_image_list
    fi
  else
    log_info "Using default hardcoded image list"
    build_default_image_list
  fi

  # Apply filters
  if [[ "${SKIP_AI}" == "true" ]]; then
    log_info "Filtering out AI/ML models"
    grep -v "MODEL:" "${image_list}" >"${TEMP_DIR}/filtered_list"
    mv "${TEMP_DIR}/filtered_list" "${image_list}"
  fi

  if [[ "${SKIP_WINDOWS}" == "true" ]]; then
    log_info "Filtering out Windows-specific images"
    grep -v "windows/" "${image_list}" >"${TEMP_DIR}/filtered_list"
    mv "${TEMP_DIR}/filtered_list" "${image_list}"
  fi

  # Write to queue file
  cat "${image_list}" >"${PULL_QUEUE}"
  TOTAL_IMAGES=$(wc -l <"${PULL_QUEUE}")

  log_info "Built image list with ${TOTAL_IMAGES} images/models"
}

# Default image list (fallback)
build_default_image_list() {
  local images=()

  # Base OS / Essentials
  images+=(
    "IMAGE:ubuntu:22.04"
    "IMAGE:debian:12-slim"
    "IMAGE:alpine:3.19"
  )

  # Programming Languages / Runtimes
  images+=(
    "IMAGE:python:3.12-slim"
    "IMAGE:node:20-alpine"
    "IMAGE:openjdk:21-jdk-slim"
    "IMAGE:golang:1.22-alpine"
  )

  # Databases
  images+=(
    "IMAGE:postgres:16-alpine"
    "IMAGE:mysql:8.0"
    "IMAGE:redis:7.2-alpine"
  )

  # Write to temporary file
  printf '%s\n' "${images[@]}" >"${TEMP_DIR}/image_list"
}

# Image validation functions
validate_image_exists() {
  local image="$1"
  local timeout="${2:-10}"

  if timeout "${timeout}" docker manifest inspect "${image}" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Pre-validation function
validate_all_images() {
  log_info "Pre-validating image availability..."

  local valid_list="${TEMP_DIR}/valid_images"
  local invalid_list="${TEMP_DIR}/invalid_images"
  true >"${valid_list}"
  true >"${invalid_list}"

  local validation_count=0

  # Process each image
  while IFS= read -r line; do
    if [[ -z "${line}" ]]; then
      continue
    fi

    local entry="${line}"
    local type="${line%%:*}"
    local remaining="${line#*:}"
    local image="${remaining%%:*}"

    if [[ "$type" == "IMAGE" ]] && validate_image_exists "${image}"; then
      echo "${entry}" >>"${valid_list}"
    else
      echo "${entry}" >>"${invalid_list}"
    fi

    ((validation_count++))

    if [[ $((validation_count % 5)) -eq 0 ]]; then
      show_progress "${validation_count}" "${TOTAL_IMAGES}"
    fi
  done <"${PULL_QUEUE}"

  echo # New line after progress

  # Process results
  local valid_count
  local invalid_count
  valid_count=$(wc -l <"${valid_list}" 2>/dev/null || echo 0)
  invalid_count=$(wc -l <"${invalid_list}" 2>/dev/null || echo 0)

  log_info "Validation completed: ${valid_count} valid, ${invalid_count} invalid"

  if [[ $invalid_count -gt 0 ]]; then
    log_warn "Invalid images found:"
    while IFS= read -r line; do
      log_warn "  - ${line#*:}"
    done <"${invalid_list}"
  fi

  # Update pull queue with only valid images
  cp "${valid_list}" "${PULL_QUEUE}"
  TOTAL_IMAGES=$valid_count

  if [[ $TOTAL_IMAGES -eq 0 ]]; then
    log_error "No valid images found to pull"
    exit 1
  fi
}

# Security validation
validate_image_registry() {
  local image="$1"

  if [[ -n "${ALLOWED_REGISTRIES}" ]]; then
    local registry="docker.io" # Default registry

    if [[ "$image" =~ ^([^/]+\.[^/]+)/.*$ ]]; then
      registry="${BASH_REMATCH[1]}"
    fi

    if [[ ",${ALLOWED_REGISTRIES}," != *",${registry},"* ]]; then
      log_error "Registry not allowed: ${registry} for image ${image}"
      return 1
    fi
  fi

  return 0
}

# Enhanced retry logic with jitter and circuit breaker
pull_image() {
  local entry="$1"
  local image
  image=$(get_image_name "${entry}")
  local display_name
  display_name=$(get_display_name "${entry}" "true")
  local description
  description=$(get_image_description "${entry}")

  local attempt=1
  local max_attempts=$((RETRIES + 1))
  local base_delay=2
  local circuit_breaker_file="${TEMP_DIR}/circuit_breaker_${image//[\/:]/_}"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Would pull ${display_name} (${image})"
    if [[ -n "${description}" ]]; then
      log_debug "  Description: ${description}"
    fi
    return 0
  fi

  # Check circuit breaker
  if [[ -f "${circuit_breaker_file}" ]]; then
    local last_failure
    last_failure=$(cat "${circuit_breaker_file}")
    local current_time
    current_time=$(date +%s)
    local cooldown_period=300 # 5 minutes

    if [[ $((current_time - last_failure)) -lt ${cooldown_period} ]]; then
      log_warn "Circuit breaker open for ${display_name}, skipping for now"
      return 1
    else
      rm -f "${circuit_breaker_file}"
    fi
  fi

  # Security validation
  if ! validate_image_registry "${image}"; then
    log_error "Registry validation failed for: ${display_name} (${image})"
    return 1
  fi

  # Signal that a pull is active
  echo "1" >"${TEMP_DIR}/pull_active"

  while [[ ${attempt} -le ${max_attempts} ]]; do
    log_debug "Pulling ${display_name} (attempt ${attempt}/${max_attempts})"

    # Capture stderr for error classification
    local error_output
    if error_output=$(timeout "${TIMEOUT}" docker pull "${image}" 2>&1); then
      log_info "✓ Successfully pulled: ${display_name}"
      if [[ -n "${description}" ]]; then
        log_debug "  ${description}"
      fi
      rm -f "${TEMP_DIR}/pull_active"
      return 0
    else
      local exit_code=$?
      local error_type
      error_type=$(classify_error "${error_output}" "${image}")

      log_warn "✗ Attempt ${attempt} failed for ${display_name} (${error_type}): ${error_output}"

      # Handle different error types
      case "${error_type}" in
      "RATE_LIMIT")
        # Longer delay for rate limiting
        local delay=$((base_delay * attempt * 5))
        ;;
      "DISK_SPACE")
        # Immediate failure for disk space issues
        log_error "Disk space error for ${image}, aborting"
        rm -f "${TEMP_DIR}/pull_active"
        return ${exit_code}
        ;;
      "AUTH")
        # Circuit breaker for auth failures
        date +%s >"${circuit_breaker_file}"
        log_error "Authentication error for ${display_name}, opening circuit breaker"
        rm -f "${TEMP_DIR}/pull_active"
        return ${exit_code}
        ;;
      *)
        # Standard exponential backoff with jitter
        local delay=$((base_delay * attempt * attempt))
        ;;
      esac

      if [[ ${attempt} -eq ${max_attempts} ]]; then
        log_error "Failed to pull ${display_name} after ${max_attempts} attempts (${error_type})"
        # Set circuit breaker for repeated failures
        date +%s >"${circuit_breaker_file}"
        rm -f "${TEMP_DIR}/pull_active"
        return ${exit_code}
      else
        # Add jitter (0-50% of delay)
        local jitter=$((RANDOM % (delay / 2 + 1)))
        local total_delay=$((delay + jitter))
        log_info "Retrying ${display_name} in ${total_delay} seconds..."
        sleep "${total_delay}"
      fi
    fi

    ((attempt++))
  done

  # Should not reach here
  rm -f "${TEMP_DIR}/pull_active"
  return 1
}

# Pull worker function with proper queue locking
pull_worker() {
  local worker_id="$1"
  local queue_file="$2"
  local results_file="$3"
  local processed_count=0

  log_debug "Worker ${worker_id} starting"

  while true; do
    # Get next item from queue with file locking
    local line
    line=$(
      flock -x 200
      if [[ -s "${queue_file}" ]]; then
        head -n1 "${queue_file}"
        # Remove the processed line
        sed -i '1d' "${queue_file}"
      fi
    ) 200>"${QUEUE_LOCK}"

    # Exit if no more work
    if [[ -z "${line}" ]]; then
      log_debug "Worker ${worker_id} finished, processed ${processed_count} items"
      break
    fi

    local entry="${line}"
    local type="${line%%:*}"
    local remaining="${line#*:}"
    local image="${remaining%%:*}"

    if [[ "$type" == "IMAGE" ]]; then
      if pull_image "${entry}"; then
        echo "IMAGE:${image}" >>"${COMPLETED_FILE}"
        echo "SUCCESS:${image}" >>"${results_file}"
        increment_successful
      else
        echo "IMAGE:${image}" >>"${FAILED_FILE}"
        echo "FAILED:${image}" >>"${results_file}"
        increment_failed
        # Thread-safe addition to failed images array
        echo "${image}" >>"${TEMP_DIR}/failed_images_list"
      fi
    fi

    ((processed_count++))

    # Check for stop signal (e.g., critical disk space)
    if [[ -f "${TEMP_DIR}/stop_pulls" ]]; then
      log_warn "Worker ${worker_id} stopping due to stop signal"
      break
    fi
  done
}

# Extract human-readable name from image entry
get_display_name() {
  local entry="$1"
  local use_short="${2:-false}"

  # Format: TYPE:IMAGE:FRIENDLY_NAME:SHORT_NAME:DESCRIPTION
  local friendly_name short_name
  IFS=: read -r _ _ friendly_name short_name _ <<<"${entry}"

  if [[ "${use_short}" == "true" && -n "${short_name}" ]]; then
    echo "${short_name}"
  elif [[ -n "${friendly_name}" ]]; then
    echo "${friendly_name}"
  else
    # Fallback to image name
    IFS=: read -r _ image _ _ _ <<<"${entry}"
    echo "${image}"
  fi
}

# Extract just the image name from entry
get_image_name() {
  local entry="$1"
  IFS=: read -r _ image _ _ _ <<<"${entry}"
  echo "${image}"
}

# Extract description from image entry
get_image_description() {
  local entry="$1"
  IFS=: read -r _ _ _ _ description <<<"${entry}"
  echo "${description}"
}

# Display current operation with human-readable names
show_current_operation() {
  local entry="$1"
  local operation="${2:-Processing}"

  if [[ -n "${entry}" ]]; then
    local display_name
    display_name=$(get_display_name "${entry}" "true")
    local description
    description=$(get_image_description "${entry}")

    if [[ -n "${description}" ]]; then
      log_info "${operation}: ${display_name} - ${description}"
    else
      log_info "${operation}: ${display_name}"
    fi
  fi
}

# Parse command line args
parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --parallel)
      PARALLEL="$2"
      shift 2
      ;;
    --retry)
      RETRIES="$2"
      shift 2
      ;;
    --timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    --skip-ai)
      SKIP_AI=true
      shift
      ;;
    --skip-windows)
      SKIP_WINDOWS=true
      shift
      ;;
    --log-file)
      LOG_FILE="$2"
      shift 2
      ;;
    --resume)
      RESUME_MODE=true
      shift
      ;;
    --advanced-cleanup)
      log_info "Running advanced Docker cleanup with volume management..."
      advanced_docker_cleanup
      exit 0
      ;;
    --cleanup-volumes)
      log_info "Running Docker volume cleanup..."
      cleanup_docker_volumes
      exit 0
      ;;
    --volume-status)
      log_info "Docker Volume Management Status:"
      log_info "================================"
      log_info "Volume Management Enabled: ${VOLUME_MANAGEMENT_ENABLED:-true}"
      log_info "Cache Volume: ${DOCKER_PULL_CACHE_VOLUME}"
      log_info "State Volume: ${DOCKER_PULL_STATE_VOLUME}"

      # Show actual volume status
      if docker volume inspect "${DOCKER_PULL_CACHE_VOLUME}" >/dev/null 2>&1; then
        log_info "✓ Cache volume exists"
        cache_usage=$(get_volume_usage "${DOCKER_PULL_CACHE_VOLUME}")
        log_info "  Usage: ${cache_usage}"
      else
        log_info "✗ Cache volume not created yet"
      fi

      if docker volume inspect "${DOCKER_PULL_STATE_VOLUME}" >/dev/null 2>&1; then
        log_info "✓ State volume exists"
        state_usage=$(get_volume_usage "${DOCKER_PULL_STATE_VOLUME}")
        log_info "  Usage: ${state_usage}"
      else
        log_info "✗ State volume not created yet"
      fi

      # Show configuration
      log_info ""
      log_info "Configuration:"
      log_info "  Max Cache Size: ${CACHE_MAX_SIZE_GB:-50}GB"
      log_info "  Cleanup Threshold: ${CACHE_CLEANUP_THRESHOLD:-85}%"
      log_info "  Auto Cleanup: ${AUTO_CLEANUP_ENABLED:-true}"
      log_info "  Space Threshold: ${SPACE_THRESHOLD_GB:-5}GB"
      exit 0
      ;;
    --help)
      show_help
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      show_help
      exit 1
      ;;
    esac
  done
}

# Show help
show_help() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Pull essential Docker images for development and AI/ML workloads.

Options:
  --config FILE     Specify configuration file (default: ${DEFAULT_CONFIG_FILE})
  --dry-run         Show what would be pulled without actually pulling
  --parallel NUM    Number of parallel pulls (default: ${DEFAULT_PARALLEL})
  --retry NUM       Number of retry attempts per image (default: ${DEFAULT_RETRIES})
  --timeout SEC     Timeout for each pull in seconds (default: ${DEFAULT_TIMEOUT})
  --skip-ai         Skip AI/ML model pulls
  --skip-windows    Skip Windows-specific images
  --log-file FILE   Log output to file (default: ${DEFAULT_LOG_FILE})
  --resume          Resume from a previous interrupted operation
  --advanced-cleanup  Run advanced Docker cleanup with volume management
  --cleanup-volumes   Run Docker volume cleanup
  --volume-status     Show Docker volume management status and configuration
  --help            Show this help message
EOF
}

# Generate report
generate_report() {
  local end_time
  end_time="$(date +%s)"
  local duration=$((end_time - START_TIME))
  local duration_minutes=$((duration / 60))
  local duration_seconds=$((duration % 60))

  # Get final counts from counter files
  local successful_pulls
  local failed_pulls
  successful_pulls="$(get_successful_count)"
  failed_pulls="$(get_failed_count)"

  echo
  log_info "===== DOCKER PULL SUMMARY ====="
  log_info "Total images: ${TOTAL_IMAGES}"
  log_info "Successful pulls: ${successful_pulls}"
  log_info "Failed pulls: ${failed_pulls}"
  log_info "Duration: ${duration_minutes}m ${duration_seconds}s"

  # Show Docker volume usage
  local cache_usage
  cache_usage=$(get_volume_usage "${DOCKER_PULL_CACHE_VOLUME}")
  local state_usage
  state_usage=$(get_volume_usage "${DOCKER_PULL_STATE_VOLUME}")
  log_info "Docker volumes: Cache=${cache_usage}, State=${state_usage}"

  if [[ ${failed_pulls} -gt 0 ]]; then
    log_error "Failed images:"
    for image in "${FAILED_IMAGES[@]}"; do
      log_error "  - ${image}"
    done
    log_warn "Use --resume to retry failed pulls"
    return 1
  else
    log_success "All images pulled successfully!"
    return 0
  fi
}

# Main function with enhanced state management
main() {
  # Initialize log file
  true >"${LOG_FILE}"

  log_info "Docker Pull Essentials v${SCRIPT_VERSION}"
  log_info "Starting with configuration: parallel=${PARALLEL}, retries=${RETRIES}, timeout=${TIMEOUT}"
  log_debug "Volume management: enabled=${VOLUME_MANAGEMENT_ENABLED}, cache_volume=${DOCKER_PULL_CACHE_VOLUME}"
  log_debug "Cleanup settings: auto=${AUTO_CLEANUP_ENABLED}, threshold=${SPACE_THRESHOLD_GB}GB"

  # Parse command line arguments
  parse_arguments "$@"

  # Check prerequisites
  check_prerequisites

  # Set up Docker volumes for caching and state management
  setup_docker_volumes

  # Initialize progress tracking
  echo "${START_TIME}" >"${PROGRESS_STATE}"

  # Start disk monitoring in background
  monitor_disk_space &
  local monitor_pid=$!

  # Build image list
  build_image_list

  # Validate images before pulling (unless in dry-run mode)
  if [[ "${DRY_RUN}" != "true" ]]; then
    validate_all_images
  fi

  log_info "Starting pull process with ${PARALLEL} workers"
  echo

  # Initialize state tracking files
  true >"${COMPLETED_FILE}"
  true >"${FAILED_FILE}"
  true >"${RESULTS_FILE}"
  true >"${ERROR_CLASSIFICATION}"
  true >"${TEMP_DIR}/failed_images_list"

  # Start workers in background
  local worker_pids=()
  for ((i = 0; i < PARALLEL; i++)); do
    pull_worker "$i" "${PULL_QUEUE}" "${RESULTS_FILE}" &
    worker_pids+=($!)
  done

  # Monitor progress
  local completed=0
  local total_bytes=0
  local downloaded_bytes=0

  while [[ ${completed} -lt ${TOTAL_IMAGES} ]]; do
    sleep 2

    # Check for stop signals
    if [[ -f "${TEMP_DIR}/stop_pulls" ]]; then
      log_warn "Stopping all workers due to critical condition"
      for pid in "${worker_pids[@]}"; do
        kill -TERM "$pid" 2>/dev/null || true
      done
      break
    fi

    local successful
    successful=$(get_successful_count)
    local failed
    failed=$(get_failed_count)
    completed=$((successful + failed))

    show_progress "${completed}" "${TOTAL_IMAGES}" "${downloaded_bytes}" "${total_bytes}"
  done

  # Wait for all workers to exit gracefully
  for pid in "${worker_pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  # Stop disk monitoring
  rm -f "${TEMP_DIR}/disk_monitoring_active" 2>/dev/null || true
  wait "$monitor_pid" 2>/dev/null || true

  # Build failed images array from file
  if [[ -f "${TEMP_DIR}/failed_images_list" ]]; then
    mapfile -t FAILED_IMAGES <"${TEMP_DIR}/failed_images_list"
  fi

  # Generate report
  generate_report
  return $?
}

# Run the script if not sourced
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
