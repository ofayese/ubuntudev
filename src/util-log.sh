#!/usr/bin/env bash
# Utility: util-log.sh
# Description: Unified logging and error handling utilities
# Last Updated: 2025-06-14
# Version: 1.0.1

set -euo pipefail

# Load guard to prevent multiple sourcing
if [[ -n "${UTIL_LOG_SH_LOADED:-}" ]]; then
  return 0
fi
readonly UTIL_LOG_SH_LOADED=1

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

  # Async logging support (only declare once globally)
  if [[ -z "${ASYNC_LOGGING:-}" ]]; then
    ASYNC_LOGGING="false"
    readonly ASYNC_LOGGING
  fi
}

# Initialize global variables
_init_global_vars

# No-op spinner cleanup for compatibility with scripts expecting this function
cleanup_all_spinners() {
  :
}

# ------------------------------------------------------------------------------
# Logging Configuration
# ------------------------------------------------------------------------------

# Default log path and configuration
if [[ -z "${DEFAULT_LOG_PATH:-}" ]]; then
  readonly DEFAULT_LOG_PATH="${HOME}/.local/share/ubuntu-dev-tools/logs/ubuntu-dev-tools.log"
fi
if [[ -z "${LOG_PATH:-}" ]]; then
  LOG_PATH="$DEFAULT_LOG_PATH"
  # Note: LOG_PATH is intentionally not readonly as it can be modified during runtime
fi

# Asynchronous logging configuration
if [[ -z "${LOG_BUFFER_SIZE:-}" ]]; then
  readonly LOG_BUFFER_SIZE=100
fi
if [[ -z "${LOG_FLUSH_INTERVAL:-}" ]]; then
  readonly LOG_FLUSH_INTERVAL=5
fi
if [[ -z "${MAX_LOG_ERRORS:-}" ]]; then
  readonly MAX_LOG_ERRORS=5
fi

# Logging state variables - initialize only if not already set
if [[ -z "${LOG_BUFFER_INITIALIZED:-}" ]]; then
  declare -a LOG_BUFFER=()
  declare -i LOG_BUFFER_COUNT=0
  declare -i LOG_LAST_FLUSH=0
  declare -i LOG_ERROR_COUNT=0
  declare LOG_FLUSHER_PID=""
  declare LOG_FALLBACK_ACTIVE=false
  LOG_BUFFER_INITIALIZED="true"
fi

# ------------------------------------------------------------------------------
# Core Logging Functions
# ------------------------------------------------------------------------------

# Generate timestamp for consistent logging format
_get_log_timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

# Format log message with consistent structure
_format_log_message() {
  local level="$1"
  local message="$2"
  local timestamp
  timestamp="$(_get_log_timestamp)"

  echo "[$timestamp] [$level] $message"
}

# Output log message with color and optional file logging
_output_log_message() {
  local level="$1"
  local color="$2"
  local message="$3"
  local use_stderr="${4:-false}"
  local timestamp
  timestamp="$(_get_log_timestamp)"

  local formatted_message
  formatted_message="\e[${color}m[$timestamp] [$level]\e[0m $message"

  if [[ "$use_stderr" == "true" ]]; then
    echo -e "$formatted_message" >&2
  else
    echo -e "$formatted_message"
  fi

  # Log to file without color codes
  echo "[$timestamp] [$level] $message" >>"${LOG_PATH}" 2>/dev/null || true
}

# Route to appropriate logging method based on async setting
_route_log_message() {
  local level="$1"
  local color="$2"
  local message="$3"
  local use_stderr="${4:-false}"

  if [[ "${ASYNC_LOGGING}" == "true" ]]; then
    "_log_${level,,}_async" "$message"
  else
    _output_log_message "$level" "$color" "$message" "$use_stderr"
  fi
}

# Standard logging functions with improved consistency
log_info() {
  _route_log_message "INFO" "34" "$*" "false"
}

log_success() {
  _route_log_message "SUCCESS" "32" "$*" "false"
}

log_warning() {
  _route_log_message "WARN" "33" "$*" "true"
}

log_error() {
  _route_log_message "ERROR" "31" "$*" "true"
}

log_debug() {
  if [[ "${DEBUG_LOGGING:-false}" == "true" ]]; then
    _route_log_message "DEBUG" "36" "$*" "false"
  fi
}

# ------------------------------------------------------------------------------
# Asynchronous Logging Functions
# ------------------------------------------------------------------------------

