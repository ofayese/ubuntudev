#!/usr/bin/env bash
# util-log.sh - Unified logging and error handling utilities
set -euo pipefail

# --- Log file configuration ---
LOG_DIR="/var/log"
MAIN_LOG="ubuntu-dev-tools.log"
SUMMARY_LOG="ubuntu-dev-setup-summary.txt"
DEFAULT_LOG_PATH="$LOG_DIR/$MAIN_LOG"

# --- ANSI color codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Initialize logging ---
init_logging() {
  local log_path="${1:-$DEFAULT_LOG_PATH}"
  # Create log directory if it doesn't exist
  sudo mkdir -p "$(dirname "$log_path")" 2>/dev/null || true
  sudo touch "$log_path" 2>/dev/null || true
  sudo chmod a+w "$log_path" 2>/dev/null || true
  
  # Begin logging
  echo "=== [$(basename "$0")] Started at $(date) ===" | tee -a "$log_path"
}

# --- Log message with level and color ---
log_message() {
  local level="$1"
  local message="$2"
  local log_path="${3:-$DEFAULT_LOG_PATH}"
  local color prefix
  
  case "$level" in
    "INFO")
      color="$BLUE"
      prefix="ℹ️ "
      ;;
    "SUCCESS")
      color="$GREEN"
      prefix="✅ "
      ;;
    "WARNING")
      color="$YELLOW"
      prefix="⚠️ "
      ;;
    "ERROR")
      color="$RED"
      prefix="❌ "
      ;;
    "DEBUG")
      color="$PURPLE"
      prefix="🔍 "
      ;;
    *)
      color="$NC"
      prefix=""
      ;;
  esac
  
  echo -e "${color}${prefix}${message}${NC}" | tee -a "$log_path"
}

# --- Convenience logging functions ---
log_info() {
  log_message "INFO" "$1" "${2:-$DEFAULT_LOG_PATH}"
}

log_success() {
  log_message "SUCCESS" "$1" "${2:-$DEFAULT_LOG_PATH}"
}

log_warning() {
  log_message "WARNING" "$1" "${2:-$DEFAULT_LOG_PATH}"
}

log_error() {
  log_message "ERROR" "$1" "${2:-$DEFAULT_LOG_PATH}"
}

log_debug() {
  log_message "DEBUG" "$1" "${2:-$DEFAULT_LOG_PATH}"
}

# --- Function to log command execution ---
log_cmd() {
  local cmd="$1"
  local desc="${2:-Executing command}"
  local log_path="${3:-$DEFAULT_LOG_PATH}"
  
  log_info "$desc: $cmd" "$log_path"
  if eval "$cmd"; then
    log_success "Command succeeded: $cmd" "$log_path"
    return 0
  else
    local exit_code="$?"
    log_error "Command failed ($exit_code): $cmd" "$log_path"
    return "$exit_code"
  fi
}

# --- Runtime error handler ---
handle_error() {
  local exit_code="$?"
  local line_no="$1"
  
  log_error "Error in $(basename "$0") at line $line_no (exit code: $exit_code)" 
  
  # You can add more context or recovery actions here
  return "$exit_code"
}

# --- Trap for unhandled errors ---
set_error_trap() {
  trap 'handle_error $LINENO' ERR
}

# --- End logging section ---
finish_logging() {
  local log_path="${1:-$DEFAULT_LOG_PATH}"
  echo "=== [$(basename "$0")] Finished at $(date) ===" | tee -a "$log_path"
}

# --- Usage example ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  init_logging
  log_info "This is an info message"
  log_success "This is a success message"
  log_warning "This is a warning message"
  log_error "This is an error message"
  log_debug "This is a debug message"
  finish_logging
fi
