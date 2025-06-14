#!/usr/bin/env bash
# env-detect.sh - Detect and report the current environment
# Version: 1.0.1
# Last Updated: 2025-06-14

set -euo pipefail

# ------------------------------------------------------------------------------
# Script Metadata
# ------------------------------------------------------------------------------

readonly VERSION="1.0.1"
readonly LAST_UPDATED="2025-06-14"

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_PERMISSION_DENIED=126
readonly EXIT_COMMAND_NOT_FOUND=127

# ------------------------------------------------------------------------------
# Help and Usage Functions
# ------------------------------------------------------------------------------

# Display comprehensive usage information
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
    $EXIT_SUCCESS   Success - environment detected
    $EXIT_GENERAL_ERROR   General error
    $EXIT_COMMAND_NOT_FOUND Required utility file not found
    $EXIT_PERMISSION_DENIED Permission denied

Author: Ubuntu Development Environment Setup
Version: $VERSION
Last Updated: $LAST_UPDATED
EOF
}

# Display version information
show_version() {
    echo "$(basename "$0") version $VERSION (Last updated: $LAST_UPDATED)"
}

# ------------------------------------------------------------------------------
# Argument Parsing and Validation
# ------------------------------------------------------------------------------

# Parse command line arguments with improved error handling
parse_arguments() {
    # Initialize option flags
    VERBOSE=false
    QUIET=false
    JSON_OUTPUT=false

    while [[ $# -gt 0 ]]; do
        case $1 in
        -h | --help)
            show_usage
            exit $EXIT_SUCCESS
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
            show_version
            exit $EXIT_SUCCESS
            ;;
        *)
            echo "Error: Unknown option '$1'" >&2
            echo "Use --help for usage information" >&2
            exit $EXIT_GENERAL_ERROR
            ;;
        esac
    done

    # Validate conflicting options
    if [[ "$VERBOSE" == true && "$QUIET" == true ]]; then
        echo "Error: --verbose and --quiet options are mutually exclusive" >&2
        exit $EXIT_GENERAL_ERROR
    fi
}

# ------------------------------------------------------------------------------
# Dependency Management
# ------------------------------------------------------------------------------

# Source utility dependencies with comprehensive error handling
source_dependencies() {
    local script_dir util_env_path

    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    readonly SCRIPT_DIR="$script_dir"

    util_env_path="$SCRIPT_DIR/util-env.sh"

    # Validate utility file exists and is readable
    if [[ ! -f "$util_env_path" ]]; then
        echo "Error: Required utility file not found: $util_env_path" >&2
        echo "Please ensure util-env.sh is in the same directory as this script" >&2
        exit $EXIT_COMMAND_NOT_FOUND
    fi

    if [[ ! -r "$util_env_path" ]]; then
        echo "Error: Cannot read utility file: $util_env_path" >&2
        echo "Please check file permissions" >&2
        exit $EXIT_PERMISSION_DENIED
    fi

    # Source the utility with error handling
    # shellcheck source=./util-env.sh
    if ! source "$util_env_path"; then
        echo "Error: Failed to source utility file: $util_env_path" >&2
        echo "The utility file may contain syntax errors" >&2
        exit $EXIT_GENERAL_ERROR
    fi

    # Validate required function is available
    if ! declare -f detect_environment >/dev/null 2>&1; then
        echo "Error: detect_environment function not found in $util_env_path" >&2
        echo "Please ensure you have the correct version of util-env.sh" >&2
        exit $EXIT_GENERAL_ERROR
    fi
}

# ------------------------------------------------------------------------------
# Environment Detection and Reporting
# ------------------------------------------------------------------------------

# Enhanced environment detection with proper error handling
detect_and_report_environment() {
    local env_type
    local exit_code=0
    readonly OS_TYPE="$(uname -s)"

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
                    if command -v cmd.exe >/dev/null 2>&1; then
                        echo "Windows Version: $(cmd.exe /c ver 2>/dev/null | tr -d '\r' || echo 'unknown')"
                    fi
                    ;;
                "DESKTOP")
                    echo "Desktop Environment: ${XDG_CURRENT_DESKTOP:-unknown}"
                    echo "Display Server: ${XDG_SESSION_TYPE:-unknown}"
                    ;;
                "HEADLESS")
                    echo "System Type: Headless/Server"
                    if command -v systemctl >/dev/null 2>&1; then
                        echo "Systemd: $(systemctl is-system-running 2>/dev/null || echo 'not available')"
                    fi
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

# ------------------------------------------------------------------------------
# Main Execution
# ------------------------------------------------------------------------------

main() {
    local dry_run="${DRY_RUN:-false}"

    # Parse command line arguments
    parse_arguments "$@"

    # Source dependencies
    source_dependencies

    # Check if in DRY_RUN mode
    if [[ "$dry_run" == "true" ]]; then
        if [[ "$QUIET" != "true" ]]; then
            echo "Dry-run mode: Would detect environment but making no system changes"
        fi
        exit $EXIT_SUCCESS
    fi

    # Execute detection
    if detect_and_report_environment; then
        exit $EXIT_SUCCESS
    else
        exit_code=$?
        exit $exit_code
    fi
}

# Execute main function with all arguments
main "$@"