# Create async logging function with standardized pattern
_create_async_log_function() {
  local level="$1"
  local color="$2"
  local use_stderr="${3:-false}"

  eval "_log_${level,,}_async() {
    local message=\"\$*\"
    local timestamp
    timestamp=\"\$(_get_log_timestamp)\"
    local formatted_message=\"[\$timestamp] [$level] \$message\"
    
    if [[ \"$use_stderr\" == \"true\" ]]; then
      echo -e \"\e[${color}m[$level]\e[0m \$message\" >&2
    else
      echo -e \"\e[${color}m[$level]\e[0m \$message\"
    fi
    
    _add_to_log_buffer \"\$formatted_message\"
    
    # Force immediate flush for errors
    if [[ \"$level\" == \"ERROR\" ]]; then
      _flush_log_buffer
    fi
  }"
}

# Generate async logging functions
_create_async_log_function "INFO" "34" "false"
_create_async_log_function "SUCCESS" "32" "false"
_create_async_log_function "WARN" "33" "true"
_create_async_log_function "ERROR" "31" "true"
_create_async_log_function "DEBUG" "36" "false"

# ------------------------------------------------------------------------------
# Asynchronous Logging Management
# ------------------------------------------------------------------------------

# Initialize asynchronous logging system
init_async_logging() {
  if [[ "${ASYNC_LOGGING}" == "true" ]]; then
    _start_log_flusher &
    LOG_FLUSHER_PID=$!
  fi
}

# Start background log flusher process
_start_log_flusher() {
  while true; do
    sleep "$LOG_FLUSH_INTERVAL"
    _flush_log_buffer
  done
}

# Clean up asynchronous logging resources
cleanup_async_logging() {
  # Flush remaining buffer
  _flush_log_buffer

  # Stop log flusher if running
  if [[ -n "${LOG_FLUSHER_PID:-}" ]] && kill -0 "$LOG_FLUSHER_PID" 2>/dev/null; then
    kill "$LOG_FLUSHER_PID" 2>/dev/null || true
  fi
}

# Add message to log buffer
_add_to_log_buffer() {
  local message="$1"

  LOG_BUFFER[LOG_BUFFER_COUNT]="$message"
  ((LOG_BUFFER_COUNT++))

  # Flush if buffer is full
  if [[ $LOG_BUFFER_COUNT -ge $LOG_BUFFER_SIZE ]]; then
    _flush_log_buffer
  fi
}

# Flush log buffer to file
_flush_log_buffer() {
  if [[ $LOG_BUFFER_COUNT -eq 0 ]]; then
    return 0
  fi

  # Batch write to log file
  {
    local i
    for ((i = 0; i < LOG_BUFFER_COUNT; i++)); do
      echo "${LOG_BUFFER[i]}"
    done
  } >>"${LOG_PATH}" 2>/dev/null || true

  # Clear buffer
  LOG_BUFFER=()
  LOG_BUFFER_COUNT=0
}

# ------------------------------------------------------------------------------
# Command Execution Functions
# ------------------------------------------------------------------------------

# Execute command with comprehensive logging and timeout handling
log_cmd() {
  local cmd="$1"
  local description="${2:-Running command}"
  local timeout="${3:-300}" # Default timeout of 5 minutes
  local start_time end_time exit_code

  log_info "$description: $cmd"
  start_time="$(_get_log_timestamp)"

  # Execute with timeout to prevent hanging
  if timeout --foreground "$timeout" bash -c "$cmd"; then
    end_time="$(_get_log_timestamp)"
    log_success "[$end_time] $description completed successfully"
    return 0
  else
    exit_code=$?
    end_time="$(_get_log_timestamp)"

    if [[ $exit_code -eq 124 ]]; then
      log_error "[$end_time] $description timed out after ${timeout}s"
    else
      log_error "[$end_time] $description failed (exit code: $exit_code)"
    fi
    return $exit_code
  fi
}

# ------------------------------------------------------------------------------
# Progress Tracking Functions
# ------------------------------------------------------------------------------

# Constants for progress display
readonly PROGRESS_HEADER_CHAR="═"
readonly PROGRESS_FOOTER_CHAR="─"
readonly PROGRESS_HEADER_WIDTH=72

# Generate progress header with consistent width
_generate_progress_header() {
  printf "${PROGRESS_HEADER_CHAR}%.0s" $(seq 1 $PROGRESS_HEADER_WIDTH)
}

# Generate progress footer with consistent width
_generate_progress_footer() {
  printf "${PROGRESS_FOOTER_CHAR}%.0s" $(seq 1 $PROGRESS_HEADER_WIDTH)
}

# Calculate percentage with safety check
_calculate_percentage() {
  local current="$1"
  local total="$2"

  if [[ -n "$total" && "$total" -gt 0 ]]; then
    echo $((current * 100 / total))
  else
    echo 0
  fi
}

# Record step start time
_record_step_start_time() {
  local step_id="$1"
  local start_time
  start_time=$(date +%s)
  eval "_step_start_time_${step_id}=$start_time"
}

# Calculate and format duration
_calculate_step_duration() {
  local step_id="$1"
  local var_name="_step_start_time_${step_id}"
  local start_time="${!var_name:-}"

  if [[ -n "$start_time" ]]; then
    local end_time elapsed
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))

    # Format duration
    if [[ $elapsed -ge 3600 ]]; then
      echo "$((elapsed / 3600))h $(((elapsed % 3600) / 60))m $((elapsed % 60))s"
    elif [[ $elapsed -ge 60 ]]; then
      echo "$((elapsed / 60))m $((elapsed % 60))s"
    else
      echo "${elapsed}s"
    fi
  fi
}

# Progress indicator with timestamped output
show_progress() {
  local current="$1"
  local total="$2"
  local task="${3:-Processing}"
  local percentage
  local timestamp

  percentage="$(_calculate_percentage "$current" "$total")"
  timestamp="$(_get_log_timestamp)"

  echo -e "\e[34m[$timestamp] [PROGRESS]\e[0m $task: $percentage% ($current/$total) complete"
  echo "$timestamp [PROGRESS] $task: $percentage% ($current/$total)" >>"${LOG_PATH}" 2>/dev/null || true
}

# Enhanced step tracking with timestamps and duration
log_step_start() {
  local step="$1"
  local current="$2"
  local total="$3"
  local percentage timestamp header

  percentage="$(_calculate_percentage "$current" "$total")"
  timestamp="$(_get_log_timestamp)"
  header="$(_generate_progress_header)"

  echo ""
  echo -e "\e[1;36m$header\e[0m"
  echo -e "\e[1;36m [$timestamp] [$current/$total] - $percentage% - STARTING: $step\e[0m"
  echo -e "\e[1;36m$header\e[0m"

  # Record start time for duration calculation
  _record_step_start_time "$current"

  # Log to file as well
  {
    echo "$header"
    echo "[$timestamp] [$current/$total] - $percentage% - STARTING: $step"
    echo "$header"
  } >>"${LOG_PATH}" 2>/dev/null || true
}

log_step_complete() {
  local step="$1"
  local current="$2"
  local total="$3"
  local status="${4:-SUCCESS}"
  local percentage timestamp duration footer status_color status_icon

  percentage="$(_calculate_percentage "$current" "$total")"
  timestamp="$(_get_log_timestamp)"
  duration="$(_calculate_step_duration "$current")"
  footer="$(_generate_progress_footer)"

  # Status formatting
  if [[ "$status" == "SUCCESS" ]]; then
    status_color="\e[1;32m"
    status_icon="✓"
  else
    status_color="\e[1;31m"
    status_icon="✗"
  fi

  echo ""
  echo -e "$status_color$status_icon [$timestamp] $status: $step\e[0m"

  if [[ -n "$duration" ]]; then
    echo -e "  Duration: $duration"
  fi
  echo -e "  Finished at: $timestamp"
  echo -e "  Progress: $percentage% ($current/$total) complete"
  echo -e "\e[90m$footer\e[0m"

  # Log to file as well
  {
    echo ""
    echo "[$timestamp] STATUS: $status - $step"
    if [[ -n "$duration" ]]; then
      echo "Duration: $duration"
    fi
    echo "Progress: $percentage% ($current/$total) complete"
    echo "$footer"
  } >>"${LOG_PATH}" 2>/dev/null || true
}

# Function to report sub-step progress within a major step
log_substep() {
  local substep="$1"
  local status="${2:-IN PROGRESS}"
  local details="${3:-}"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  local status_icon="🔄"
  local status_color="\e[0;36m" # cyan for in progress

  case "$status" in
  "SUCCESS")
    status_icon="✓"
    status_color="\e[0;32m" # green
    ;;
  "FAILED")
    status_icon="✗"
    status_color="\e[0;31m" # red
    ;;
  "WARNING")
    status_icon="⚠️"
    status_color="\e[0;33m" # yellow
    ;;
  esac

  echo -e "  $status_color$status_icon [$timestamp] $substep\e[0m"
  if [[ -n "$details" ]]; then
    echo -e "    $details"
  fi

  # Log to file as well
  {
    echo "  [$timestamp] $status_icon $substep"
    if [[ -n "$details" ]]; then
      echo "    $details"
    fi
  } >>"${LOG_PATH}" 2>/dev/null || true
}

