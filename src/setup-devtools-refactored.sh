#!/usr/bin/env bash
# setup-devtools.sh - Development tools setup with enhanced error handling
# Version: 1.0.1
# Last Updated: 2025-06-14

set -euo pipefail

# ------------------------------------------------------------------------------
# Script Metadata and Configuration
# ------------------------------------------------------------------------------

readonly VERSION="1.0.1"
readonly LAST_UPDATED="2025-06-14"
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# Installation configuration
readonly PACKAGE_TIMEOUT=120
readonly MAX_RETRY_ATTEMPTS=2

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_DEPENDENCY_ERROR=2

# ------------------------------------------------------------------------------
# Environment Initialization
# ------------------------------------------------------------------------------

# Initialize script environment and dependencies
_init_script_environment() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    readonly SCRIPT_DIR="$script_dir"

    # Load required utility modules
    _load_utility_modules
}

# Load utility modules with comprehensive error handling
_load_utility_modules() {
    local required_modules=(
        "util-log.sh"
        "util-install.sh"
    )

    local module
    for module in "${required_modules[@]}"; do
        local module_path="$SCRIPT_DIR/$module"

        if [[ ! -f "$module_path" ]]; then
            echo "FATAL: Required utility module not found: $module_path" >&2
            exit $EXIT_DEPENDENCY_ERROR
        fi

        # shellcheck source=./util-log.sh
        if ! source "$module_path"; then
            echo "FATAL: Failed to source utility module: $module" >&2
            exit $EXIT_DEPENDENCY_ERROR
        fi
    done
}

# Initialize environment
_init_script_environment

# ------------------------------------------------------------------------------
# Package Installation Functions
# ------------------------------------------------------------------------------

# Install a single package with retry logic and progress reporting
install_package_with_retry() {
    local package_name="$1"
    local description="${2:-$package_name}"
    local attempt=1

    log_substep "Installing $description" "IN PROGRESS"

    while [[ $attempt -le $MAX_RETRY_ATTEMPTS ]]; do
        if [[ $attempt -gt 1 ]]; then
            log_substep "Retrying $description (attempt $attempt/$MAX_RETRY_ATTEMPTS)" "IN PROGRESS"
        fi

        if run_with_timeout \
            "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $package_name" \
            "Installing $package_name" \
            "$PACKAGE_TIMEOUT"; then

            log_substep "Installing $description" "SUCCESS"
            return 0
        fi

        ((attempt++))
    done

    log_substep "Installing $description" "FAILED" "Failed after $MAX_RETRY_ATTEMPTS attempts"
    return 1
}

