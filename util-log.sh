#!/usr/bin/env bash
# util-log.sh - Unified logging and error handling utilities
set -euo pipefail

# Guard against multiple sourcing
if [[ "${UTIL_LOG_LOADED:-}" == "true" ]]; then
  return 0
fi
readonly UTIL_LOG_LOADED="true"

DEFAULT_LOG_PATH="/var/log/ubuntu-dev-tools.log"
LOG_PATH="${LOG_PATH:-$DEFAULT_LOG_PATH}"

log_info()    { echo -e "\e[34m[INFO]\e[0m $*" | tee -a "${LOG_PATH}"; }
log_success() { echo -e "\e[32m[SUCCESS]\e[0m $*" | tee -a "${LOG_PATH}"; }
log_warning() { echo -e "\e[33m[WARN]\e[0m $*" | tee -a "${LOG_PATH}"; }
log_error()   { echo -e "\e[31m[ERROR]\e[0m $*" | tee -a "${LOG_PATH}" >&2; }

# Progress indicator functions
show_progress() {
  local current="$1"
  local total="$2"
  local task="${3:-Processing}"
  local percentage=$((current * 100 / total))
  local bar_length=30
  local filled_length=$((percentage * bar_length / 100))
  
  # Create progress bar
  local bar=""
  for ((i=0; i<filled_length; i++)); do bar+="█"; done
  for ((i=filled_length; i<bar_length; i++)); do bar+="░"; done
  
  printf "\r\e[34m[PROGRESS]\e[0m %s: [%s] %d%% (%d/%d)" "${task}" "${bar}" "${percentage}" "${current}" "${total}"
  
  # Add newline if complete
  if [[ "${current}" -eq "${total}" ]]; then
    echo ""
    echo "$(date '+%Y-%m-%d %H:%M:%S') [PROGRESS] ${task}: 100% (${total}/${total})" >> "${LOG_PATH}"
  fi
}

# Spinner for indeterminate progress
start_spinner() {
  local task="${1:-Processing}"
  local spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
  local delay=0.1
  
  # Store spinner PID in a file for cleanup
  local spinner_pid_file="/tmp/.spinner_pid_$$"
  
  (
    local i=0
    while true; do
      printf "\r\e[34m[WORKING]\e[0m %s %s" "${task}" "${spinner_chars:$i:1}"
      sleep "${delay}"
      i=$(( (i + 1) % ${#spinner_chars} ))
    done
  ) &
  
  echo $! > "${spinner_pid_file}"
}

stop_spinner() {
  local task="${1:-Processing}"
  local spinner_pid_file="/tmp/.spinner_pid_$$"
  
  if [[ -f "${spinner_pid_file}" ]]; then
    local spinner_pid
    spinner_pid=$(cat "${spinner_pid_file}")
    kill "${spinner_pid}" 2>/dev/null || true
    rm -f "${spinner_pid_file}"
    printf "\r\e[32m[COMPLETE]\e[0m %s ✓                    \n" "${task}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [COMPLETE] ${task}" >> "${LOG_PATH}"
  fi
}

# Execute command with progress indication
log_cmd_with_progress() {
  local cmd="$1"
  local desc="${2:-Running command}"
  local timeout="${3:-300}"  # 5 minutes default timeout
  
  log_info "$desc: $cmd"
  start_spinner "$desc"
  
  if timeout "${timeout}" bash -c "$cmd" >/dev/null 2>&1; then
    stop_spinner "$desc"
    log_success "$desc completed successfully"
    return 0
  else
    local exit_code=$?
    stop_spinner "$desc"
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

# Progress summary for completed operations
show_completion_summary() {
  local operation="$1"
  local duration="${2:-}"
  local status="${3:-SUCCESS}"
  
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  if [[ "$status" == "SUCCESS" ]]; then
    echo "║ ✅ $operation COMPLETED SUCCESSFULLY"
  else
    echo "║ ❌ $operation FAILED"
  fi
  
  if [[ -n "$duration" ]]; then
    echo "║ ⏱️  Duration: $duration"
  fi
  echo "║ 📄 Log file: $LOG_PATH"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
}