# Execute command with timeout and progress reporting
run_with_timeout() {
  local cmd="$1"
  local description="$2"
  local timeout="${3:-300}" # Default 5 minutes
  local current="${4:-}"
  local total="${5:-}"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  log_substep "$description" "IN PROGRESS"

  local temp_output
  temp_output=$(mktemp)
  local start_time
  start_time=$(date +%s)

  # Run the command with timeout and capture output in real time
  if timeout --foreground "$timeout" bash -c "$cmd" 2>&1 | tee "$temp_output"; then
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local end_timestamp
    end_timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Format duration for display
    local duration_str=""
    if [[ $duration -ge 60 ]]; then
      duration_str="$((duration / 60))m $((duration % 60))s"
    else
      duration_str="${duration}s"
    fi

    log_substep "$description" "SUCCESS" "Completed in $duration_str"
    rm -f "$temp_output"
    return 0
  else
    local exit_code=$?
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local end_timestamp
    end_timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Format duration for display
    local duration_str=""
    if [[ $duration -ge 60 ]]; then
      duration_str="$((duration / 60))m $((duration % 60))s"
    else
      duration_str="${duration}s"
    fi

    # Check if it was a timeout
    if [[ $exit_code -eq 124 ]]; then
      log_substep "$description" "FAILED" "Timed out after ${timeout}s"
    else
      log_substep "$description" "FAILED" "Exit code: $exit_code (after $duration_str)"
    fi

    # Show last few lines from output
    if [[ -f "$temp_output" && -s "$temp_output" ]]; then
      echo -e "    Last output:"
      tail -n 5 "$temp_output" | while IFS= read -r line; do
        echo "      $line"
      done
    fi

    rm -f "$temp_output"
    return $exit_code
  fi
}

# New improved progress logging functions (replacing spinners)
log_progress_start() {
  local task="$1"
  local current="${2:-}"
  local total="${3:-}"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  if [[ -n "$current" && -n "$total" ]]; then
    local percentage
    percentage=$((current * 100 / total))
    local header
    header=$(printf '═%.0s' $(seq 1 72))

    echo ""
    echo -e "\e[1;36m$header\e[0m"
    echo -e "\e[1;36m [$timestamp] STARTING STEP [$current/$total] ($percentage%): $task\e[0m"
    echo -e "\e[1;36m$header\e[0m"
  else
    local header
    header=$(printf '═%.0s' $(seq 1 72))

    echo ""
    echo -e "\e[1;36m$header\e[0m"
    echo -e "\e[1;36m [$timestamp] STARTING: $task\e[0m"
    echo -e "\e[1;36m$header\e[0m"
  fi

  # Record start time for duration calculation
  if [[ -n "$current" ]]; then
    local _progress_start_time_var
    _progress_start_time_var=$(date +%s)
    eval "export _progress_start_time_$current=$_progress_start_time_var"
  else
    local _progress_start_time_var
    _progress_start_time_var=$(date +%s)
    export _progress_start_time=$_progress_start_time_var
  fi
}

log_progress_update() {
  local task="$1"
  local message="$2"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  echo -e "[$timestamp] $task: $message"
}

log_progress_complete() {
  local task="$1"
  local status="${2:-SUCCESS}"
  local current="${3:-}"
  local total="${4:-}"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  local duration=""
  local start_time

  # Get the appropriate start time variable
  if [[ -n "$current" ]]; then
    eval "start_time=\${_progress_start_time_$current:-}"
  else
    start_time="${_progress_start_time:-}"
  fi

  # Calculate duration if we have a start time
  if [[ -n "$start_time" ]]; then
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    # Format duration
    if [[ $elapsed -ge 3600 ]]; then
      duration="$((elapsed / 3600))h $(((elapsed % 3600) / 60))m $((elapsed % 60))s"
    elif [[ $elapsed -ge 60 ]]; then
      duration="$((elapsed / 60))m $((elapsed % 60))s"
    else
      duration="${elapsed}s"
    fi
  fi

  local footer=$(printf '─%.0s' $(seq 1 72))

  if [[ -n "$current" && -n "$total" ]]; then
    local percentage=$((current * 100 / total))

    echo ""
    if [[ "$status" == "SUCCESS" ]]; then
      echo -e "\e[1;32m✓ [$timestamp] COMPLETED STEP [$current/$total] ($percentage%): $task\e[0m"
    else
      echo -e "\e[1;31m✗ [$timestamp] FAILED STEP [$current/$total] ($percentage%): $task\e[0m"
    fi

    if [[ -n "$duration" ]]; then
      echo -e "  Duration: $duration"
    fi
    echo -e "\e[90m$footer\e[0m"
  else
    echo ""
    if [[ "$status" == "SUCCESS" ]]; then
      echo -e "\e[1;32m✓ [$timestamp] COMPLETED: $task\e[0m"
    else
      echo -e "\e[1;31m✗ [$timestamp] FAILED: $task\e[0m"
    fi

    if [[ -n "$duration" ]]; then
      echo -e "  Duration: $duration"
    fi
    echo -e "\e[90m$footer\e[0m"
  fi
}

# Component result logging function
log_component_result() {
  local component="$1"
  local status="${2:-COMPLETED}"
  local details="${3:-}"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  local status_color="\e[0;32m" # green for success
  local status_icon="✓"

  case "$status" in
  "SUCCESS")
    status_color="\e[0;32m"
    status_icon="✓"
    ;;
  "FAILED")
    status_color="\e[0;31m"
    status_icon="✗"
    ;;
  "WARNING")
    status_color="\e[0;33m"
    status_icon="⚠️"
    ;;
  *)
    status_color="\e[0;36m"
    status_icon="ℹ"
    ;;
  esac

  echo -e "$status_color$status_icon [$timestamp] $component: $status\e[0m"
  if [[ -n "$details" ]]; then
    echo -e "  $details"
  fi
}

# Validate log path for security
validate_log_path() {
  local path="$1"

  # Check for path traversal attempts
  if [[ "$path" =~ \.\./|/\.\. ]]; then
    return 1
  fi

  # Ensure path is absolute or in safe relative location
  if [[ ! "$path" =~ ^(/|~/|\./\.cache/) && ! "$path" =~ ^[-_./:a-zA-Z0-9]+$ ]]; then
    return 1
  fi

  # Check for suspicious characters using string matching
  case "$path" in
  *";"* | *"&"* | *"|"* | *'`'* | *'$'*) return 1 ;;
  esac

  return 0
}

# Create secure user log
create_user_log_securely() {
  local log_dir
  log_dir="$(dirname -- "$LOG_PATH")"

  # Create directory with restrictive permissions
  if mkdir -p "$log_dir" 2>/dev/null; then
    chmod 750 "$log_dir" 2>/dev/null || true

    # Create log file with secure permissions
    if touch "$LOG_PATH" 2>/dev/null; then
      chmod 640 "$LOG_PATH" 2>/dev/null || true
      echo "=== [$(basename -- "$0")] Started at $(date) ===" >>"${LOG_PATH}"
      return 0
    fi
  fi

  return 1
}

# Fallback to user log if primary log creation fails
fallback_to_user_log() {
  LOG_PATH="${HOME}/.cache/ubuntu-dev-tools.log"
  mkdir -p "$(dirname -- "$LOG_PATH")" 2>/dev/null || true
  chmod 750 "$(dirname -- "$LOG_PATH")" 2>/dev/null || true

  if touch "$LOG_PATH" 2>/dev/null; then
    chmod 640 "$LOG_PATH" 2>/dev/null || true
    echo "=== [$(basename -- "$0")] Started at $(date) ===" >>"${LOG_PATH}" 2>/dev/null
    return 0
  else
    LOG_PATH="/dev/null"
    echo "=== [$(basename -- "$0")] Started at $(date) ==="
    return 1
  fi
}

# Log rotation and size management
readonly MAX_LOG_SIZE_MB=50
readonly MAX_LOG_FILES=5
readonly LOG_ROTATION_CHECK_INTERVAL=3600 # 1 hour
declare LOG_ROTATION_PID=""

