#!/usr/bin/env bash
# env-detect.sh - Detect and report the current environment
set -euo pipefail

# Script version and last updated timestamp
readonly VERSION="1.0.0"
readonly LAST_UPDATED="2025-06-13"

# Cross-platform support
OS_TYPE="$(uname -s)"
readonly OS_TYPE

# Function to display usage information
show_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Description:
    Detects and reports the current environment type (WSL2, Desktop, or Headless).
    This script is a wrapper for the detect_environment function in util-env.sh.

Options:
    -h, --help          Show this help message and exit
    -v, --verbose       Enable verbose output with additional details
    -q, --quiet         Suppress all output except the environment type
    --json              Output result in JSON format
    --version           Show script version information

Environment Variables:
    DRY_RUN             Set to "true" to enable dry-run mode (no changes made)

Output:
    Prints one of the following environment types:
    - WSL2      : Windows Subsystem for Linux 2
    - DESKTOP   : Ubuntu Desktop environment
    - HEADLESS  : Ubuntu Server/headless environment

Examples:
    $(basename "$0")                    # Detect and display environment
    $(basename "$0") --json             # Output in JSON format
    $(basename "$0") --quiet            # Output only environment type

Exit Codes:
    0   Success - environment detected
    1   General error
    127 Required utility file not found
    126 Permission denied

Author: Ubuntu Development Environment Setup
Version: $VERSION
Last Updated: $LAST_UPDATED
EOF
}

# Parse command line arguments
VERBOSE=false
QUIET=false
JSON_OUTPUT=false
readonly DRY_RUN="${DRY_RUN:-false}"

while [[ $# -gt 0 ]]; do
    case $1 in
    -h | --help)
        show_usage
        exit 0
        ;;
    -v | --verbose)
        VERBOSE=true
        shift
        ;;
    -q | --quiet)
        QUIET=true
        shift
        ;;
    --json)
        JSON_OUTPUT=true
        shift
        ;;
    --version)
        echo "env-detect.sh version $VERSION (Last updated: $LAST_UPDATED)"
        exit 0
        ;;
    *)
        echo "Error: Unknown option '$1'" >&2
        echo "Use --help for usage information" >&2
        exit 1
        ;;
    esac
done

# Source the environment utility with error handling
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
UTIL_ENV_PATH="$SCRIPT_DIR/util-env.sh"

# Validate utility file exists and is readable
if [[ ! -f "$UTIL_ENV_PATH" ]]; then
    echo "Error: Required utility file not found: $UTIL_ENV_PATH" >&2
    echo "Please ensure util-env.sh is in the same directory as this script" >&2
    exit 127
fi

if [[ ! -r "$UTIL_ENV_PATH" ]]; then
    echo "Error: Cannot read utility file: $UTIL_ENV_PATH" >&2
    echo "Please check file permissions" >&2
    exit 126
fi

# Optional logging integration (if util-log.sh is available)
UTIL_LOG_PATH="$SCRIPT_DIR/util-log.sh"
LOGGING_AVAILABLE=false

if [[ -f "$UTIL_LOG_PATH" ]] && [[ -r "$UTIL_LOG_PATH" ]]; then
    # shellcheck disable=SC1090  # Dynamic utility sourcing
    if source "$UTIL_LOG_PATH" 2>/dev/null; then
        LOGGING_AVAILABLE=true
        # Initialize logging if available
        if declare -f init_logging >/dev/null 2>&1; then
            init_logging 2>/dev/null || true
        fi
    fi
fi

# Enhanced logging functions with fallback
log_debug() {
    if [[ "$LOGGING_AVAILABLE" == "true" ]] && declare -f log_debug >/dev/null 2>&1; then
        log_debug "$@"
    elif [[ "$VERBOSE" == "true" ]]; then
        echo "DEBUG: $*" >&2
    fi
}

log_info() {
    if [[ "$LOGGING_AVAILABLE" == "true" ]] && declare -f log_info >/dev/null 2>&1; then
        log_info "$@"
    elif [[ "$QUIET" != "true" ]]; then
        echo "INFO: $*"
    fi
}

