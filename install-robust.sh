#!/usr/bin/env bash
# install-robust.sh - Robust installation with proper error handling
# Version: 2.0.0
# Last updated: 2025-06-13
set -euo pipefail

# Use declare first, then make readonly to avoid redeclaration issues
# when multiple scripts define the same constants
# VERSION is used for logging/reporting and debugging
declare VERSION="2.0.0"
export VERSION
readonly VERSION

# shellcheck disable=SC2034  # SCRIPT_DIR used by sourced utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# Use user-accessible log location instead of system directory
readonly LOGFILE="$HOME/.local/share/ubuntu-dev-tools/logs/ubuntu-dev-tools-robust.log"
readonly STATE_FILE="$HOME/.ubuntu-devtools-robust.state"
readonly TIMEOUT_NETWORK=30
readonly TIMEOUT_PACKAGE=600
readonly MAX_RETRIES=3

# Source utilities with proper error handling
for util in util-log.sh util-env.sh util-install.sh util-deps.sh; do
    if [[ -f "$SCRIPT_DIR/$util" ]]; then
        # shellcheck source=/dev/null
        source "$SCRIPT_DIR/$util" || {
            echo "FATAL: Failed to source $util" >&2
            exit 1
        }
    else
        echo "FATAL: Missing utility file: $util" >&2
        exit 1
    fi
done

# Initialize robust error handling
setup_error_handling() {
    set -euo pipefail

    # Comprehensive error trap
    trap 'handle_error $? $LINENO "$BASH_COMMAND"' ERR
    trap 'cleanup_on_exit' EXIT
    trap 'handle_interrupt' INT TERM
}

handle_error() {
    local exit_code=$1
    local line_number=$2
    local command="$3"

    # Safe error logging - fallback to echo if logging not ready
    if command -v log_error >/dev/null 2>&1; then
        log_error "Error at line $line_number: $command (exit code: $exit_code)"
    else
        echo "[ERROR] Error at line $line_number: $command (exit code: $exit_code)" >&2
    fi

    # Offer recovery options
    if [[ -t 0 ]]; then # Interactive terminal
        echo ""
        echo "Installation error occurred. Options:"
        echo "1. Continue (skip failed component)"
        echo "2. Retry current operation"
        echo "3. Rollback and exit"
        echo "4. Exit without rollback"

        read -p "Choose option [1-4]: " -t 30 choice || choice="1"

        case "$choice" in
        2) return 0 ;; # Continue execution for retry
        3) rollback_installation && exit 1 ;;
        4) exit $exit_code ;;
        *)
            if command -v log_warning >/dev/null 2>&1; then
                log_warning "Continuing with next component..."
            else
                echo "[WARN] Continuing with next component..." >&2
            fi
            ;;
        esac
    else
        if command -v log_warning >/dev/null 2>&1; then
            log_warning "Non-interactive mode: continuing with next component"
        else
            echo "[WARN] Non-interactive mode: continuing with next component" >&2
        fi
    fi
}

handle_interrupt() {
    if command -v log_warning >/dev/null 2>&1; then
        log_warning "Installation interrupted by user"
    else
        echo "[WARN] Installation interrupted by user" >&2
    fi
    save_installation_state
    cleanup_on_exit
    exit 130
}

cleanup_on_exit() {
    # Clean up temporary files and processes
    local temp_files=(/tmp/ubuntu-devtools-* /tmp/install-*)
    for file in "${temp_files[@]}"; do
        [[ -f "$file" ]] && rm -f "$file" 2>/dev/null || true
    done

    # Kill any background processes we started
    jobs -p | xargs -r kill 2>/dev/null || true
}

# Minimal system validation (instead of heavy prerequisites)
validate_system() {
    log_info "Performing minimal system validation..."

    local validation_errors=()

    # Check if we're root (not recommended)
    if [[ $EUID -eq 0 ]]; then
        log_warning "Running as root is not recommended"
    fi

    # Test sudo access
    if ! sudo -n true 2>/dev/null && ! timeout 30 sudo -v 2>/dev/null; then
        validation_errors+=("Sudo access required")
    fi

    # Basic connectivity test (quick)
    if ! timeout 5 ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_warning "No internet connectivity detected - some installations may fail"
    fi

    # Check available disk space (basic threshold)
    local available_gb
    available_gb=$(df -BG / | awk 'NR==2 {gsub("G","",$4); print $4}')
    if [[ ${available_gb:-0} -lt 2 ]]; then
        validation_errors+=("Insufficient disk space: ${available_gb}GB (2GB+ recommended)")
    fi

    # Report critical issues
    if [[ ${#validation_errors[@]} -gt 0 ]]; then
        log_error "Critical system validation failed:"
        for error in "${validation_errors[@]}"; do
            log_error "  - $error"
        done

        if [[ -t 0 ]]; then
            read -p "Continue anyway? [y/N]: " -n 1 -r
            echo
            [[ $REPLY =~ ^[Yy]$ ]] || exit 1
        else
            log_error "Cannot continue in non-interactive mode"
            exit 1
        fi
    fi

    log_success "Basic system validation passed"
}

# Safe component installation with retry logic
install_component_safe() {
    local component="$1"
    local script="$2"
    local attempt=1

    log_info "Installing component: $component"

    while [[ $attempt -le $MAX_RETRIES ]]; do
        if [[ $attempt -gt 1 ]]; then
            log_info "Retry attempt $attempt for $component"
            sleep $((attempt * 5)) # Exponential backoff
        fi

        # Record attempt in state
        update_component_state "$component" "installing" "Attempt $attempt"

        # Run installation with timeout
        if timeout $TIMEOUT_PACKAGE bash "$SCRIPT_DIR/$script"; then
            log_success "Successfully installed: $component"
            update_component_state "$component" "completed" "Success"
            return 0
        else
            local exit_code=$?
            log_warning "Installation attempt $attempt failed for $component (exit code: $exit_code)"
            update_component_state "$component" "failed" "Exit code: $exit_code"

            # Try to identify and fix common issues
            case $exit_code in
            124) log_warning "Installation timed out" ;;
            1 | 2) log_warning "General installation error" ;;
            126) log_warning "Permission denied" ;;
            127) log_warning "Command not found" ;;
            esac

            ((attempt++))
        fi
    done

    log_error "Failed to install $component after $MAX_RETRIES attempts"
    update_component_state "$component" "failed" "Failed after $MAX_RETRIES attempts"
    return 1
}

