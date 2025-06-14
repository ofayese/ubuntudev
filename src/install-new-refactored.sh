#!/usr/bin/env bash
# install-new.sh - Main installer with dependency resolution and recovery
# Version: 1.0.1
# Last Updated: 2025-06-14

set -euo pipefail

# ------------------------------------------------------------------------------
# Script Metadata and Constants
# ------------------------------------------------------------------------------

readonly VERSION="1.0.1"
readonly LAST_UPDATED="2025-06-14"

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_DEPENDENCY_ERROR=2
readonly EXIT_PERMISSION_DENIED=126
readonly EXIT_COMMAND_NOT_FOUND=127

# File paths
readonly DEFAULT_LOG_DIR="$HOME/.local/share/ubuntu-dev-tools/logs"
readonly LOGFILE="$DEFAULT_LOG_DIR/ubuntu-dev-tools.log"
readonly STATE_FILE="$HOME/.ubuntu-devtools.state"

# ------------------------------------------------------------------------------
# Global Variable Initialization
# ------------------------------------------------------------------------------

# Initialize script directory and environment
_init_script_environment() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    readonly SCRIPT_DIR="$script_dir"

    # Cross-platform OS detection
    local os_type
    os_type="$(uname -s)"
    readonly OS_TYPE="$os_type"

    # Configuration variables
    readonly DRY_RUN="${DRY_RUN:-false}"
    readonly DEBUG_MODE="${DEBUG_MODE:-false}"

    # Create necessary directories
    mkdir -p "$(dirname "$LOGFILE")"
}

# Initialize the script environment
_init_script_environment

# ------------------------------------------------------------------------------
# Utility Module Loading
# ------------------------------------------------------------------------------

# Source utility module with comprehensive error handling
_source_utility_module() {
    local module_name="$1"
    local module_path="$SCRIPT_DIR/$module_name"

    if [[ ! -f "$module_path" ]]; then
        echo "FATAL: Required utility module not found: $module_path" >&2
        exit $EXIT_DEPENDENCY_ERROR
    fi

    # shellcheck source=./util-log.sh
    if ! source "$module_path"; then
        echo "FATAL: Failed to source utility module: $module_name" >&2
        exit $EXIT_DEPENDENCY_ERROR
    fi
}

# Load all required utility modules
_load_utility_modules() {
    local modules=(
        "util-log.sh"
        "util-env.sh"
        "util-install.sh"
        "util-deps.sh"
    )

    local module
    for module in "${modules[@]}"; do
        if [[ "$DEBUG_MODE" == "true" ]]; then
            echo "DEBUG: Loading utility module: $module" >&2
        fi
        _source_utility_module "$module"
    done
}

# Load all utilities
_load_utility_modules

# ------------------------------------------------------------------------------
# Help and Usage Functions
# ------------------------------------------------------------------------------

# Display comprehensive help information
show_help() {
    cat <<'EOF'
🚀 Ubuntu Development Environment Installer
==========================================

USAGE:
  ./install-new.sh [OPTIONS] [COMPONENTS]

OPTIONS:
  --all                Install all available components
  --resume             Resume from previous failed installation
  --graph              Generate dependency graph and exit
  --validate           Run validation checks and exit
  --debug              Enable debug mode (set -x)
  --skip-prereqs       Skip prerequisite checks
  --dry-run            Show what would be done without making changes
  --help, -h           Show this help message

COMPONENTS:
  --devtools           Essential development tools (git, vim, curl, etc.)
  --terminal           Modern CLI tools (bat, ripgrep, fzf, etc.)
  --desktop            Desktop environment enhancements
  --devcontainers      Development containers setup
  --dotnet-ai          .NET and AI development tools
  --lang-sdks          Language SDKs (Node.js, Python, Java, etc.)
  --vscommunity        Visual Studio Code and extensions
  --update-env         Environment updates and optimizations

EXAMPLES:
  ./install-new.sh --all                    # Install everything
  ./install-new.sh --devtools --terminal    # Install dev tools and modern CLI
  ./install-new.sh --validate               # Just run validation
  ./install-new.sh --graph                  # Show dependency graph
  ./install-new.sh --dry-run --all          # Preview what would be installed

FILES:
  dependencies.yaml                         # Component dependencies
  ~/.ubuntu-devtools.state                  # Installation state
  ~/.local/share/ubuntu-dev-tools/logs/     # Log files

ENVIRONMENT VARIABLES:
  DRY_RUN=true                             # Enable dry-run mode
  DEBUG_MODE=true                          # Enable debug output
  SKIP_PREREQS=true                        # Skip prerequisite checks

For more information, see: README.md
EOF
}

