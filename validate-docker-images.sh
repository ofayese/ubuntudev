#!/usr/bin/env bash
# validate-docker-images.sh
# Validates that pulled Docker images are accessible and functional
# Version: 1.0.0
# Last updated: 2025-06-11

set -euo pipefail

declare SCRIPT_NAME
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME

readonly SCRIPT_VERSION="1.0.0"
readonly LOG_PREFIX="[${SCRIPT_NAME}]"
readonly LOG_FILE="docker-validation.log"

# Test results
declare -i TOTAL_TESTS=0
declare -i PASSED_TESTS=0
declare -i FAILED_TESTS=0
declare -a FAILED_IMAGES=()

# Logging functions
log_info()  { 
  local msg
  msg="$(date '+%Y-%m-%d %H:%M:%S') ${LOG_PREFIX} INFO: $*"
  echo "${msg}" | tee -a "${LOG_FILE}"
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

# Test if image exists and can be inspected
test_image() {
  local image="$1"
  ((TOTAL_TESTS++))
  
  log_info "Testing image: ${image}"
  
  # Check if image exists locally
  if ! docker image inspect "${image}" >/dev/null 2>&1; then
    log_error "Image not found locally: ${image}"
    ((FAILED_TESTS++))
    FAILED_IMAGES+=("${image}")
    return 1
  fi
  
  # Try to run a basic command
  local test_command="echo 'test'"
  case "${image}" in
    *alpine*)
      test_command="/bin/sh -c 'echo test'"
      ;;
    *ubuntu*|*debian*)
      test_command="/bin/bash -c 'echo test'"
      ;;
    *python*)
      test_command="python -c 'print(\"test\")'"
      ;;
    *node*)
      test_command="node -e 'console.log(\"test\")'"
      ;;
    *openjdk*|*java*)
      test_command="java -version"
      ;;
    *golang*)
      test_command="go version"
      ;;
    *ruby*)
      test_command="ruby -e 'puts \"test\"'"
      ;;
    *php*)
      test_command="php -r 'echo \"test\";'"
      ;;
    *postgres*)
      test_command="postgres --version"
      ;;
    *mysql*)
      test_command="mysql --version"
      ;;
    *nginx*)
      test_command="nginx -v"
      ;;
    *powershell*)
      test_command="pwsh -c 'Write-Host test'"
      ;;
    *)
      test_command="echo test"
      ;;
  esac
  
  # Run test command with timeout
  if timeout 30 docker run --rm "${image}" ${test_command} >/dev/null 2>&1; then
    log_success "Image test passed: ${image}"
    ((PASSED_TESTS++))
    return 0
  else
    log_error "Image test failed: ${image}"
    ((FAILED_TESTS++))
    FAILED_IMAGES+=("${image}")
    return 1
  fi
}

# Get list of essential images
get_essential_images() {
  cat << 'EOF'
ubuntu:latest
debian:latest
alpine:latest
python:latest
node:latest
openjdk:latest
golang:latest
ruby:latest
php:latest
postgres:latest
mysql:latest
mariadb:latest
mongo:latest
redis:latest
nginx:latest
httpd:latest
caddy:latest
mcr.microsoft.com/dotnet/sdk:9.0
mcr.microsoft.com/dotnet/aspnet:9.0
mcr.microsoft.com/powershell:latest
docker:latest
registry:latest
grafana/grafana:latest
jenkins/jenkins:lts-jdk17
EOF
}

# Generate validation report
generate_report() {
  echo
  log_info "=== VALIDATION SUMMARY ==="
  log_info "Total tests: ${TOTAL_TESTS}"
  log_info "Passed: ${PASSED_TESTS}"
  log_info "Failed: ${FAILED_TESTS}"
  
  if [[ ${FAILED_TESTS} -gt 0 ]]; then
    log_error "Failed images:"
    for failed in "${FAILED_IMAGES[@]}"; do
      log_error "  - ${failed}"
    done
  fi
  
  local success_rate
  success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
  log_info "Success rate: ${success_rate}%"
}

# Main function
main() {
  log_info "Starting Docker image validation (v${SCRIPT_VERSION})"
  
  # Check Docker availability
  if ! command -v docker >/dev/null 2>&1; then
    log_error "Docker not found"
    exit 2
  fi
  
  if ! docker info >/dev/null 2>&1; then
    log_error "Docker daemon not accessible"
    exit 2
  fi
  
  # Test each essential image
  while IFS= read -r image; do
    [[ -n "${image}" ]] && test_image "${image}"
  done < <(get_essential_images)
  
  # Generate report
  generate_report
  
  # Exit with appropriate code
  if [[ ${FAILED_TESTS} -gt 0 ]]; then
    exit 1
  else
    log_info "All validation tests passed!"
    exit 0
  fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