# State management functions
update_component_state() {
    local component="$1"
    local status="$2"
    local details="$3"
    local timestamp
    timestamp=$(date -Iseconds)

    # Create state entry
    local state_entry
    state_entry=$(
        cat <<EOF
{
  "component": "$component",
  "status": "$status", 
  "details": "$details",
  "timestamp": "$timestamp",
  "attempt": ${attempt:-1}
}
EOF
    )

    # Append to state file (simple approach)
    echo "$state_entry" >>"$STATE_FILE"
}

save_installation_state() {
    log_info "Saving installation state to $STATE_FILE"
    echo "# Installation interrupted at $(date)" >>"$STATE_FILE"
}

rollback_installation() {
    log_info "Rollback functionality not implemented yet"
    return 0
}

# Network-aware installation wrapper
install_with_network_retry() {
    local operation="$1"
    shift
    local args=("$@")

    local attempt=1
    while [[ $attempt -le $MAX_RETRIES ]]; do
        if [[ $attempt -gt 1 ]]; then
            log_info "Network retry attempt $attempt"

            # Test connectivity before retry
            if ! timeout 10 ping -c 2 8.8.8.8 >/dev/null 2>&1; then
                log_warning "Network connectivity issues detected"
                sleep $((attempt * 10))
            fi
        fi

        if timeout $TIMEOUT_NETWORK "$operation" "${args[@]}"; then
            return 0
        else
            local exit_code=$?
            log_warning "Network operation failed (attempt $attempt): $operation"
            ((attempt++))
        fi
    done

    log_error "Network operation failed after $MAX_RETRIES attempts: $operation"
    return 1
}

# Main installation logic
main() {
    # Ensure log directory exists first
    mkdir -p "$(dirname "$LOGFILE")"

    # Initialize logging before error handling
    init_logging "$LOGFILE"

    # Now set up error handling (which uses logging)
    setup_error_handling

    log_info "Starting robust Ubuntu development environment installation"
    log_info "Version: $VERSION"

    # Minimal validation instead of heavy prerequisites
    validate_system

    # Parse command line arguments
    local components=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
        --all)
            components=("devtools" "terminal-enhancements" "desktop" "devcontainers" "dotnet-ai" "lang-sdks" "node-python" "npm" "vscommunity")
            ;;
        --skip-validation)
            log_info "Validation skip flag noted (minimal validation still performed)"
            ;;
        --devtools) components+=("devtools") ;;
        --terminal) components+=("terminal-enhancements") ;;
        --desktop) components+=("desktop") ;;
        --devcontainers) components+=("devcontainers") ;;
        --dotnet-ai) components+=("dotnet-ai") ;;
        --lang-sdks) components+=("lang-sdks") ;;
        --node-python) components+=("node-python") ;;
        --npm) components+=("npm") ;;
        --vscommunity) components+=("vscommunity") ;;
        --help | -h)
            echo "Usage: $0 [--all] [--component-name] [--skip-validation]"
            echo "Available components: devtools, terminal, desktop, devcontainers, dotnet-ai, lang-sdks, node-python, npm, vscommunity"
            exit 0
            ;;
        *)
            log_warning "Unknown option: $1"
            ;;
        esac
        shift
    done

    # Default to devtools if no components specified
    if [[ ${#components[@]} -eq 0 ]]; then
        components=("devtools")
        log_info "No components specified, defaulting to devtools"
    fi

    # Install components with error tolerance
    local installed=()
    local failed=()

    for component in "${components[@]}"; do
        local script="setup-${component}.sh"

        # Check if script exists
        if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
            log_warning "Script not found: $script (skipping $component)"
            failed+=("$component (script not found)")
            continue
        fi

        # Install with retry logic
        if install_component_safe "$component" "$script"; then
            installed+=("$component")
        else
            failed+=("$component")
        fi
    done

    # Installation summary
    echo ""
    log_info "Installation Summary:"
    log_info "Successfully installed: ${#installed[@]} components"
    for comp in "${installed[@]}"; do
        log_success "  ✓ $comp"
    done

    if [[ ${#failed[@]} -gt 0 ]]; then
        log_warning "Failed installations: ${#failed[@]} components"
        for comp in "${failed[@]}"; do
            log_error "  ✗ $comp"
        done
        log_info "Check logs in $LOGFILE for details"
        log_info "Run './validate-installation.sh' to verify what's working"
    else
        log_success "All components installed successfully!"
    fi

    finish_logging

    # Exit with appropriate code
    [[ ${#failed[@]} -eq 0 ]] && exit 0 || exit 1
}

# Run main function with all arguments
main "$@"