check_log_rotation() {
  if [[ ! -f "$LOG_PATH" ]] || [[ "$LOG_PATH" == "/dev/null" ]]; then
    return 0
  fi

  # Check if log rotation is needed
  local log_size_mb
  log_size_mb=$(du -m "$LOG_PATH" 2>/dev/null | cut -f1)

  if [[ ${log_size_mb:-0} -ge $MAX_LOG_SIZE_MB ]]; then
    rotate_log_file
  fi

  # Also check for log files older than 30 days
  # shellcheck disable=SC2317
  local log_dir
  log_dir="$(dirname -- "$LOG_PATH")"
  # shellcheck disable=SC2317
  if [[ -d "$log_dir" ]]; then
    # Find and remove log files older than 30 days
    find "$log_dir" -name "*.log.*" -type f -mtime +30 -exec rm -f {} \; 2>/dev/null || true
    log_debug "Cleaned up old log files"
  fi
}

# Automatic log rotation check in background
setup_log_rotation_check() {
  # Check log size periodically in background
  (
    while true; do
      sleep "$LOG_ROTATION_CHECK_INTERVAL"
      check_log_rotation
    done
  ) &

  LOG_ROTATION_PID=$!
}

cleanup_log_rotation() {
  if [[ -n "${LOG_ROTATION_PID:-}" ]] && kill -0 "$LOG_ROTATION_PID" 2>/dev/null; then
    kill "$LOG_ROTATION_PID" 2>/dev/null || true
  fi
}

rotate_log_file() {
  if [[ ! -f "$LOG_PATH" ]]; then
    return 0
  fi

  log_info "Rotating log file (size: $(du -h "$LOG_PATH" 2>/dev/null | cut -f1))"

  # Rotate existing log files
  local i
  for ((i = MAX_LOG_FILES - 1; i >= 1; i--)); do
    local old_log="${LOG_PATH}.${i}"
    local new_log="${LOG_PATH}.$((i + 1))"

    if [[ -f "$old_log" ]]; then
      if [[ $i -eq $((MAX_LOG_FILES - 1)) ]]; then
        # Remove oldest log
        rm -f "$old_log"
      else
        # Rotate log
        mv "$old_log" "$new_log" 2>/dev/null || true
      fi
    fi
  done

  # Move current log to .1
  mv "$LOG_PATH" "${LOG_PATH}.1" 2>/dev/null || true

  # Create new log file
  touch "$LOG_PATH" 2>/dev/null || true
  chmod 640 "$LOG_PATH" 2>/dev/null || true

  # Log rotation event
  echo "=== Log rotated at $(date) ===" >>"${LOG_PATH}"
  log_info "Log rotation completed"
}

