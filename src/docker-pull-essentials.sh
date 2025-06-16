#!/usr/bin/env bash
# docker-pull-essentials.sh
# Pulls essential Docker images for development and AI/ML workloads.
# Version: 3.0.0
# Last updated: 2025-06-15
#
# Usage:
#   ./docker-pull-essentials.sh [OPTIONS]
#
# Options:
#   --config FILE     Specify configuration file (default: ./docker-pull-config.yaml)
#   --dry-run         Show what would be pulled without actually pulling
#   --retry NUM       Number of retry attempts per image (default: 2)
#   --timeout SEC     Timeout for each pull in seconds (default: 300)
#   --skip-ai         Skip AI/ML model pulls
#   --skip-windows    Skip Windows-specific images
#   --help            Show this help message

set -euo pipefail

# Script information
SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT_VERSION="3.0.0"

# Default configuration
DEFAULT_CONFIG_FILE="${SCRIPT_DIR}/docker-pull-config.yaml"
DEFAULT_TIMEOUT=300
DEFAULT_RETRIES=2
TEMP_DIR=""

# Configuration variables
CONFIG_FILE="${DEFAULT_CONFIG_FILE}"
DRY_RUN=false
SKIP_AI=false
SKIP_WINDOWS=false
TIMEOUT=${DEFAULT_TIMEOUT}
RETRIES=${DEFAULT_RETRIES}

# Counters for reporting
SUCCESSFUL_PULLS=0
FAILED_PULLS=0
TOTAL_IMAGES=0
FAILED_IMAGES=()

# Create temporary directory
create_temp_dir() {
  TEMP_DIR=$(mktemp -d)
  trap 'rm -rf "${TEMP_DIR}"' EXIT
}

# Logging functions
log() {
  local level=$1
  shift
  echo "$(date '+%Y-%m-%d %H:%M:%S') [${SCRIPT_NAME}] ${level}: $*" >&2
}

log_info() {
  log "INFO" "$@"
}

log_warn() {
  log "WARN" "$@"
}

log_error() {
  log "ERROR" "$@"
}

log_success() {
  log "SUCCESS" "$@"
}

# Show help
show_help() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Pull essential Docker images for development and AI/ML workloads.
Images are pulled sequentially (one at a time) for reliability.

Options:
  --config FILE     Specify configuration file (default: ${DEFAULT_CONFIG_FILE})
  --dry-run         Show what would be pulled without actually pulling
  --retry NUM       Number of retry attempts per image (default: ${DEFAULT_RETRIES})
  --timeout SEC     Timeout for each pull in seconds (default: ${DEFAULT_TIMEOUT})
  --skip-ai         Skip AI/ML model pulls
  --skip-windows    Skip Windows-specific images
  --help            Show this help message
EOF
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

  # Check for YAML parser
  if ! command -v python3 >/dev/null 2>&1; then
    log_error "Python 3 is required for parsing YAML configuration"
    exit 2
  fi

  log_info "Prerequisites check completed"
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