log_error() {
    if [[ "$LOGGING_AVAILABLE" == "true" ]] && declare -f log_error >/dev/null 2>&1; then
        log_error "$@"
    else
        echo "ERROR: $*" >&2
    fi
}

# Source utility with logging
log_debug "Starting environment detection"
log_debug "Script directory: $SCRIPT_DIR"
log_debug "Utility path: $UTIL_ENV_PATH"

log_debug "Loading environment utilities"
# shellcheck disable=SC1090  # Dynamic utility sourcing
if ! source "$UTIL_ENV_PATH"; then
    log_error "Failed to load utility functions from $UTIL_ENV_PATH"
    echo "Error: Failed to load utility functions from $UTIL_ENV_PATH" >&2
    echo "The utility file may be corrupted or contain syntax errors" >&2
    exit 1
fi

# Validate required function is available after sourcing
log_debug "Validating detect_environment function availability"
if ! declare -f detect_environment >/dev/null 2>&1; then
    log_error "detect_environment function not found in $UTIL_ENV_PATH"
    echo "Error: detect_environment function not found in $UTIL_ENV_PATH" >&2
    echo "Please ensure you have the correct version of util-env.sh" >&2
    echo "Expected function: detect_environment" >&2
    exit 1
fi

# Verify function is callable (additional safety check)
if ! type -t detect_environment >/dev/null 2>&1; then
    log_error "detect_environment is not a callable function"
    echo "Error: detect_environment is not a callable function" >&2
    exit 1
fi

# Enhanced environment detection with proper error handling
detect_and_report_environment() {
    local env_type
    local exit_code=0

    # Call detect_environment and capture both output and exit code
    if env_type=$(detect_environment 2>/dev/null); then
        # Success case - environment detected
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            # JSON output format
            cat <<EOF
{
    "environment": "$env_type",
    "timestamp": "$(date -Iseconds)",
    "hostname": "$(hostname)",
    "status": "success",
    "os_type": "$OS_TYPE"
}
EOF
        elif [[ "$QUIET" == "true" ]]; then
            # Quiet mode - just the environment type
            echo "$env_type"
        else
            # Standard output with additional information
            echo "Environment Type: $env_type"

            if [[ "$VERBOSE" == "true" ]]; then
                echo "Detection Time: $(date)"
                echo "Hostname: $(hostname)"
                echo "User: $(whoami)"
                echo "Shell: $SHELL"

                # Add environment-specific details
                case "$env_type" in
                "WSL2")
                    echo "WSL Distribution: ${WSL_DISTRO_NAME:-unknown}"
                    echo "Windows Version: $(cmd.exe /c ver 2>/dev/null | tr -d '\r' || echo 'unknown')"
                    ;;
                "DESKTOP")
                    echo "Desktop Environment: ${XDG_CURRENT_DESKTOP:-unknown}"
                    echo "Display Server: ${XDG_SESSION_TYPE:-unknown}"
                    ;;
                "HEADLESS")
                    echo "System Type: Headless/Server"
                    echo "Systemd: $(systemctl is-system-running 2>/dev/null || echo 'not available')"
                    ;;
                esac
            fi
        fi
    else
        # Error case - detection failed
        exit_code=$?

        if [[ "$JSON_OUTPUT" == "true" ]]; then
            cat <<EOF
{
    "environment": null,
    "timestamp": "$(date -Iseconds)",
    "status": "error",
    "error": "Environment detection failed"
}
EOF
        elif [[ "$QUIET" != "true" ]]; then
            echo "Error: Failed to detect environment type" >&2
            echo "Please check that util-env.sh contains a working detect_environment function" >&2
        fi
    fi

    return $exit_code
}

# Check if in DRY_RUN mode
if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Dry-run mode: Would detect environment but making no system changes"
    exit 0
fi

# Execute detection with logging
log_debug "Executing environment detection"
if detect_and_report_environment; then
    log_debug "Environment detection completed successfully"
    exit 0
else
    exit_code=$?
    log_error "Environment detection failed with exit code: $exit_code"
    exit $exit_code
fi