# Enhanced logging initialization with security
init_logging() {
  local requested_path="${1:-$DEFAULT_LOG_PATH}"

  # Validate and sanitize log path
  if ! validate_log_path "$requested_path"; then
    echo "WARNING: Invalid or insecure log path: $requested_path" >&2
    requested_path="$HOME/.cache/ubuntu-dev-tools.log"
  fi

  LOG_PATH="$requested_path"

  # Create log directory with secure permissions
  local log_dir
  log_dir="$(dirname -- "$LOG_PATH")"

  if [[ "$LOG_PATH" =~ ^/var/log/ ]]; then
    # System log directory - try with sudo
    if sudo mkdir -p "$log_dir" 2>/dev/null &&
      sudo touch "$LOG_PATH" 2>/dev/null; then
      # Set secure permissions: owner read/write, group read, no world access
      sudo chmod 640 "$LOG_PATH" 2>/dev/null || true
      sudo chown root:adm "$LOG_PATH" 2>/dev/null || true
      echo "=== [$(basename -- "$0")] Started at $(date) ===" | sudo tee -a "${LOG_PATH}" >/dev/null
    else
      fallback_to_user_log
    fi
  else
    # User log directory
    if ! create_user_log_securely; then
      fallback_to_user_log
    fi
  fi

  # Initialize async logging if enabled
  if [[ "${ASYNC_LOGGING}" == "true" ]]; then
    init_async_logging
  fi

  # Set up log rotation
  setup_log_rotation_check

  # Start health check
  setup_logging_health_check

  # Check if immediate rotation is needed
  check_log_rotation

  # Set up cleanup trap
  trap 'cleanup_all_spinners; cleanup_async_logging; cleanup_log_rotation; cleanup_health_check' EXIT INT TERM
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

# Resilient logging with fallback mechanisms and improved error recovery
safe_log_write() {
  local message="$1"
  local level="${2:-INFO}"
  local max_attempts=3
  local attempt=1

  # Sanitize message for safety
  message=$(sanitize_log_message "$message")

  while [[ $attempt -le $max_attempts ]]; do
    # Try to write to primary log
    if write_to_log "$message" "$LOG_PATH"; then
      # Reset error count on successful write
      LOG_ERROR_COUNT=0
      LOG_FALLBACK_ACTIVE=false
      return 0
    else
      ((LOG_ERROR_COUNT++))

      # If we've exceeded error threshold, activate fallback
      if [[ $LOG_ERROR_COUNT -ge $MAX_LOG_ERRORS ]]; then
        activate_fallback_logging "$message" "$level"
        return $?
      fi

      # Try to diagnose and fix the issue
      if diagnose_log_issue; then
        log_debug "Log issue diagnosed and potentially fixed, retrying..."
      else
        sleep 0.1 # Brief delay before retry
      fi
    fi

    ((attempt++))
  done

  # All attempts failed, activate fallback
  activate_fallback_logging "$message" "$level"
}

# Sanitize log messages to prevent log injection
sanitize_log_message() {
  local input="$1"

  # Replace ANSI escape sequences
  local sanitized
  # shellcheck disable=SC2001  # Complex regex requires sed
  sanitized=$(echo "$input" | sed 's/\x1b\[[0-9;]*[mGKHF]//g')

  # Filter potentially dangerous characters
  sanitized=$(echo "$sanitized" | tr -d '\000-\011\013\014\016-\037\177')

  # Limit length to prevent buffer overflows
  if [[ ${#sanitized} -gt 8192 ]]; then
    sanitized="${sanitized:0:8192}... [truncated]"
  fi

  echo "$sanitized"
}

write_to_log() {
  local message="$1"
  local log_file="$2"

  # Check if log file is writable
  if [[ ! -w "$log_file" ]] && [[ ! -w "$(dirname "$log_file")" ]]; then
    return 1
  fi

  # Attempt to write with error checking
  if echo "$message" >>"$log_file" 2>/dev/null; then
    return 0
  else
    return 1
  fi
}

diagnose_log_issue() {
  local log_dir
  log_dir="$(dirname "$LOG_PATH")"

  # Check disk space
  local available_space
  available_space=$(df "$log_dir" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")

  if [[ ${available_space:-0} -lt 1024 ]]; then # Less than 1MB
    echo "WARNING: Low disk space detected, attempting cleanup..." >&2

    # Try to free space by cleaning old logs
    find "$log_dir" -name "*.log.*" -mtime +7 -delete 2>/dev/null || true

    # Try log rotation if current log is large
    if [[ -f "$LOG_PATH" ]]; then
      local log_size
      log_size=$(stat -c%s "$LOG_PATH" 2>/dev/null || echo "0")
      if [[ ${log_size:-0} -gt 10485760 ]]; then # > 10MB
        rotate_log_file
        return 0
      fi
    fi

    return 1
  fi

  # Check permissions
  if [[ ! -w "$LOG_PATH" ]]; then
    echo "WARNING: Log file not writable, attempting permission fix..." >&2

    # Try to fix permissions
    if chmod 640 "$LOG_PATH" 2>/dev/null; then
      return 0
    fi

    # Try to recreate log file
    if rm -f "$LOG_PATH" 2>/dev/null && touch "$LOG_PATH" 2>/dev/null; then
      chmod 640 "$LOG_PATH" 2>/dev/null || true
      return 0
    fi

    return 1
  fi

  # Check if directory exists
  if [[ ! -d "$log_dir" ]]; then
    echo "WARNING: Log directory missing, attempting recreation..." >&2
    if mkdir -p "$log_dir" 2>/dev/null; then
      chmod 750 "$log_dir" 2>/dev/null || true
      return 0
    fi
    return 1
  fi

  return 1
}

activate_fallback_logging() {
  local message="$1"
  local level="$2"

  if [[ "$LOG_FALLBACK_ACTIVE" != "true" ]]; then
    LOG_FALLBACK_ACTIVE=true
    echo "WARNING: Primary logging failed, switching to fallback mode" >&2
  fi

  # Try multiple fallback options in order of preference
  local fallback_paths=(
    "${HOME}/.cache/ubuntu-dev-tools-fallback.log"
    "/tmp/ubuntu-dev-tools-fallback-${USER}.log"
    "/dev/stderr"
  )

  for fallback_path in "${fallback_paths[@]}"; do
    if [[ "$fallback_path" == "/dev/stderr" ]]; then
      # Last resort - just output to stderr
      echo "$message" >&2
      return 0
    else
      # Try to write to fallback file
      if write_to_log "$message" "$fallback_path"; then
        # Update log path to fallback
        LOG_PATH="$fallback_path"
        return 0
      fi
    fi
  done

  # Complete failure - at least try to output to console
  echo "LOGGING FAILURE: $message" >&2
  return 1
}

# Health check function for logging system
check_logging_health() {
  local health_status="healthy"
  local issues=()

  # Check primary log accessibility
  if [[ ! -w "$LOG_PATH" ]] && [[ "$LOG_PATH" != "/dev/null" ]]; then
    health_status="degraded"
    issues+=("Primary log not writable")
  fi

  # Check disk space
  local log_dir
  log_dir="$(dirname "$LOG_PATH")"
  local available_space
  available_space=$(df "$log_dir" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")

  if [[ ${available_space:-0} -lt 10240 ]]; then # Less than 10MB
    health_status="critical"
    issues+=("Low disk space: $((available_space / 1024))MB available")
  fi

  # Check error count
  if [[ $LOG_ERROR_COUNT -gt 0 ]]; then
    health_status="degraded"
    issues+=("Recent logging errors: $LOG_ERROR_COUNT")
  fi

  # Check fallback status
  if [[ "$LOG_FALLBACK_ACTIVE" == "true" ]]; then
    health_status="degraded"
    issues+=("Fallback logging active")
  fi

  # Report health status
  case "$health_status" in
  "healthy")
    log_debug "Logging system health: OK"
    return 0
    ;;
  "degraded")
    log_warning "Logging system health: DEGRADED - ${issues[*]}"
    return 1
    ;;
  "critical")
    log_error "Logging system health: CRITICAL - ${issues[*]}"
    return 2
    ;;
  esac
}

# Periodic health check
setup_logging_health_check() {
  (
    while true; do
      sleep 300 # Check every 5 minutes
      check_logging_health >/dev/null 2>&1 || true
    done
  ) &

  HEALTH_CHECK_PID=$!
}

cleanup_health_check() {
  if [[ -n "${HEALTH_CHECK_PID:-}" ]] && kill -0 "$HEALTH_CHECK_PID" 2>/dev/null; then
    kill "$HEALTH_CHECK_PID" 2>/dev/null || true
  fi
}

finish_logging() {
  # Flush any pending operations
  if [[ "${ASYNC_LOGGING}" == "true" ]]; then
    flush_log_buffer 2>/dev/null || true
  fi

  # Cleanup any active spinners
  cleanup_all_spinners 2>/dev/null || true

  # Stop background processes
  cleanup_async_logging 2>/dev/null || true
  cleanup_log_rotation 2>/dev/null || true
  cleanup_health_check 2>/dev/null || true

  # Generate logging statistics
  local log_stats=""
  if [[ -f "$LOG_PATH" && "$LOG_PATH" != "/dev/null" ]]; then
    local log_size
    log_size=$(du -h "$LOG_PATH" 2>/dev/null | cut -f1 || echo "unknown")
    local log_entries
    log_entries=$(wc -l <"$LOG_PATH" 2>/dev/null || echo "unknown")
    log_stats="Log size: ${log_size}, entries: ${log_entries}"
  fi

  # Final log entry
  local end_msg
  end_msg="=== [$(basename -- "$0")] Finished at $(date) ==="
  if [[ -n "$log_stats" ]]; then
    end_msg="${end_msg} [$log_stats]"
  fi

  if [[ "${ASYNC_LOGGING}" == "true" ]]; then
    safe_log_write "$end_msg" "INFO"
  else
    echo "$end_msg" | tee -a "${LOG_PATH}" 2>/dev/null ||
      echo "$end_msg" >&2
  fi

  # Report final logging statistics
  if [[ $LOG_ERROR_COUNT -gt 0 ]] || [[ "$LOG_FALLBACK_ACTIVE" == "true" ]]; then
    echo "Logging completed with issues: $LOG_ERROR_COUNT errors, fallback: $LOG_FALLBACK_ACTIVE" >&2
  fi

  # Check if log rotation is needed after completion
  check_log_rotation
}

# Progress summary for completed operations with additional metrics
show_completion_summary() {
  local operation="$1"
  local duration="${2:-}"
  local status="${3:-SUCCESS}"
  local details="${4:-}"

  # Calculate runtime metrics
  local current_date
  current_date=$(date +"%Y-%m-%d %H:%M:%S")
  local metrics=""

  # Get resource usage when available
  if command -v ps >/dev/null 2>&1; then
    local memory_usage
    memory_usage=$(ps -o rss= -p "$$" 2>/dev/null || echo "unknown")
    if [[ "$memory_usage" != "unknown" ]]; then
      memory_usage=$((memory_usage / 1024))
      metrics="Memory: ${memory_usage}MB"
    fi
  fi

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

  if [[ -n "$metrics" ]]; then
    echo "║ 📊 $metrics"
  fi

  if [[ -n "$details" ]]; then
    echo "║ 📋 $details"
  fi

  echo "║ 🕒 Completed at: $current_date"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""

  # Also log to file
  {
    echo "=== COMPLETION SUMMARY ==="
    echo "Operation: $operation"
    echo "Status: $status"
    if [[ -n "$duration" ]]; then
      echo "Duration: $duration"
    fi
    if [[ -n "$metrics" ]]; then
      echo "Metrics: $metrics"
    fi
    if [[ -n "$details" ]]; then
      echo "Details: $details"
    fi
    echo "Completed at: $current_date"
    echo "=== END SUMMARY ==="
  } >>"$LOG_PATH" 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# Enhanced Progress Reporting System (2025-06-13)
# ------------------------------------------------------------------------------
# Robust timestamp-based progress reporting to replace spinners

# Enhanced timestamped progress logging
log_progress_start() {
  local task="$1"
  local current="${2:-}"
  local total="${3:-}"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  if [[ -n "$current" && -n "$total" ]]; then
    local percentage=$((current * 100 / total))
    local header=$(printf '═%.0s' $(seq 1 72))

    echo ""
    echo -e "\e[1;36m$header\e[0m"
    echo -e "\e[1;36m [$timestamp] STARTING STEP [$current/$total] ($percentage%): $task\e[0m"
    echo -e "\e[1;36m$header\e[0m"
  else
    local header=$(printf '═%.0s' $(seq 1 72))

    echo ""
    echo -e "\e[1;36m$header\e[0m"
    echo -e "\e[1;36m [$timestamp] STARTING: $task\e[0m"
    echo -e "\e[1;36m$header\e[0m"
  fi

  # Record start time for duration calculation
  if [[ -n "$current" ]]; then
    eval "export _progress_start_time_$current"
    _progress_start_time=$(date +%s)
  else
    export _progress_start_time
    _progress_start_time=$(date +%s)
  fi
}

log_progress_update() {
  local task="$1"
  local message="$2"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  echo -e "[$timestamp] $task: $message"
}

log_progress_complete() {
  local task="$1"
  local status="${2:-SUCCESS}"
  local current="${3:-}"
  local total="${4:-}"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  local duration=""
  local start_time

  # Get the appropriate start time variable
  if [[ -n "$current" ]]; then
    eval "start_time=\${_progress_start_time_$current:-}"
  else
    start_time="${_progress_start_time:-}"
  fi

  # Calculate duration if we have a start time
  if [[ -n "$start_time" ]]; then
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    # Format duration
    if [[ $elapsed -ge 3600 ]]; then
      duration="$((elapsed / 3600))h $(((elapsed % 3600) / 60))m $((elapsed % 60))s"
    elif [[ $elapsed -ge 60 ]]; then
      duration="$((elapsed / 60))m $((elapsed % 60))s"
    else
      duration="${elapsed}s"
    fi
  fi

  local footer=$(printf '─%.0s' $(seq 1 72))

  if [[ -n "$current" && -n "$total" ]]; then
    local percentage=$((current * 100 / total))

    echo ""
    if [[ "$status" == "SUCCESS" ]]; then
      echo -e "\e[1;32m✓ [$timestamp] COMPLETED STEP [$current/$total] ($percentage%): $task\e[0m"
    else
      echo -e "\e[1;31m✗ [$timestamp] FAILED STEP [$current/$total] ($percentage%): $task\e[0m"
    fi

    if [[ -n "$duration" ]]; then
      echo -e "  Duration: $duration"
    fi
    echo -e "\e[90m$footer\e[0m"
  else
    echo ""
    if [[ "$status" == "SUCCESS" ]]; then
      echo -e "\e[1;32m✓ [$timestamp] COMPLETED: $task\e[0m"
    else
      echo -e "\e[1;31m✗ [$timestamp] FAILED: $task\e[0m"
    fi

    if [[ -n "$duration" ]]; then
      echo -e "  Duration: $duration"
    fi
    echo -e "\e[90m$footer\e[0m"
  fi
}

# Component result logging function
log_component_result() {
  local component="$1"
  local status="${2:-COMPLETED}"
  local details="${3:-}"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  local status_color="\e[0;32m" # green for success
  local status_icon="✓"

  case "$status" in
  "SUCCESS")
    status_color="\e[0;32m"
    status_icon="✓"
    ;;
  "FAILED")
    status_color="\e[0;31m"
    status_icon="✗"
    ;;
  "WARNING")
    status_color="\e[0;33m"
    status_icon="⚠️"
    ;;
  *)
    status_color="\e[0;36m"
    status_icon="ℹ"
    ;;
  esac

  echo -e "$status_color$status_icon [$timestamp] $component: $status\e[0m"
  if [[ -n "$details" ]]; then
    echo -e "  $details"
  fi
}