# Install a group of packages with progress tracking
install_package_group() {
    local group_name="$1"
    shift
    local packages=("$@")

    local total_packages=${#packages[@]}
    local installed_count=0
    local failed_packages=()

    log_info "Installing $group_name ($total_packages packages)"

    local package
    for package in "${packages[@]}"; do
        ((installed_count++))
        show_progress "$installed_count" "$total_packages" "Installing $group_name"

        if install_package_with_retry "$package"; then
            log_debug "Successfully installed: $package"
        else
            failed_packages+=("$package")
            log_warning "Failed to install: $package"
        fi
    done

    # Report results
    local success_count=$((total_packages - ${#failed_packages[@]}))

    if [[ ${#failed_packages[@]} -eq 0 ]]; then
        log_success "$group_name installation completed ($success_count/$total_packages packages)"
        return 0
    elif [[ $success_count -gt 0 ]]; then
        log_warning "$group_name installation partially completed ($success_count/$total_packages packages)"
        log_warning "Failed packages: ${failed_packages[*]}"
        return 1
    else
        log_error "$group_name installation failed completely"
        return 1
    fi
}

# Handle alternative package installations
install_package_alternatives() {
    local primary_command="$1"
    local primary_package="$2"
    shift 2
    local alternative_packages=("$@")

    # Check if primary command is already available
    if command -v "$primary_command" >/dev/null 2>&1; then
        log_info "$primary_command is already available"
        return 0
    fi

    # Try primary package first
    if install_package_with_retry "$primary_package"; then
        return 0
    fi

    # Try alternatives
    local alt_package
    for alt_package in "${alternative_packages[@]}"; do
        log_info "Trying alternative package: $alt_package"

        if install_package_with_retry "$alt_package"; then
            # Handle special post-installation setup
            _handle_alternative_setup "$primary_command" "$alt_package"
            return 0
        fi
    done

    log_error "Failed to install $primary_command using any available package"
    return 1
}

# Handle post-installation setup for alternative packages
_handle_alternative_setup() {
    local command_name="$1"
    local installed_package="$2"

    case "$command_name" in
    "bat")
        if [[ "$installed_package" == "batcat" ]]; then
            log_info "Setting up bat alias for batcat"
            echo 'alias bat=batcat' >>"$HOME/.bashrc"
            log_success "Added bat=batcat alias to ~/.bashrc"
        fi
        ;;
    esac
}

# ------------------------------------------------------------------------------
# System Update Functions
# ------------------------------------------------------------------------------

# Update package index with comprehensive error handling
update_package_index() {
    log_substep "Updating package index" "IN PROGRESS"

    if run_with_timeout \
        "sudo apt-get update -y" \
        "Package index update" \
        "$PACKAGE_TIMEOUT"; then

        log_substep "Package index update" "SUCCESS"
        return 0
    else
        log_substep "Package index update" "WARNING" "Continuing despite update issues"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Component Installation Functions
# ------------------------------------------------------------------------------

# Install system monitoring tools
install_monitoring_tools() {
    local monitoring_packages=(
        "htop"
        "btop"
        "glances"
        "ncdu"
        "iftop"
        "tree"
    )

    install_package_group "System Monitoring Tools" "${monitoring_packages[@]}"
}

# Install CLI utilities
install_cli_utilities() {
    local cli_packages=(
        "git"
        "wget"
        "curl"
        "fzf"
        "ripgrep"
    )

    # Install basic CLI utilities
    if ! install_package_group "CLI Utilities" "${cli_packages[@]}"; then
        log_warning "Some CLI utilities failed to install"
    fi

    # Handle packages with alternatives
    install_package_alternatives "bat" "bat" "batcat"
}

# Install modern file management tools
install_file_tools() {
    log_info "Installing modern file management tools"

    # Try to install eza (modern ls replacement)
    if ! install_eza_from_github; then
        log_warning "Failed to install eza from GitHub, trying package manager"
        install_package_with_retry "exa" "exa (eza alternative)" || true
    fi

    # Install other file tools
    local file_packages=(
        "fd-find"
        "jq"
        "yq"
    )

    install_package_group "File Management Tools" "${file_packages[@]}"
}

# Install eza from GitHub releases
install_eza_from_github() {
    log_substep "Installing eza from GitHub" "IN PROGRESS"

    local temp_dir
    temp_dir=$(mktemp -d)

    # Cleanup function
    cleanup_temp() {
        rm -rf "$temp_dir"
    }
    trap cleanup_temp EXIT

    # Detect architecture
    local arch
    arch=$(uname -m)
    case "$arch" in
    "x86_64") arch="x86_64" ;;
    "aarch64" | "arm64") arch="aarch64" ;;
    *)
        log_substep "Installing eza" "FAILED" "Unsupported architecture: $arch"
        return 1
        ;;
    esac

    # Download and install eza
    local eza_url="https://github.com/eza-community/eza/releases/latest/download/eza_${arch}-unknown-linux-gnu.tar.gz"

    if run_with_timeout \
        "cd '$temp_dir' && wget -O eza.tar.gz '$eza_url' && tar xzf eza.tar.gz && sudo cp eza /usr/local/bin/" \
        "Downloading and installing eza" \
        "$PACKAGE_TIMEOUT"; then

        log_substep "Installing eza" "SUCCESS"
        return 0
    else
        log_substep "Installing eza" "FAILED" "Download or installation failed"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Main Installation Workflow
# ------------------------------------------------------------------------------

# Execute the complete development tools setup
main() {
    readonly TOTAL_STEPS=4
    local current_step=0

    log_info "Starting development tools setup"
    log_info "Script: $SCRIPT_NAME v$VERSION"

    # Step 1: Update package index
    log_step_start "Update Package Index" $((++current_step)) "$TOTAL_STEPS"
    if update_package_index; then
        log_step_complete "Update Package Index" "$current_step" "$TOTAL_STEPS" "SUCCESS"
    else
        log_step_complete "Update Package Index" "$current_step" "$TOTAL_STEPS" "WARNING"
    fi

    # Step 2: Install monitoring tools
    log_step_start "Install System Monitoring Tools" $((++current_step)) "$TOTAL_STEPS"
    if install_monitoring_tools; then
        log_step_complete "Install System Monitoring Tools" "$current_step" "$TOTAL_STEPS" "SUCCESS"
    else
        log_step_complete "Install System Monitoring Tools" "$current_step" "$TOTAL_STEPS" "PARTIAL"
    fi

    # Step 3: Install CLI utilities
    log_step_start "Install CLI Utilities" $((++current_step)) "$TOTAL_STEPS"
    if install_cli_utilities; then
        log_step_complete "Install CLI Utilities" "$current_step" "$TOTAL_STEPS" "SUCCESS"
    else
        log_step_complete "Install CLI Utilities" "$current_step" "$TOTAL_STEPS" "PARTIAL"
    fi

    # Step 4: Install file management tools
    log_step_start "Install File Management Tools" $((++current_step)) "$TOTAL_STEPS"
    if install_file_tools; then
        log_step_complete "Install File Management Tools" "$current_step" "$TOTAL_STEPS" "SUCCESS"
    else
        log_step_complete "Install File Management Tools" "$current_step" "$TOTAL_STEPS" "PARTIAL"
    fi

    log_success "Development tools setup completed"
    log_info "Please restart your shell or run 'source ~/.bashrc' to use new tools"
}

# Execute main function
main "$@"
