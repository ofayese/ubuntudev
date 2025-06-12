#!/usr/bin/env bash
# docker-pull-essentials.sh
# Pulls essential Docker images for development and AI/ML workloads.
# Version: 1.1.0
# Last updated: 2025-06-11
# 
# Usage:
#   ./docker-pull-essentials.sh [OPTIONS]
#
# Options:
#   --dry-run        Show what would be pulled without actually pulling
#   --parallel NUM   Number of parallel pulls (default: 4)
#   --retry NUM      Number of retry attempts per image (default: 2)
#   --timeout SEC    Timeout for each pull in seconds (default: 300)
#   --skip-ai        Skip AI/ML model pulls
#   --skip-windows   Skip Windows-specific images
#   --log-file FILE  Log output to file (default: docker-pull.log)
#   --help           Show this help message
#
# Environment Variables:
#   DOCKER_PULL_TIMEOUT    Override default timeout (seconds)
#   DOCKER_PULL_RETRIES    Override default retry count
#   DOCKER_PULL_PARALLEL   Override default parallel count
#
# Exit Codes:
#   0   Success
#   1   General error
#   2   Docker not available
#   126 Permission denied
#   130 Interrupted by user

set -euo pipefail

declare SCRIPT_NAME
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME

readonly SCRIPT_VERSION="1.1.0"
readonly LOG_PREFIX="[${SCRIPT_NAME}]"

# Default configuration
readonly DEFAULT_TIMEOUT=300
readonly DEFAULT_RETRIES=2
readonly DEFAULT_PARALLEL=4
readonly DEFAULT_LOG_FILE="docker-pull.log"

# Configuration variables
DRY_RUN=false
SKIP_AI=false
SKIP_WINDOWS=false
TIMEOUT="${DOCKER_PULL_TIMEOUT:-${DEFAULT_TIMEOUT}}"
RETRIES="${DOCKER_PULL_RETRIES:-${DEFAULT_RETRIES}}"
PARALLEL="${DOCKER_PULL_PARALLEL:-${DEFAULT_PARALLEL}}"
LOG_FILE="${DEFAULT_LOG_FILE}"

# Counters for reporting
declare -i TOTAL_IMAGES=0
declare -i SUCCESSFUL_PULLS=0
declare -i FAILED_PULLS=0
declare -a FAILED_IMAGES=()

# Temporary files for parallel processing
declare TEMP_DIR
TEMP_DIR="$(mktemp -d)"
readonly TEMP_DIR
readonly PULL_QUEUE="${TEMP_DIR}/pull_queue"
readonly RESULTS_FILE="${TEMP_DIR}/results"

# Cleanup function
cleanup() {
  local exit_code=$?
  if [[ -d "${TEMP_DIR}" ]]; then
    rm -rf "${TEMP_DIR}"
  fi
  return ${exit_code}
}

# Set up cleanup trap
trap cleanup EXIT INT TERM

# Logging functions with timestamps
log_info()  { 
  local msg
  msg="$(date '+%Y-%m-%d %H:%M:%S') ${LOG_PREFIX} INFO: $*"
  echo "${msg}" | tee -a "${LOG_FILE}"
}

log_warn()  { 
  local msg
  msg="$(date '+%Y-%m-%d %H:%M:%S') ${LOG_PREFIX} WARN: $*"
  echo "${msg}" | tee -a "${LOG_FILE}" >&2
}

log_error() { 
  local msg
  msg="$(date '+%Y-%m-%d %H:%M:%S') ${LOG_PREFIX} ERROR: $*"
  echo "${msg}" | tee -a "${LOG_FILE}" >&2
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
  
  # Check available disk space (warn if < 10GB)
  local available_space
  available_space="$(df /var/lib/docker 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")"
  if [[ "${available_space}" -lt 10485760 ]]; then  # 10GB in KB
    log_warn "Low disk space detected. Available: $((available_space / 1024 / 1024))GB"
  fi
  
  log_info "Prerequisites check completed"
}