# Validate log path for security
validate_log_path() {
  local path="$1"

  # Check for path traversal attempts
  if [[ "$path" =~ \.\./|/\.\. ]]; then
    return 1
  fi

  # Ensure path is absolute or in safe relative location
  if [[ ! "$path" =~ ^(/|~/|\./\.cache/) && ! "$path" =~ ^[-_./:a-zA-Z0-9]+$ ]]; then
    return 1
  fi

  # Check for suspicious characters using string matching
  case "$path" in
  *";"* | *"&"* | *"|"* | *'`'* | *'$'*) return 1 ;;
  esac

  return 0
}

# Create secure user log
create_user_log_securely() {
  local log_dir
  log_dir="$(dirname -- "$LOG_PATH")"

  # Create directory with restrictive permissions
  if mkdir -p "$log_dir" 2>/dev/null; then
    chmod 750 "$log_dir" 2>/dev/null || true

    # Create log file with secure permissions
    if touch "$LOG_PATH" 2>/dev/null; then
      chmod 640 "$LOG_PATH" 2>/dev/null || true
      echo "=== [$(basename -- "$0")] Started at $(date) ===" >>"${LOG_PATH}"
      return 0
    fi
  fi

  return 1
}

# Fallback to user log if primary log creation fails
fallback_to_user_log() {
  LOG_PATH="${HOME}/.cache/ubuntu-dev-tools.log"
  mkdir -p "$(dirname -- "$LOG_PATH")" 2>/dev/null || true
  chmod 750 "$(dirname -- "$LOG_PATH")" 2>/dev/null || true

  if touch "$LOG_PATH" 2>/dev/null; then
    chmod 640 "$LOG_PATH" 2>/dev/null || true
    echo "=== [$(basename -- "$0")] Started at $(date) ===" >>"${LOG_PATH}" 2>/dev/null
    return 0
  else
    LOG_PATH="/dev/null"
    echo "=== [$(basename -- "$0")] Started at $(date) ==="
    return 1
  fi
}

# Log rotation and size management
declare LOG_ROTATION_PID=""

check_log_rotation() {
  if [[ ! -f "$LOG_PATH" ]] || [[ "$LOG_PATH" == "/dev/null" ]]; then
    return 0
  fi

  # Check if log rotation is needed
  local log_size_mb
  log_size_mb=$(du -m "$LOG_PATH" 2>/dev/null | cut -f1)

  if [[ ${log_size_mb:-0} -ge $MAX_LOG_SIZE_MB ]]; then
    rotate_log_file
  fi

  # Also check for log files older than 30 days
  # shellcheck disable=SC2317
  local log_dir
  log_dir="$(dirname -- "$LOG_PATH")"
  # shellcheck disable=SC2317
  if [[ -d "$log_dir" ]]; then
    # Find and remove log files older than 30 days
    find "$log_dir" -name "*.log.*" -type f -mtime +30 -exec rm -f {} \; 2>/dev/null || true
    log_debug "Cleaned up old log files"
  fi
}