# Parse YAML config file with Python
parse_config() {
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    log_error "Configuration file not found: ${CONFIG_FILE}"
    return 1
  fi

  log_info "Loading configuration from: ${CONFIG_FILE}"

  local py_script
  py_script=$(
    cat <<'EOF'
import sys
import yaml
import os

try:
    with open(sys.argv[1], 'r') as f:
        config = yaml.safe_load(f)
    
    # Get environment-specific settings
    is_wsl = os.environ.get('WSL_ENV', 'false').lower() == 'true'
    
    # Get global settings with environment overrides
    settings = config.get('settings', {})
    parallel = settings.get('parallel', 4)
    skip_windows = settings.get('skip_windows', False)
    
    if is_wsl and 'environments' in config and 'wsl2' in config['environments']:
        wsl_config = config['environments']['wsl2']
        if 'parallel' in wsl_config:
            parallel = wsl_config['parallel']
        if 'skip_windows' in wsl_config:
            skip_windows = wsl_config['skip_windows']
    elif not is_wsl and 'environments' in config and 'native_linux' in config['environments']:
        linux_config = config['environments']['native_linux']
        if 'parallel' in linux_config:
            parallel = linux_config['parallel']
    
    # Print settings
    print(f"CONFIG_PARALLEL={parallel}")
    print(f"CONFIG_TIMEOUT={settings.get('timeout', 300)}")
    print(f"CONFIG_RETRIES={settings.get('retries', 2)}")
    print(f"CONFIG_SKIP_AI={str(settings.get('skip_ai', False)).lower()}")
    print(f"CONFIG_SKIP_WINDOWS={str(skip_windows).lower()}")
    
    # Process image categories and output images
    categories = config.get('categories', {})
    for cat_name, cat_data in categories.items():
        # Skip disabled categories
        if not cat_data.get('enabled', True):
            continue
            
        images = cat_data.get('images', [])
        for img in images:
            if isinstance(img, dict) and 'name' in img:
                img_type = img.get('type', 'IMAGE').upper()
                if img_type not in ('IMAGE', 'MODEL'):
                    img_type = 'IMAGE'
                
                # Get image details
                name = img['name']
                tag = img.get('tag', 'latest')
                friendly_name = img.get('friendly_name', f"{name}:{tag}")
                
                print(f"IMAGE:{img_type}:{name}:{tag}:{friendly_name}")
            elif isinstance(img, str):
                # Handle simple string format (just image name)
                parts = img.split(':')
                name = parts[0]
                tag = parts[1] if len(parts) > 1 else 'latest'
                print(f"IMAGE:IMAGE:{name}:{tag}:{name}:{tag}")
    
except Exception as e:
    print(f"CONFIG_ERROR={str(e)}", file=sys.stderr)
    sys.exit(1)
EOF
  )

  # Run Python script to parse YAML
  local config_output
  config_output=$(python3 -c "${py_script}" "${CONFIG_FILE}")

  if [[ $? -ne 0 ]]; then
    log_error "Failed to parse configuration file"
    return 1
  fi

  # Process output
  while IFS= read -r line; do
    if [[ "${line}" == CONFIG_ERROR=* ]]; then
      log_error "Error parsing configuration: ${line#CONFIG_ERROR=}"
      return 1
    elif [[ "${line}" == CONFIG_TIMEOUT=* ]]; then
      TIMEOUT="${line#CONFIG_TIMEOUT=}"
    elif [[ "${line}" == CONFIG_RETRIES=* ]]; then
      RETRIES="${line#CONFIG_RETRIES=}"
    elif [[ "${line}" == CONFIG_SKIP_AI=* ]]; then
      SKIP_AI="${line#CONFIG_SKIP_AI=}"
    elif [[ "${line}" == CONFIG_SKIP_WINDOWS=* ]]; then
      SKIP_WINDOWS="${line#CONFIG_SKIP_WINDOWS=}"
    elif [[ "${line}" == IMAGE:* ]]; then
      echo "${line}" >>"${TEMP_DIR}/image_list"
    fi
  done <<<"${config_output}"

  return 0
}

# Build default image list (fallback)
build_default_image_list() {
  local images=(
    "IMAGE:IMAGE:ubuntu:22.04:Ubuntu 22.04"
    "IMAGE:IMAGE:debian:12-slim:Debian 12 Slim"
    "IMAGE:IMAGE:alpine:3.19:Alpine 3.19"
    "IMAGE:IMAGE:python:3.12-slim:Python 3.12 Slim"
    "IMAGE:IMAGE:node:20-alpine:Node.js 20 Alpine"
    "IMAGE:IMAGE:openjdk:21-jdk-slim:OpenJDK 21 Slim"
    "IMAGE:IMAGE:postgres:16-alpine:PostgreSQL 16 Alpine"
    "IMAGE:IMAGE:mysql:8.0:MySQL 8.0"
    "IMAGE:IMAGE:redis:7.2-alpine:Redis 7.2 Alpine"
  )

  printf '%s\n' "${images[@]}" >"${TEMP_DIR}/image_list"
  log_info "Using default image list with ${#images[@]} images"
}

