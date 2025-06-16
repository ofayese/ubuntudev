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

# Configuration variables
CONFIG_FILE="${DEFAULT_CONFIG_FILE}"
DRY_RUN=false
SKIP_AI=false
SKIP_WINDOWS=false
TIMEOUT=${DEFAULT_TIMEOUT}
RETRIES=${DEFAULT_RETRIES}

# Image storage
declare -a IMAGE_LIST=()

# Counters for reporting
SUCCESSFUL_PULLS=0
FAILED_PULLS=0
TOTAL_IMAGES=0
FAILED_IMAGES=()

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

# Check Python dependencies
check_python_dependencies() {
  if ! command -v python3 >/dev/null 2>&1; then
    log_error "Python 3 is required for parsing YAML configuration"
    exit 2
  fi

  # Check if PyYAML is installed
  if ! python3 -c "import yaml" >/dev/null 2>&1; then
    log_warn "PyYAML is not installed. Attempting to install it..."
    if command -v pip3 >/dev/null 2>&1; then
      pip3 install pyyaml
      if ! python3 -c "import yaml" >/dev/null 2>&1; then
        log_error "Failed to install PyYAML. Please install it manually: pip3 install pyyaml"
        exit 2
      fi
      log_info "Successfully installed PyYAML"
    else
      log_error "pip3 is not installed. Please install PyYAML manually: pip3 install pyyaml"
      exit 2
    fi
  fi
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

  # Check Python and PyYAML
  check_python_dependencies

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

  local yaml_parser="${SCRIPT_DIR}/yaml_parser.py"

  # Check if the parser script exists
  if [[ ! -f "${yaml_parser}" ]]; then
    log_error "YAML parser script not found: ${yaml_parser}"
    return 1
  fi

  # Check if the parser is executable
  if [[ ! -x "${yaml_parser}" ]]; then
    log_warn "YAML parser script is not executable, setting executable permission..."
    chmod +x "${yaml_parser}"
  fi

  log_info "Loading configuration from: ${CONFIG_FILE}"
  log_info "Debug: Starting YAML parsing..."

  # Run standalone Python script to parse YAML
  local config_output
  log_info "Debug: Running YAML parser script..."

  # Try to run the parser with more explicit error handling
  config_output=$("${yaml_parser}" "${CONFIG_FILE}" 2>&1)
  local parse_result=$?

  # Log the raw output for debugging
  echo "Raw parser output: ${config_output}" >>"${DEBUG_LOG}"

  if [[ ${parse_result} -ne 0 ]]; then
    log_error "Failed to parse configuration file (exit code: ${parse_result})"
    log_error "Parser error: ${config_output}"
    return 1
  fi

  log_info "Debug: Python parsing completed successfully"

  # Clear the image list before populating
  IMAGE_LIST=()

  log_info "Debug: Parser output follows:"
  echo "$config_output" | tee /dev/stderr | grep "^IMAGE:" | head -n 3 >/dev/stderr
  log_info "Debug: End of sample output (showing first 3 images if available)"

  # Process output
  log_info "Debug: Processing parser output..."
  while IFS= read -r line; do
    if [[ "${line}" == CONFIG_ERROR=* ]]; then
      log_error "Error parsing configuration: ${line#CONFIG_ERROR=}"
      return 1
    elif [[ "${line}" == CONFIG_TIMEOUT=* ]]; then
      TIMEOUT="${line#CONFIG_TIMEOUT=}"
      log_info "Debug: Set timeout to ${TIMEOUT}"
    elif [[ "${line}" == CONFIG_RETRIES=* ]]; then
      RETRIES="${line#CONFIG_RETRIES=}"
      log_info "Debug: Set retries to ${RETRIES}"
    elif [[ "${line}" == CONFIG_SKIP_AI=* ]]; then
      SKIP_AI="${line#CONFIG_SKIP_AI=}"
      log_info "Debug: Set skip_ai to ${SKIP_AI}"
    elif [[ "${line}" == CONFIG_SKIP_WINDOWS=* ]]; then
      SKIP_WINDOWS="${line#CONFIG_SKIP_WINDOWS=}"
      log_info "Debug: Set skip_windows to ${SKIP_WINDOWS}"
    elif [[ "${line}" == IMAGE:* ]]; then
      IMAGE_LIST+=("${line}")
    fi
  done <<<"${config_output}"

  log_info "Debug: Finished processing output, found ${#IMAGE_LIST[@]} images"
  return 0
}