# Automatic log rotation check in background
setup_log_rotation_check() {
  # Check log size periodically in background
  (
    while true; do
      sleep "$LOG_ROTATION_CHECK_INTERVAL"
      check_log_rotation
    done
  ) &

  LOG_ROTATION_PID=$!
}

cleanup_log_rotation() {
  if [[ -n "${LOG_ROTATION_PID:-}" ]] && kill -0 "$LOG_ROTATION_PID" 2>/dev/null; then
    kill "$LOG_ROTATION_PID" 2>/dev/null || true
  fi
}

rotate_log_file() {
  if [[ ! -f "$LOG_PATH" ]]; then
    return 0
  fi

  log_info "Rotating log file (size: $(du -h "$LOG_PATH" 2>/dev/null | cut -f1))"

  # Rotate existing log files
  local i
  for ((i = MAX_LOG_FILES - 1; i >= 1; i--)); do
    local old_log="${LOG_PATH}.${i}"
    local new_log="${LOG_PATH}.$((i + 1))"

    if [[ -f "$old_log" ]]; then
      if [[ $i -eq $((MAX_LOG_FILES - 1)) ]]; then
        # Remove oldest log
        rm -f "$old_log"
      else
        # Rotate log
        mv "$old_log" "$new_log" 2>/dev/null || true
      fi
    fi
  done

  # Move current log to .1
  mv "$LOG_PATH" "${LOG_PATH}.1" 2>/dev/null || true

  # Create new log file
  touch "$LOG_PATH" 2>/dev/null || true
  chmod 640 "$LOG_PATH" 2>/dev/null || true

  # Log rotation event
  echo "=== Log rotated at $(date) ===" >>"${LOG_PATH}"
  log_info "Log rotation completed"
}