# ------------------------------------------------------------------------------
# Argument Parsing
# ------------------------------------------------------------------------------

# Parse command line arguments with validation
parse_arguments() {
    # Initialize flags
    local resume=false
    local show_graph=false
    local validate_only=false
    local install_all=false
    local skip_prereqs=false
    local component_flags=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
        --help | -h)
            show_help
            exit $EXIT_SUCCESS
            ;;
        --skip-prereqs)
            skip_prereqs=true
            ;;
        --resume)
            resume=true
            ;;
        --graph)
            show_graph=true
            ;;
        --validate)
            validate_only=true
            ;;
        --all)
            install_all=true
            ;;
        --debug)
            set -x
            ;;
        --dry-run)
            # Override DRY_RUN setting
            DRY_RUN=true
            ;;
        --*)
            component_flags+=("$1")
            ;;
        *)
            echo "Error: Unknown option '$1'" >&2
            echo "Use --help for usage information" >&2
            exit $EXIT_GENERAL_ERROR
            ;;
        esac
        shift
    done

    # Export parsed flags for use by other functions
    readonly RESUME="$resume"
    readonly SHOW_GRAPH="$show_graph"
    readonly VALIDATE_ONLY="$validate_only"
    readonly INSTALL_ALL="$install_all"
    readonly SKIP_PREREQS="$skip_prereqs"
    readonly COMPONENT_FLAGS=("${component_flags[@]}")
}

# ------------------------------------------------------------------------------
# Dependency Management
# ------------------------------------------------------------------------------

# Load and validate dependencies
load_and_validate_dependencies() {
    local dependencies_file="$SCRIPT_DIR/dependencies.yaml"

    if [[ ! -f "$dependencies_file" ]]; then
        log_error "Dependencies file not found: $dependencies_file"
        exit $EXIT_DEPENDENCY_ERROR
    fi

    log_info "Loading dependency configuration from $dependencies_file"

    if ! load_dependencies "$dependencies_file"; then
        log_error "Failed to load dependencies from $dependencies_file"
        exit $EXIT_DEPENDENCY_ERROR
    fi

    log_success "Dependencies loaded successfully"
}

# Generate dependency graph if requested
handle_graph_generation() {
    if [[ "$SHOW_GRAPH" == "true" ]]; then
        log_info "Generating dependency graph"

        if command -v print_dependency_graph >/dev/null 2>&1; then
            print_dependency_graph | tee "$SCRIPT_DIR/dependency-graph.dot"
            log_success "Dependency graph saved to: $SCRIPT_DIR/dependency-graph.dot"
        else
            log_error "print_dependency_graph function not available"
            exit $EXIT_DEPENDENCY_ERROR
        fi

        exit $EXIT_SUCCESS
    fi
}

# Run validation if requested
handle_validation() {
    if [[ "$VALIDATE_ONLY" == "true" ]]; then
        log_info "Running installation validation"

        local validation_script="$SCRIPT_DIR/validate-installation.sh"
        if [[ -f "$validation_script" ]]; then
            bash "$validation_script"
        else
            log_error "Validation script not found: $validation_script"
            exit $EXIT_DEPENDENCY_ERROR
        fi

        exit $EXIT_SUCCESS
    fi
}

# ------------------------------------------------------------------------------
# Installation State Management
# ------------------------------------------------------------------------------

# Initialize installation state
initialize_installation_state() {
    # Handle resume logic
    if [[ "$RESUME" != "true" ]]; then
        log_info "Starting fresh installation (removing previous state)"
        rm -f "$STATE_FILE"
    else
        log_info "Resuming installation from previous state"
    fi

    # Ensure state file exists
    touch "$STATE_FILE"

    log_info "Installation state file: $STATE_FILE"
}

# ------------------------------------------------------------------------------
# Component Selection
# ------------------------------------------------------------------------------