# Enhanced pull function with retry logic and timeout
pull_image() {
  local image="$1"
  local attempt=1
  local max_attempts=$((RETRIES + 1))
  
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Would pull image: ${image}"
    return 0
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
        sleep $((attempt * 2))  # Exponential backoff
      fi
    fi
    
    ((attempt++))
  done
}

# Enhanced model pull function
pull_model() {
  local model="$1"
  local attempt=1
  local max_attempts=$((RETRIES + 1))
  
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Would pull model: ${model}"
    return 0
  fi
  
  # Check if docker model command exists
  if ! docker model --help >/dev/null 2>&1; then
    log_warn "Docker model command not available, skipping: ${model}"
    return 0
  fi
  
  while [[ ${attempt} -le ${max_attempts} ]]; do
    log_debug "Pulling model ${model} (attempt ${attempt}/${max_attempts})"
    
    if timeout "${TIMEOUT}" docker model pull "${model}" >/dev/null 2>&1; then
      log_info "Successfully pulled model: ${model}"
      return 0
    else
      local exit_code=$?
      if [[ ${attempt} -eq ${max_attempts} ]]; then
        log_error "Failed to pull model ${model} after ${max_attempts} attempts"
        return ${exit_code}
      else
        log_warn "Attempt ${attempt} failed for model ${model}, retrying..."
        sleep $((attempt * 2))
      fi
    fi
    
    ((attempt++))
  done
}

# Parallel processing worker
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
    local result="FAILED"
    
    case "${type}" in
      "IMAGE")
        if pull_image "${image}"; then
          result="SUCCESS"
        fi
        ;;
      "MODEL")
        if pull_model "${image}"; then
          result="SUCCESS"
        fi
        ;;
    esac
    
    echo "${result}:${image}" >> "${results_file}"
    
  done < <(sort -R "${queue_file}" | awk "NR % ${PARALLEL} == ${worker_id}")
}

# Process results and update counters
process_results() {
  if [[ ! -f "${RESULTS_FILE}" ]]; then
    return
  fi
  
  while IFS=: read -r result image; do
    if [[ "${result}" == "SUCCESS" ]]; then
      ((SUCCESSFUL_PULLS++))
    else
      ((FAILED_PULLS++))
      FAILED_IMAGES+=("${image}")
    fi
  done < "${RESULTS_FILE}"
}

# Show usage information
show_help() {
  cat << EOF
${SCRIPT_NAME} v${SCRIPT_VERSION}

Pulls essential Docker images for development and AI/ML workloads.

Usage:
  ${SCRIPT_NAME} [OPTIONS]

Options:
  --dry-run        Show what would be pulled without actually pulling
  --parallel NUM   Number of parallel pulls (default: ${DEFAULT_PARALLEL})
  --retry NUM      Number of retry attempts per image (default: ${DEFAULT_RETRIES})
  --timeout SEC    Timeout for each pull in seconds (default: ${DEFAULT_TIMEOUT})
  --skip-ai        Skip AI/ML model pulls
  --skip-windows   Skip Windows-specific images
  --log-file FILE  Log output to file (default: ${DEFAULT_LOG_FILE})
  --help           Show this help message

Environment Variables:
  DOCKER_PULL_TIMEOUT    Override default timeout (seconds)
  DOCKER_PULL_RETRIES    Override default retry count
  DOCKER_PULL_PARALLEL   Override default parallel count
  DEBUG                  Enable debug logging (true/false)

Examples:
  ${SCRIPT_NAME}                    # Pull all images with defaults
  ${SCRIPT_NAME} --dry-run          # Show what would be pulled
  ${SCRIPT_NAME} --parallel 8       # Use 8 parallel workers
  ${SCRIPT_NAME} --skip-ai          # Skip AI/ML models
  
Exit Codes:
  0   Success
  1   General error
  2   Docker not available
  126 Permission denied
  130 Interrupted by user

EOF
}