# Build image list from configuration
build_image_list() {
  # Initialize image list file
  true >"${TEMP_DIR}/image_list"

  # Try to load from configuration file
  if parse_config; then
    log_info "Building image list from configuration"
  else
    log_info "Using default hardcoded image list"
    build_default_image_list
  fi

  # Apply filters
  if [[ "${SKIP_AI}" == "true" ]]; then
    log_info "Filtering out AI/ML models"
    grep -v "IMAGE:MODEL:" "${TEMP_DIR}/image_list" >"${TEMP_DIR}/filtered_list"
    mv "${TEMP_DIR}/filtered_list" "${TEMP_DIR}/image_list"
  fi

  if [[ "${SKIP_WINDOWS}" == "true" ]]; then
    log_info "Filtering out Windows-specific images"
    grep -v "windows/" "${TEMP_DIR}/image_list" >"${TEMP_DIR}/filtered_list"
    mv "${TEMP_DIR}/filtered_list" "${TEMP_DIR}/image_list"
  fi

  # Count total images
  TOTAL_IMAGES=$(wc -l <"${TEMP_DIR}/image_list")
  log_info "Built image list with ${TOTAL_IMAGES} images"
}

# Pull image with retries
pull_image() {
  local image_line="$1"
  local img_name tag friendly_name

  # Parse image line (format: IMAGE:TYPE:NAME:TAG:FRIENDLY_NAME)
  IFS=':' read -r _ _ img_name tag friendly_name <<<"${image_line}"

  local image="${img_name}:${tag}"
  local display_name="${friendly_name:-${image}}"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Would pull ${display_name} (${image})"
    return 0
  fi

  log_info "Pulling ${display_name}..."

  local attempt=1
  local max_attempts=$((RETRIES + 1))

  while [[ ${attempt} -le ${max_attempts} ]]; do
    if timeout "${TIMEOUT}" docker pull "${image}" >/dev/null 2>&1; then
      log_success "✓ Successfully pulled: ${display_name}"
      SUCCESSFUL_PULLS=$((SUCCESSFUL_PULLS + 1))
      return 0
    else
      local exit_code=$?

      if [[ ${attempt} -eq ${max_attempts} ]]; then
        log_error "Failed to pull ${display_name} after ${max_attempts} attempts"
        FAILED_PULLS=$((FAILED_PULLS + 1))
        FAILED_IMAGES+=("${image}")
        return ${exit_code}
      else
        log_warn "Attempt ${attempt}/${max_attempts} failed for ${display_name}, retrying..."
        sleep $((attempt * 2))
      fi
    fi

    attempt=$((attempt + 1))
  done

  # Should not reach here
  return 1
}

# Pull images sequentially (one at a time)
pull_images_sequential() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "DRY-RUN: Would pull ${TOTAL_IMAGES} images sequentially"
    local count=0
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      local img_name tag friendly_name
      IFS=':' read -r _ _ img_name tag friendly_name <<<"${line}"
      local image="${img_name}:${tag}"
      local display_name="${friendly_name:-${image}}"
      ((count++))
      log_info "  ${count}. Would pull: ${display_name} (${image})"
    done <"${TEMP_DIR}/image_list"
    return 0
  fi

  log_info "Starting sequential pull process for ${TOTAL_IMAGES} images"
  echo

  local current=0

  # Process each image sequentially
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue

    ((current++))
    local img_name tag friendly_name
    IFS=':' read -r _ _ img_name tag friendly_name <<<"${line}"
    local image="${img_name}:${tag}"
    local display_name="${friendly_name:-${image}}"

    echo "Progress: [${current}/${TOTAL_IMAGES}] ${display_name}"

    if pull_image "${line}"; then
      echo "✓ Success: ${display_name}"
    else
      echo "✗ Failed: ${display_name}"
    fi
    echo

  done <"${TEMP_DIR}/image_list"

  log_info "Sequential pull process completed"
}

# Generate report
generate_report() {
  local start_time="$1"
  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))
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
    return 1
  else
    log_success "All images pulled successfully!"
    return 0
  fi
}

# Main function
main() {
  local start_time
  start_time=$(date +%s)

  log_info "Docker Pull Essentials v${SCRIPT_VERSION}"

  # Create temporary directory
  create_temp_dir

  # Parse command line arguments
  parse_arguments "$@"

  # Check prerequisites
  check_prerequisites

  # Build image list
  build_image_list

  # Pull images sequentially (one at a time)
  pull_images_sequential

  # Generate report
  generate_report "${start_time}"
  return $?
}

# Run the script
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  # Add simple echo for testing
  echo "Script is executing..."
  main "$@"
fi