# Enhanced logging initialization with security
init_logging() {
  local requested_path="${1:-$DEFAULT_LOG_PATH}"

  # Validate and sanitize log path
  if ! validate_log_path "$requested_path"; then
    echo "WARNING: Invalid or insecure log path: $requested_path" >&2
    requested_path="$HOME/.cache/ubuntu-dev-tools.log"
  fi

  LOG_PATH="$requested_path"

  # Create log directory with secure permissions
  local log_dir
  log_dir="$(dirname -- "$LOG_PATH")"

  if [[ "$LOG_PATH" =~ ^/var/log/ ]]; then
    # System log directory - try with sudo
    if sudo mkdir -p "$log_dir" 2>/dev/null &&
      sudo touch "$LOG_PATH" 2>/dev/null; then
      # Set secure permissions: owner read/write, group read, no world access
      sudo chmod 640 "$LOG_PATH" 2>/dev/null || true
      sudo chown root:adm "$LOG_PATH" 2>/dev/null || true
      echo "=== [$(basename -- "$0")] Started at $(date) ===" | sudo tee -a "${LOG_PATH}" >/dev/null
    else
      fallback_to_user_log
    fi
  else
    # User log directory
    if ! create_user_log_securely; then
      fallback_to_user_log
    fi
  fi

  # Initialize async logging if enabled
  if [[ "${ASYNC_LOGGING}" == "true" ]]; then
    init_async_logging
  fi

  # Set up log rotation
  setup_log_rotation_check

  # Start health check
  setup_logging_health_check

  # Check if immediate rotation is needed
  check_log_rotation

  # Set up cleanup trap
  trap 'cleanup_all_spinners; cleanup_async_logging; cleanup_log_rotation; cleanup_health_check' EXIT INT TERM
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

# Resilient logging with fallback mechanisms and improved error recovery
safe_log_write() {
  local message="$1"
  local level="${2:-INFO}"
  local max_attempts=3
  local attempt=1

  # Sanitize message for safety
  message=$(sanitize_log_message "$message")

  while [[ $attempt -le $max_attempts ]]; do
    # Try to write to primary log
    if write_to_log "$message" "$LOG_PATH"; then
      # Reset error count on successful write
      LOG_ERROR_COUNT=0
      LOG_FALLBACK_ACTIVE=false
      return 0
    else
      ((LOG_ERROR_COUNT++))

      # If we've exceeded error threshold, activate fallback
      if [[ $LOG_ERROR_COUNT -ge $MAX_LOG_ERRORS ]]; then
        activate_fallback_logging "$message" "$level"
        return $?
      fi

      # Try to diagnose and fix the issue
      if diagnose_log_issue; then
        log_debug "Log issue diagnosed and potentially fixed, retrying..."
      else
        sleep 0.1 # Brief delay before retry
      fi
    fi

    ((attempt++))
  done

  # All attempts failed, activate fallback
  activate_fallback_logging "$message" "$level"
}

# Sanitize log messages to prevent log injection
sanitize_log_message() {
  local input="$1"

  # Replace ANSI escape sequences
  local sanitized
  # shellcheck disable=SC2001  # Complex regex requires sed
  sanitized=$(echo "$input" | sed 's/\x1b\[[0-9;]*[mGKHF]//g')

  # Filter potentially dangerous characters
  sanitized=$(echo "$sanitized" | tr -d '\000-\011\013\014\016-\037\177')

  # Limit length to prevent buffer overflows
  if [[ ${#sanitized} -gt 8192 ]]; then
    sanitized="${sanitized:0:8192}... [truncated]"
  fi

  echo "$sanitized"
}

write_to_log() {
  local message="$1"
  local log_file="$2"

  # Check if log file is writable
  if [[ ! -w "$log_file" ]] && [[ ! -w "$(dirname "$log_file")" ]]; then
    return 1
  fi

  # Attempt to write with error checking
  if echo "$message" >>"$log_file" 2>/dev/null; then
    return 0
  else
    return 1
  fi
}

diagnose_log_issue() {
  local log_dir
  log_dir="$(dirname "$LOG_PATH")"

  # Check disk space
  local available_space
  available_space=$(df "$log_dir" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")

  if [[ ${available_space:-0} -lt 1024 ]]; then # Less than 1MB
    echo "WARNING: Low disk space detected, attempting cleanup..." >&2

    # Try to free space by cleaning old logs
    find "$log_dir" -name "*.log.*" -mtime +7 -delete 2>/dev/null || true

    # Try log rotation if current log is large
    if [[ -f "$LOG_PATH" ]]; then
      local log_size
      log_size=$(stat -c%s "$LOG_PATH" 2>/dev/null || echo "0")
      if [[ ${log_size:-0} -gt 10485760 ]]; then # > 10MB
        rotate_log_file
        return 0
      fi
    fi

    return 1
  fi

  # Check permissions
  if [[ ! -w "$LOG_PATH" ]]; then
    echo "WARNING: Log file not writable, attempting permission fix..." >&2

    # Try to fix permissions
    if chmod 640 "$LOG_PATH" 2>/dev/null; then
      return 0
    fi

    # Try to recreate log file
    if rm -f "$LOG_PATH" 2>/dev/null && touch "$LOG_PATH" 2>/dev/null; then
      chmod 640 "$LOG_PATH" 2>/dev/null || true
      return 0
    fi

    return 1
  fi

  # Check if directory exists
  if [[ ! -d "$log_dir" ]]; then
    echo "WARNING: Log directory missing, attempting recreation..." >&2
    if mkdir -p "$log_dir" 2>/dev/null; then
      chmod 750 "$log_dir" 2>/dev/null || true
      return 0
    fi
    return 1
  fi

  return 1
}

activate_fallback_logging() {
  local message="$1"
  local level="$2"

  if [[ "$LOG_FALLBACK_ACTIVE" != "true" ]]; then
    LOG_FALLBACK_ACTIVE=true
    echo "WARNING: Primary logging failed, switching to fallback mode" >&2
  fi

  # Try multiple fallback options in order of preference
  local fallback_paths=(
    "${HOME}/.cache/ubuntu-dev-tools-fallback.log"
    "/tmp/ubuntu-dev-tools-fallback-${USER}.log"
    "/dev/stderr"
  )

  for fallback_path in "${fallback_paths[@]}"; do
    if [[ "$fallback_path" == "/dev/stderr" ]]; then
      # Last resort - just output to stderr
      echo "$message" >&2
      return 0
    else
      # Try to write to fallback file
      if write_to_log "$message" "$fallback_path"; then
        # Update log path to fallback
        LOG_PATH="$fallback_path"
        return 0
      fi
    fi
  done

  # Complete failure - at least try to output to console
  echo "LOGGING FAILURE: $message" >&2
  return 1
}

# Health check function for logging system
check_logging_health() {
  local health_status="healthy"
  local issues=()

  # Check primary log accessibility
  if [[ ! -w "$LOG_PATH" ]] && [[ "$LOG_PATH" != "/dev/null" ]]; then
    health_status="degraded"
    issues+=("Primary log not writable")
  fi

  # Check disk space
  local log_dir
  log_dir="$(dirname "$LOG_PATH")"
  local available_space
  available_space=$(df "$log_dir" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")

  if [[ ${available_space:-0} -lt 10240 ]]; then # Less than 10MB
    health_status="critical"
    issues+=("Low disk space: $((available_space / 1024))MB available")
  fi

  # Check error count
  if [[ $LOG_ERROR_COUNT -gt 0 ]]; then
    health_status="degraded"
    issues+=("Recent logging errors: $LOG_ERROR_COUNT")
  fi

  # Check fallback status
  if [[ "$LOG_FALLBACK_ACTIVE" == "true" ]]; then
    health_status="degraded"
    issues+=("Fallback logging active")
  fi

  # Report health status
  case "$health_status" in
  "healthy")
    log_debug "Logging system health: OK"
    return 0
    ;;
  "degraded")
    log_warning "Logging system health: DEGRADED - ${issues[*]}"
    return 1
    ;;
  "critical")
    log_error "Logging system health: CRITICAL - ${issues[*]}"
    return 2
    ;;
  esac
}

# Periodic health check
setup_logging_health_check() {
  (
    while true; do
      sleep 300 # Check every 5 minutes
      check_logging_health >/dev/null 2>&1 || true
    done
  ) &

  HEALTH_CHECK_PID=$!
}

cleanup_health_check() {
  if [[ -n "${HEALTH_CHECK_PID:-}" ]] && kill -0 "$HEALTH_CHECK_PID" 2>/dev/null; then
    kill "$HEALTH_CHECK_PID" 2>/dev/null || true
  fi
}

finish_logging() {
  # Flush any pending operations
  if [[ "${ASYNC_LOGGING}" == "true" ]]; then
    flush_log_buffer 2>/dev/null || true
  fi

  # Cleanup any active spinners
  cleanup_all_spinners 2>/dev/null || true

  # Stop background processes
  cleanup_async_logging 2>/dev/null || true
  cleanup_log_rotation 2>/dev/null || true
  cleanup_health_check 2>/dev/null || true

  # Generate logging statistics
  local log_stats=""
  if [[ -f "$LOG_PATH" && "$LOG_PATH" != "/dev/null" ]]; then
    local log_size
    log_size=$(du -h "$LOG_PATH" 2>/dev/null | cut -f1 || echo "unknown")
    local log_entries
    log_entries=$(wc -l <"$LOG_PATH" 2>/dev/null || echo "unknown")
    log_stats="Log size: ${log_size}, entries: ${log_entries}"
  fi

  # Final log entry
  local end_msg
  end_msg="=== [$(basename -- "$0")] Finished at $(date) ==="
  if [[ -n "$log_stats" ]]; then
    end_msg="${end_msg} [$log_stats]"
  fi

  if [[ "${ASYNC_LOGGING}" == "true" ]]; then
    safe_log_write "$end_msg" "INFO"
  else
    echo "$end_msg" | tee -a "${LOG_PATH}" 2>/dev/null ||
      echo "$end_msg" >&2
  fi

  # Report final logging statistics
  if [[ $LOG_ERROR_COUNT -gt 0 ]] || [[ "$LOG_FALLBACK_ACTIVE" == "true" ]]; then
    echo "Logging completed with issues: $LOG_ERROR_COUNT errors, fallback: $LOG_FALLBACK_ACTIVE" >&2
  fi

  # Check if log rotation is needed after completion
  check_log_rotation
}

# Progress summary for completed operations with additional metrics
show_completion_summary() {
  local operation="$1"
  local duration="${2:-}"
  local status="${3:-SUCCESS}"
  local details="${4:-}"

  # Calculate runtime metrics
  local current_date
  current_date=$(date +"%Y-%m-%d %H:%M:%S")
  local metrics=""

  # Get resource usage when available
  if command -v ps >/dev/null 2>&1; then
    local memory_usage
    memory_usage=$(ps -o rss= -p "$$" 2>/dev/null || echo "unknown")
    if [[ "$memory_usage" != "unknown" ]]; then
      memory_usage=$((memory_usage / 1024))
      metrics="Memory: ${memory_usage}MB"
    fi
  fi

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

  if [[ -n "$metrics" ]]; then
    echo "║ 📊 $metrics"
  fi

  if [[ -n "$details" ]]; then
    echo "║ 📋 $details"
  fi

  echo "║ 🕒 Completed at: $current_date"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""

  # Also log to file
  {
    echo "=== COMPLETION SUMMARY ==="
    echo "Operation: $operation"
    echo "Status: $status"
    if [[ -n "$duration" ]]; then
      echo "Duration: $duration"
    fi
    if [[ -n "$metrics" ]]; then
      echo "Metrics: $metrics"
    fi
    if [[ -n "$details" ]]; then
      echo "Details: $details"
    fi
    echo "Completed at: $current_date"
    echo "=== END SUMMARY ==="
  } >>"$LOG_PATH" 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# Spinner Functions (Simple Implementation)
# ------------------------------------------------------------------------------

# Simple spinner implementation that just logs progress
start_spinner() {
  local message="${1:-Working...}"
  log_info "$message"
}

# Stop spinner - just log completion if message provided
stop_spinner() {
  local spinner_id="${1:-default}"
  local completion_message="${2:-}"

  if [[ -n "$completion_message" ]]; then
    log_success "$completion_message"
  fi
}

# Cleanup function - no-op for simple implementation
cleanup_spinners() {
  :
}