# Build default image list (fallback)
build_default_image_list() {
  IMAGE_LIST=(
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

  log_info "Using default image list with ${#IMAGE_LIST[@]} images"
}

# Build image list from configuration
build_image_list() {
  log_info "Debug: Building image list..."

  # Try to load from configuration file
  if parse_config; then
    log_info "Building image list from configuration"
    log_info "Debug: Config parsing successful"
  else
    log_info "Using default hardcoded image list"
    log_info "Debug: Using fallback default image list"
    build_default_image_list
  fi

  log_info "Debug: Before filtering: ${#IMAGE_LIST[@]} images"

  # Apply filters - create a new filtered array
  local -a FILTERED_LIST=()

  for image in "${IMAGE_LIST[@]}"; do
    # Skip AI/ML models if requested
    if [[ "${SKIP_AI}" == "true" && "${image}" == *"IMAGE:MODEL:"* ]]; then
      continue
    fi

    # Skip Windows images if requested
    if [[ "${SKIP_WINDOWS}" == "true" && "${image}" == *"windows/"* ]]; then
      continue
    fi

    FILTERED_LIST+=("${image}")
  done

  # Replace the original array with the filtered one
  IMAGE_LIST=("${FILTERED_LIST[@]}")

  # Count total images
  TOTAL_IMAGES=${#IMAGE_LIST[@]}

  # Apply skip filters in logs if used
  if [[ "${SKIP_AI}" == "true" ]]; then
    log_info "Filtering out AI/ML models"
  fi

  if [[ "${SKIP_WINDOWS}" == "true" ]]; then
    log_info "Filtering out Windows-specific images"
  fi

  log_info "Built image list with ${TOTAL_IMAGES} images"

  # Debug: Print first 3 images for verification
  log_info "Debug: Image list sample (first 3 images):"
  local count=0
  for image in "${IMAGE_LIST[@]}"; do
    ((count++))
    if [[ $count -le 3 ]]; then
      log_info "Debug: Image $count: $image"
    else
      break
    fi
  done
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
    if timeout "${TIMEOUT}" docker pull "${image}"; then
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
  log_info "Debug: Starting pull_images_sequential with ${TOTAL_IMAGES} images"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "DRY-RUN: Would pull ${TOTAL_IMAGES} images sequentially"
    local count=0
    for line in "${IMAGE_LIST[@]}"; do
      local img_name tag friendly_name
      IFS=':' read -r _ _ img_name tag friendly_name <<<"${line}"
      local image="${img_name}:${tag}"
      local display_name="${friendly_name:-${image}}"
      ((count++))
      log_info "  ${count}. Would pull: ${display_name} (${image})"
    done
    log_info "Debug: Dry run completed successfully"
    return 0
  fi

  log_info "Starting sequential pull process for ${TOTAL_IMAGES} images"
  echo

  local current=0

  # Process each image sequentially
  for line in "${IMAGE_LIST[@]}"; do
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
  done

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
  # Create debug log file
  DEBUG_LOG="/tmp/docker-pull-debug.log"
  echo "===== DEBUG LOG START: $(date) =====" >"${DEBUG_LOG}"

  # Print environment details to debug log
  echo "BASH_VERSION: ${BASH_VERSION}" >>"${DEBUG_LOG}"
  echo "PWD: $(pwd)" >>"${DEBUG_LOG}"
  echo "SCRIPT_DIR: ${SCRIPT_DIR}" >>"${DEBUG_LOG}"
  echo "CONFIG_FILE: ${CONFIG_FILE}" >>"${DEBUG_LOG}"

  # Log commands for debugging
  echo "Starting with arguments: $*" >>"${DEBUG_LOG}"

  # Add simple echo for testing
  echo "Script is executing..."
  echo "Debug: Starting main function..."
  echo "Debug log is being written to ${DEBUG_LOG}"

  # Capture output of the main function
  {
    main "$@" 2>&1
    exit_code=$?
  } | tee -a "${DEBUG_LOG}"

  # Log final status
  echo "Debug: Script completed with exit code: ${exit_code}" | tee -a "${DEBUG_LOG}"
  echo "===== DEBUG LOG END: $(date) =====" >>"${DEBUG_LOG}"
  echo "Full debug log is available at: ${DEBUG_LOG}"

  exit ${exit_code}
fi
