#!/usr/bin/env bash
# util-log.sh - Unified logging and error handling utilities
set -euo pipefail

DEFAULT_LOG_PATH="/var/log/ubuntu-dev-tools.log"
LOG_PATH="${LOG_PATH:-$DEFAULT_LOG_PATH}"

log_info()    { echo -e "\e[34m[INFO]\e[0m $*" | tee -a "${LOG_PATH}"; }
log_success() { echo -e "\e[32m[SUCCESS]\e[0m $*" | tee -a "${LOG_PATH}"; }
log_warning() { echo -e "\e[33m[WARN]\e[0m $*" | tee -a "${LOG_PATH}"; }
log_error()   { echo -e "\e[31m[ERROR]\e[0m $*" | tee -a "${LOG_PATH}" >&2; }

# Execute command with logging
log_cmd() {
  local cmd="$1"
  local desc="${2:-Running command}"
  log_info "$desc: $cmd"
  if eval "$cmd"; then
    log_success "$desc completed successfully"
    return 0
  else
    local exit_code=$?
    log_error "$desc failed (exit code: $exit_code)"
    return $exit_code
  fi
}

init_logging() {
  LOG_PATH="${1:-$DEFAULT_LOG_PATH}"
  sudo mkdir -p "$(dirname -- "$LOG_PATH")" 2>/dev/null || true
  sudo touch "$LOG_PATH" 2>/dev/null || true
  sudo chmod a+w "$LOG_PATH" 2>/dev/null || true
  echo "=== [$(basename -- "$0")] Started at $(date) ===" | tee -a "${LOG_PATH}"
}

set_error_trap() {
  trap 'handle_error $LINENO' ERR
}

handle_error() {
  local exit_code=$?
  local line_no="$1"
  log_error "Error in $(basename -- "$0") at line $line_no (exit code $exit_code)"
  log_warning "An issue occurred. You can resume with --resume after fixing."
  return "$exit_code"
}

finish_logging() {
  echo "=== [$(basename -- "$0")] Finished at $(date) ===" | tee -a "${LOG_PATH}"
}