# Parse command line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
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
      --help|-h)
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
  
  # Validate numeric arguments
  if ! [[ "${PARALLEL}" =~ ^[0-9]+$ ]] || [[ "${PARALLEL}" -lt 1 ]]; then
    log_error "Invalid parallel count: ${PARALLEL}"
    exit 1
  fi
  
  if ! [[ "${RETRIES}" =~ ^[0-9]+$ ]]; then
    log_error "Invalid retry count: ${RETRIES}"
    exit 1
  fi
  
  if ! [[ "${TIMEOUT}" =~ ^[0-9]+$ ]] || [[ "${TIMEOUT}" -lt 1 ]]; then
    log_error "Invalid timeout: ${TIMEOUT}"
    exit 1
  fi
}

# Build image list
build_image_list() {
  local images=()
  
  # Base OS / Essentials
  images+=(
    "IMAGE:ubuntu:latest"
    "IMAGE:debian:latest"
    "IMAGE:alpine:latest"
  )
  
  # Programming Languages / Runtimes
  images+=(
    "IMAGE:python:latest"
    "IMAGE:node:latest"
    "IMAGE:openjdk:latest"
    "IMAGE:golang:latest"
    "IMAGE:ruby:latest"
    "IMAGE:php:latest"
  )
  
  # Databases
  images+=(
    "IMAGE:postgres:latest"
    "IMAGE:mysql:latest"
    "IMAGE:mariadb:latest"
    "IMAGE:mongo:latest"
    "IMAGE:redis:latest"
    "IMAGE:redis/redis-stack:latest"
    "IMAGE:pgvector/pgvector:latest"
    "IMAGE:myscale/myscaledb:latest"
  )
  
  # Devcontainers Universal
  images+=(
    "IMAGE:mcr.microsoft.com/devcontainers/universal:latest"
  )
  
  # Microsoft / .NET
  images+=(
    "IMAGE:mcr.microsoft.com/dotnet/sdk:9.0"
    "IMAGE:mcr.microsoft.com/dotnet/aspnet:9.0"
    "IMAGE:mcr.microsoft.com/dotnet/runtime:9.0"
    "IMAGE:mcr.microsoft.com/dotnet/framework/aspnet:4.8.1"
    "IMAGE:mcr.microsoft.com/dotnet/framework/runtime:4.8.1"
    "IMAGE:mcr.microsoft.com/powershell:latest"
    "IMAGE:mcr.microsoft.com/azure-powershell:ubuntu-22.04"
  )
  
  # PowerShell test deps
  images+=(
    "IMAGE:mcr.microsoft.com/powershell/test-deps:debian-12"
    "IMAGE:mcr.microsoft.com/powershell/test-deps:lts-ubuntu-22.04"
    "IMAGE:mcr.microsoft.com/powershell/test-deps:preview-alpine-3.16"
    "IMAGE:mcr.microsoft.com/powershell:preview-7.6-ubuntu-24.04"
    "IMAGE:mcr.microsoft.com/powershell:preview-alpine-3.20"
  )
  
  # Web Servers / Proxies
  images+=(
    "IMAGE:nginx:latest"
    "IMAGE:httpd:latest"
    "IMAGE:caddy:latest"
    "IMAGE:haproxy:latest"
  )
  
  # DevOps / CI / Tools
  images+=(
    "IMAGE:docker:latest"
    "IMAGE:registry:latest"
    "IMAGE:portainer/portainer-ce:latest"
    "IMAGE:containrrr/watchtower:latest"
    "IMAGE:bitnami/kubectl:latest"
    "IMAGE:grafana/grafana:latest"
    "IMAGE:sonarqube:latest"
    "IMAGE:jenkins/jenkins:lts-jdk17"
  )
  
  # AI/ML Models (if not skipped)
  if [[ "${SKIP_AI}" != "true" ]]; then
    images+=(
      "IMAGE:ai/llama3.2:latest"
      "IMAGE:ai/mistral:latest"
      "IMAGE:ai/deepcoder-preview"
      "MODEL:ai/smollm2:latest"
      "MODEL:ai/llama3.3:latest"
      "MODEL:ai/phi4:latest"
      "MODEL:ai/qwen2.5:latest"
      "MODEL:ai/mxbai-embed-large:latest"
    )
  fi
  
  # Other Utilities
  images+=(
    "IMAGE:curlimages/curl:latest"
    "IMAGE:influxdb:latest"
    "IMAGE:vault:latest"
    "IMAGE:consul:latest"
    "IMAGE:elasticsearch:latest"
    "IMAGE:maven:latest"
  )
  
  # Windows-specific images (if not skipped and not in WSL)
  if [[ "${SKIP_WINDOWS}" != "true" ]] && [[ "${WSL_ENV:-false}" != "true" ]]; then
    images+=(
      "IMAGE:mcr.microsoft.com/windows/server:ltsc2022"
      "IMAGE:mcr.microsoft.com/windows/nanoserver:ltsc2025"
    )
  fi
  
  # Write to queue file
  printf '%s\n' "${images[@]}" > "${PULL_QUEUE}"
  TOTAL_IMAGES=${#images[@]}
}

# Generate summary report
generate_report() {
  echo
  log_info "=== PULL SUMMARY ==="
  log_info "Total images/models: ${TOTAL_IMAGES}"
  log_info "Successful pulls: ${SUCCESSFUL_PULLS}"
  log_info "Failed pulls: ${FAILED_PULLS}"
  
  if [[ ${FAILED_PULLS} -gt 0 ]]; then
    log_warn "Failed images/models:"
    for failed in "${FAILED_IMAGES[@]}"; do
      log_warn "  - ${failed}"
    done
  fi
  
  # Calculate and display execution time
  local end_time
  end_time="$(date +%s)"
  local duration=$((end_time - START_TIME))
  log_info "Execution time: ${duration} seconds"
  
  # Disk usage info
  local docker_size
  docker_size="$(docker system df --format 'table {{.Type}}\t{{.Size}}' | grep Images | awk '{print $2}' || echo "unknown")"
  log_info "Docker images total size: ${docker_size}"
}

# Main execution function
main() {
  local START_TIME
  START_TIME="$(date +%s)"
  
  # Parse arguments
  parse_args "$@"
  
  # Initialize log file
  echo "=== Docker Pull Script Log - $(date) ===" > "${LOG_FILE}"
  
  log_info "Starting Docker image pulls (v${SCRIPT_VERSION})"
  log_info "Configuration: parallel=${PARALLEL}, retries=${RETRIES}, timeout=${TIMEOUT}s"
  log_info "Options: dry-run=${DRY_RUN}, skip-ai=${SKIP_AI}, skip-windows=${SKIP_WINDOWS}"
  
  # Run checks
  check_prerequisites
  
  # Build image list
  build_image_list
  
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "DRY RUN - Images that would be pulled:"
    while IFS=: read -r type image; do
      echo "  ${type}: ${image}"
    done < "${PULL_QUEUE}"
    exit 0
  fi
  
  # Start parallel workers
  log_info "Starting ${PARALLEL} parallel workers..."
  local pids=()
  
  for ((i=0; i<PARALLEL; i++)); do
    pull_worker "${i}" "${PULL_QUEUE}" "${RESULTS_FILE}" &
    pids+=($!)
  done
  
  # Monitor progress
  local completed=0
  while [[ ${completed} -lt ${TOTAL_IMAGES} ]]; do
    if [[ -f "${RESULTS_FILE}" ]]; then
      completed=$(wc -l < "${RESULTS_FILE}" 2>/dev/null || echo 0)
    fi
    show_progress "${completed}" "${TOTAL_IMAGES}"
    sleep 2
  done
  
  # Wait for all workers to complete
  for pid in "${pids[@]}"; do
    wait "${pid}"
  done
  
  echo  # New line after progress indicator
  
  # Process results
  process_results
  
  # Generate final report
  generate_report
  
  # Exit with appropriate code
  if [[ ${FAILED_PULLS} -gt 0 ]]; then
    log_warn "Some pulls failed. Check the log for details."
    exit 1
  else
    log_info "All pulls completed successfully!"
    exit 0
  fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
