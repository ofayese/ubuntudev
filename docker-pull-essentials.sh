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
ENABLE_CONTENT_TRUST="${DOCKER_CONTENT_TRUST:-false}"
VULNERABILITY_SCAN="${ENABLE_VULN_SCAN:-false}"
ALLOWED_REGISTRIES="${DOCKER_ALLOWED_REGISTRIES:-}"

# Counters for reporting
declare -i TOTAL_IMAGES=0
declare -i SUCCESSFUL_PULLS=0
declare -i FAILED_PULLS=0
declare -a FAILED_IMAGES=()

# Temporary files for parallel processing
TEMP_DIR="$(mktemp -d)"
readonly TEMP_DIR
readonly PULL_QUEUE="${TEMP_DIR}/pull_queue"
readonly RESULTS_FILE="${TEMP_DIR}/results"
readonly STATE_FILE="${TEMP_DIR}/pull_state.json"
readonly COMPLETED_FILE="${TEMP_DIR}/completed_images"
readonly FAILED_FILE="${TEMP_DIR}/failed_images"
readonly SECURITY_LOG="${TEMP_DIR}/security_validation.log"

# Store start time for duration calculation
START_TIME="$(date +%s)"
readonly START_TIME

# Cleanup function
cleanup() {
  local exit_code=$?
  if [[ -d "${TEMP_DIR}" ]]; then
    # Don't remove temp directory if in resume mode and there were failures
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

# Progress indicator
show_progress() {
  local current="$1"
  local total="$2"
  local percentage=$((current * 100 / total))
  printf "\r${LOG_PREFIX} Progress: [%3d%%] %d/%d images" "${percentage}" "${current}" "${total}"
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

# Cleanup functions
cleanup_partial_downloads() {
  log_info "Cleaning up partial downloads..."
  docker image prune -f --filter "dangling=true" >/dev/null 2>&1 || true
  docker builder prune -f >/dev/null 2>&1 || true
  log_info "Partial download cleanup completed"
}

cleanup_old_images() {
  log_info "Cleaning up old unused images..."
  docker image prune -f --filter "until=168h" >/dev/null 2>&1 || true
  log_info "Old image cleanup completed"
}

# Background disk monitoring function
monitor_disk_space() {
  local monitor_pid=$$
  local last_check=0

  log_debug "Starting disk space monitoring (PID: ${monitor_pid})"

  while kill -0 $monitor_pid 2>/dev/null; do
    local current_time=$(date +%s)

    if [[ $((current_time - last_check)) -ge ${DISK_CHECK_INTERVAL} ]]; then
      local available_gb=$(get_available_disk)
      local usage_percent=$(df /var/lib/docker 2>/dev/null | awk 'NR==2 {gsub(/%/, "", $5); print $5}' || echo "0")

      log_debug "Disk check: ${available_gb}GB available, ${usage_percent}% used"

      if [[ ${available_gb} -lt ${MIN_FREE_SPACE_GB} ]]; then
        log_error "Critical: Low disk space detected: ${available_gb}GB available"
        cleanup_partial_downloads
        kill -TERM $monitor_pid
        exit 1
      elif [[ ${usage_percent} -gt ${CLEANUP_THRESHOLD_PERCENT} ]]; then
        log_warn "High disk usage detected: ${usage_percent}% used"
        cleanup_old_images
      fi

      last_check=$current_time
    fi

    sleep 10
  done
}

# Configuration loading function
load_configuration() {
  local config_file="$1"

  if [[ ! -f "${config_file}" ]]; then
    log_error "Configuration file not found: ${config_file}"
    return 1
  fi

  log_info "Loading configuration from: ${config_file}"

  # Check if yq is available for YAML parsing
  if command -v yq >/dev/null 2>&1; then
    parse_yaml_config_yq "${config_file}"
    return $?
  elif command -v python3 >/dev/null 2>&1; then
    parse_yaml_config_python "${config_file}"
    return $?
  else
    log_error "No YAML parser available (yq or python3)"
    return 1
  fi
}

# Parse YAML with yq
parse_yaml_config_yq() {
  local config_file="$1"

  # Get global settings
  TIMEOUT=$(yq eval '.settings.timeout // 300' "${config_file}")
  RETRIES=$(yq eval '.settings.retries // 2' "${config_file}")
  PARALLEL=$(yq eval '.settings.parallel // 4' "${config_file}")
  SKIP_AI=$(yq eval '.settings.skip_ai // false' "${config_file}")
  SKIP_WINDOWS=$(yq eval '.settings.skip_windows // false' "${config_file}")

  # Check for environment-specific overrides
  if [[ "${WSL_ENV}" == "true" ]] && yq eval '.environments.wsl2 | length > 0' "${config_file}" >/dev/null 2>&1; then
    log_info "Applying WSL2-specific configuration overrides"
    PARALLEL=$(yq eval '.environments.wsl2.parallel // .settings.parallel' "${config_file}")
    SKIP_WINDOWS=$(yq eval '.environments.wsl2.skip_windows // .settings.skip_windows' "${config_file}")
  elif [[ "${WSL_ENV}" == "false" ]] && yq eval '.environments.native_linux | length > 0' "${config_file}" >/dev/null 2>&1; then
    log_info "Applying native Linux configuration overrides"
    PARALLEL=$(yq eval '.environments.native_linux.parallel // .settings.parallel' "${config_file}")
  fi

  return 0
}

# Parse YAML with Python
parse_yaml_config_python() {
  local config_file="$1"

  # Python script to parse YAML
  local py_script=$(
    cat <<'EOF'
import sys
import yaml

try:
    with open(sys.argv[1], 'r') as f:
        config = yaml.safe_load(f)
    
    # Output key settings as env vars
    settings = config.get('settings', {})
    print(f"CONFIG_TIMEOUT={settings.get('timeout', 300)}")
    print(f"CONFIG_RETRIES={settings.get('retries', 2)}")
    print(f"CONFIG_PARALLEL={settings.get('parallel', 4)}")
    print(f"CONFIG_SKIP_AI={str(settings.get('skip_ai', False)).lower()}")
    print(f"CONFIG_SKIP_WINDOWS={str(settings.get('skip_windows', False)).lower()}")
    
    # Check for environment overrides
    is_wsl = sys.argv[2].lower() == 'true'
    envs = config.get('environments', {})
    
    if is_wsl and 'wsl2' in envs:
        wsl_config = envs['wsl2']
        if 'parallel' in wsl_config:
            print(f"CONFIG_PARALLEL={wsl_config['parallel']}")
        if 'skip_windows' in wsl_config:
            print(f"CONFIG_SKIP_WINDOWS={str(wsl_config['skip_windows']).lower()}")
    elif not is_wsl and 'native_linux' in envs:
        linux_config = envs['native_linux']
        if 'parallel' in linux_config:
            print(f"CONFIG_PARALLEL={linux_config['parallel']}")
    
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
                    print(f"CONFIG_IMAGE={img_type}:{img['name']}:{img['tag']}")
                elif isinstance(img, str):
                    print(f"CONFIG_IMAGE=IMAGE:{img}")
    
except Exception as e:
    print(f"CONFIG_ERROR={str(e)}", file=sys.stderr)
    sys.exit(1)
EOF
  )

  # Run Python script to parse YAML
  local config_vars
  if ! config_vars=$(python3 -c "${py_script}" "${config_file}" "${WSL_ENV}"); then
    log_error "Failed to parse configuration file with Python"
    return 1
  fi

  # Apply configuration
  while IFS= read -r line; do
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
  >"${image_list}"

  # Try to load from configuration file
  if load_configuration "${CONFIG_FILE}"; then
    log_info "Building image list from configuration"

    # Process config_images file if it exists
    if [[ -f "${TEMP_DIR}/config_images" ]]; then
      while IFS=: read -r type name tag; do
        local full_image="${name}:${tag}"
        echo "${type}:${full_image}" >>"${image_list}"
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
  >"${valid_list}"
  >"${invalid_list}"

  local validation_count=0

  # Process each image
  while IFS= read -r line; do
    if [[ -z "${line}" ]]; then
      continue
    fi

    local type="${line%%:*}"
    local image="${line#*:}"

    if [[ "$type" == "IMAGE" ]] && validate_image_exists "${image}"; then
      echo "${line}" >>"${valid_list}"
    else
      echo "${line}" >>"${invalid_list}"
    fi

    ((validation_count++))

    if [[ $((validation_count % 5)) -eq 0 ]]; then
      show_progress "${validation_count}" "${TOTAL_IMAGES}"
    fi
  done <"${PULL_QUEUE}"

  echo # New line after progress

  # Process results
  local valid_count=$(wc -l <"${valid_list}" 2>/dev/null || echo 0)
  local invalid_count=$(wc -l <"${invalid_list}" 2>/dev/null || echo 0)

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

# Core pull function
pull_image() {
  local image="$1"
  local attempt=1
  local max_attempts=$((RETRIES + 1))

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Would pull image: ${image}"
    return 0
  fi

  # Security validation
  if ! validate_image_registry "${image}"; then
    log_error "Registry validation failed for: ${image}"
    return 1
  fi

  while [[ ${attempt} -le ${max_attempts} ]]; do
    log_debug "Pulling ${image} (attempt ${attempt}/${max_attempts})"

    if timeout "${TIMEOUT}" docker pull "${image}" >/dev/null 2>&1; then
      log_info "Successfully pulled: ${image}"
      return 0
    else
      local exit_code=$?
      if [[ ${attempt} -eq ${max_attempts} ]]; then
        log_error "Failed to pull ${image} after ${max_attempts} attempts"
        return ${exit_code}
      else
        log_warn "Attempt ${attempt} failed for ${image}, retrying..."
        sleep $((attempt * 2)) # Exponential backoff
      fi
    fi

    ((attempt++))
  done

  # Should not reach here
  return 1
}

# Pull worker function
pull_worker() {
  local worker_id="$1"
  local queue_file="$2"
  local results_file="$3"

  while IFS= read -r line; do
    if [[ -z "${line}" ]]; then
      continue
    fi

    local type="${line%%:*}"
    local image="${line#*:}"

    if [[ "$type" == "IMAGE" ]]; then
      if pull_image "${image}"; then
        echo "IMAGE:${image}" >>"${COMPLETED_FILE}"
        echo "SUCCESS:${image}" >>"${results_file}"
        ((SUCCESSFUL_PULLS++))
      else
        echo "IMAGE:${image}" >>"${FAILED_FILE}"
        echo "FAILED:${image}" >>"${results_file}"
        ((FAILED_PULLS++))
        FAILED_IMAGES+=("${image}")
      fi
    fi

  done < <(sort -R "${queue_file}" | awk "NR % ${PARALLEL} == ${worker_id}")
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

  echo
  log_info "===== DOCKER PULL SUMMARY ====="
  log_info "Total images: ${TOTAL_IMAGES}"
  log_info "Successful pulls: ${SUCCESSFUL_PULLS}"
  log_info "Failed pulls: ${FAILED_PULLS}"
  log_info "Duration: ${duration_minutes}m ${duration_seconds}s"

  if [[ ${FAILED_PULLS} -gt 0 ]]; then
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

# Main function
main() {
  # Initialize log file
  >"${LOG_FILE}"

  log_info "Docker Pull Essentials v${SCRIPT_VERSION}"
  log_info "Starting with configuration: parallel=${PARALLEL}, retries=${RETRIES}, timeout=${TIMEOUT}"

  # Parse command line arguments
  parse_arguments "$@"

  # Check prerequisites
  check_prerequisites

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
  >"${COMPLETED_FILE}"
  >"${FAILED_FILE}"
  >"${RESULTS_FILE}"

  # Start workers in background
  local worker_pids=()
  for ((i = 0; i < PARALLEL; i++)); do
    pull_worker "$i" "${PULL_QUEUE}" "${RESULTS_FILE}" &
    worker_pids+=($!)
  done

  # Wait for all workers to finish
  local completed=0
  while [[ ${completed} -lt ${TOTAL_IMAGES} ]]; do
    sleep 1
    completed=$((SUCCESSFUL_PULLS + FAILED_PULLS))
    show_progress "${completed}" "${TOTAL_IMAGES}"
  done

  # Wait for all workers to exit
  for pid in "${worker_pids[@]}"; do
    wait "$pid" || true
  done

  # Kill disk monitoring
  kill "$monitor_pid" 2>/dev/null || true

  # Generate report
  generate_report
  return $?
}

# Run the script if not sourced
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