# Determine which components to install
determine_components_to_install() {
    local components_to_install=()

    if [[ "$INSTALL_ALL" == "true" ]]; then
        log_info "Installing all available components"
        # Get all components from loaded dependencies
        if [[ ${#COMPONENTS[@]} -gt 0 ]]; then
            components_to_install=("${COMPONENTS[@]}")
        else
            log_error "No components found in dependencies"
            exit $EXIT_DEPENDENCY_ERROR
        fi
    elif [[ ${#COMPONENT_FLAGS[@]} -gt 0 ]]; then
        log_info "Installing selected components: ${COMPONENT_FLAGS[*]}"

        # Convert component flags to component names
        local flag
        for flag in "${COMPONENT_FLAGS[@]}"; do
            local component_name="${flag#--}" # Remove leading --
            components_to_install+=("$component_name")
        done
    else
        log_error "No components specified for installation"
        echo "Use --help to see available options" >&2
        exit $EXIT_GENERAL_ERROR
    fi

    # Export components for use by installation functions
    readonly COMPONENTS_TO_INSTALL=("${components_to_install[@]}")
    log_info "Components selected for installation: ${COMPONENTS_TO_INSTALL[*]}"
}

# ------------------------------------------------------------------------------
# Main Installation Logic
# ------------------------------------------------------------------------------

# Execute the main installation process
execute_installation() {
    log_info "Starting Ubuntu development environment installation"
    log_info "Version: $VERSION"
    log_info "Dry run mode: $DRY_RUN"

    # Check prerequisites unless skipped
    if [[ "$SKIP_PREREQS" != "true" ]]; then
        log_info "Running prerequisite checks"

        local prereq_script="$SCRIPT_DIR/check-prerequisites.sh"
        if [[ -f "$prereq_script" ]]; then
            if ! bash "$prereq_script"; then
                log_error "Prerequisite checks failed"
                exit $EXIT_DEPENDENCY_ERROR
            fi
        else
            log_warning "Prerequisite script not found: $prereq_script"
        fi
    else
        log_info "Skipping prerequisite checks (--skip-prereqs specified)"
    fi

    # Install selected components
    local component
    local component_count=0
    local total_components=${#COMPONENTS_TO_INSTALL[@]}

    for component in "${COMPONENTS_TO_INSTALL[@]}"; do
        ((component_count++))

        log_step_start "Installing $component" "$component_count" "$total_components"

        # Check if component was already installed (for resume functionality)
        if grep -q "^$component:SUCCESS$" "$STATE_FILE" 2>/dev/null; then
            log_info "Component $component already installed (skipping)"
            log_step_complete "Installing $component" "$component_count" "$total_components" "SKIPPED"
            continue
        fi

        # Install the component
        if install_component "$component"; then
            echo "$component:SUCCESS" >>"$STATE_FILE"
            log_step_complete "Installing $component" "$component_count" "$total_components" "SUCCESS"
        else
            echo "$component:FAILED" >>"$STATE_FILE"
            log_step_complete "Installing $component" "$component_count" "$total_components" "FAILED"
            log_error "Installation failed for component: $component"
            exit $EXIT_GENERAL_ERROR
        fi
    done

    log_success "Installation completed successfully"
}

# Install a single component
install_component() {
    local component="$1"

    # Check if component script exists
    local script_name="${SCRIPTS[$component]:-setup-$component.sh}"
    local script_path="$SCRIPT_DIR/$script_name"

    if [[ ! -f "$script_path" ]]; then
        log_error "Installation script not found for component $component: $script_path"
        return 1
    fi

    log_info "Executing installation script: $script_name"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would execute: bash $script_path"
        return 0
    fi

    # Execute the component installation script
    if bash "$script_path"; then
        log_success "Component $component installed successfully"
        return 0
    else
        log_error "Component $component installation failed"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Main Execution Function
# ------------------------------------------------------------------------------

main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Load and validate dependencies
    load_and_validate_dependencies

    # Handle special operations (graph, validation)
    handle_graph_generation
    handle_validation

    # Initialize installation state
    initialize_installation_state

    # Determine components to install
    determine_components_to_install

    # Execute installation
    execute_installation
}

# Execute main function with all arguments
main "$@"
