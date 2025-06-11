#!/usr/bin/env bash
# install.sh - Main installation script for Ubuntu Development Environment
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-log.sh"
source "$SCRIPT_DIR/util-env.sh"

# Initialize logging
LOGFILE="/var/log/ubuntu-dev-tools.log"
init_logging "$LOGFILE"

# Set error trap
set_error_trap

# Run prerequisites check first (unless skipped)
SKIP_PREREQS=false
if [[ "${1:-}" == "--skip-prereqs" ]]; then
    SKIP_PREREQS=true
    shift
fi

if [[ "$SKIP_PREREQS" == "false" ]]; then
    log_info "Running prerequisites check..."
    if ! bash "$SCRIPT_DIR/check-prerequisites.sh"; then
        log_error "Prerequisites check failed. Please address the issues above."
        log_warning "You can skip this check with --skip-prereqs flag (advanced users only)"
        finish_logging
        exit 1
    fi
else
    log_warning "Skipping prerequisites check as requested"
fi

# Detect environment type
ENV_TYPE=$(detect_environment)
log_info "Detected environment: $ENV_TYPE"

# Function to run a script with error handling
run_script() {
    local script="$1"
    local description="$2"
    
    log_info "Running $description..."
    
    if [ -f "$SCRIPT_DIR/$script" ]; then
        if bash "$SCRIPT_DIR/$script"; then
            log_success "$description completed successfully"
            return 0
        else
            log_error "$description failed"
            return 1
        fi
    else
        log_error "Script $script not found"
        return 1
    fi
}

# Display help information
show_help() {
  echo "Usage: $0 [--skip-prereqs] [options]"
  echo ""
  echo "  --skip-prereqs        Skip prerequisites check (advanced users only)"
  echo "  --all                 Install everything"
  echo "  --desktop             Run desktop customizations"
  echo "  --node-python         Setup Node.js and Python with version managers"
  echo "  --devtools            Install CLI dev tools, linters, shells, etc."
  echo "  --devcontainers       Setup Docker Desktop or containerd/devcontainers"
  echo "  --dotnet-ai           Install .NET, PowerShell, AI/ML tools"
  echo "  --lang-sdks           Install Java, Rust, Haskell (via SDKMAN, rustup, ghcup)"
  echo "  --terminal            Finalize terminal: starship, alacritty, zsh plugins"
  echo "  --npm                 Install npm global and local dependencies"
  echo "  --validate            Validate the installation"
  echo "  --help                Show this help message"
}

# Install all components
install_all() {
  local failed_scripts=()
  
  log_info "Installing all components for $ENV_TYPE environment..."
  
  # Desktop-specific components
  if [[ "$ENV_TYPE" == "DESKTOP" ]]; then
    run_script "setup-desktop.sh" "Desktop Environment Setup" || failed_scripts+=("setup-desktop.sh")
  fi
  
  # Core components for all environments
  run_script "setup-node-python.sh" "Node.js and Python Setup" || failed_scripts+=("setup-node-python.sh")
  run_script "setup-devtools.sh" "Development Tools Setup" || failed_scripts+=("setup-devtools.sh")
  # VS Code should be installed on Windows (for WSL2) or locally (for Desktop)
  run_script "setup-devcontainers.sh" "Container Development Setup" || failed_scripts+=("setup-devcontainers.sh")
  run_script "setup-dotnet-ai.sh" ".NET and AI Tools Setup" || failed_scripts+=("setup-dotnet-ai.sh")
  run_script "setup-lang-sdks.sh" "Language SDKs Setup" || failed_scripts+=("setup-lang-sdks.sh")
  run_script "setup-terminal-enhancements.sh" "Terminal Enhancements" || failed_scripts+=("setup-terminal-enhancements.sh")
  run_script "setup-npm.sh" "NPM Packages Setup" || failed_scripts+=("setup-npm.sh")
  
  # WSL-specific components
  if [[ "$ENV_TYPE" == "WSL2" ]]; then
  # WSL optimizations are handled by util-wsl.sh functions
    run_script "setup-vscommunity.sh" "Visual Studio Community Setup" || failed_scripts+=("setup-vscommunity.sh")
    run_script "validate-docker-desktop.sh" "Docker Desktop Validation" || failed_scripts+=("validate-docker-desktop.sh")
  fi
  
  # Final validation
  run_script "validate-installation.sh" "Installation Validation" || failed_scripts+=("validate-installation.sh")
  
  # Report results
  if [ ${#failed_scripts[@]} -eq 0 ]; then
    log_success "All components installed successfully!"
  else
    log_warning "Some components failed to install:"
    for script in "${failed_scripts[@]}"; do
      log_error "  $script"
    done
    log_info "You can retry failed components individually."
  fi
}

# Parse CLI arguments
if [[ $# -eq 0 ]]; then
  show_help
  finish_logging
  exit 1
fi

for arg in "$@"; do
  case "$arg" in
    --all) install_all ;;
    --desktop) "$SCRIPT_DIR/setup-desktop.sh" ;;
    --node-python) "$SCRIPT_DIR/setup-node-python.sh" ;;
    --devtools) "$SCRIPT_DIR/setup-devtools.sh" ;;
    # VS Code should be installed on Windows for WSL2 users
    --devcontainers) "$SCRIPT_DIR/setup-devcontainers.sh" ;;
    --dotnet-ai) "$SCRIPT_DIR/setup-dotnet-ai.sh" ;;
    --lang-sdks) "$SCRIPT_DIR/setup-lang-sdks.sh" ;;
    --terminal) "$SCRIPT_DIR/setup-terminal-enhancements.sh" ;;
    --npm) "$SCRIPT_DIR/setup-npm.sh" ;;
    --validate) "$SCRIPT_DIR/validate-installation.sh" ;;
    --help|-h) show_help; exit 0 ;;
    *) log_error "Unknown option: $arg"; show_help; exit 1 ;;
  esac
done

# Final validation
log_info "Validating development environment..."

declare -A tools=(
  [nvm]="Node Version Manager"
  [pyenv]="Python Version Manager"
  [sdk]="SDKMAN for Java"
  [rustup]="Rust Toolchain Manager"
  [ghcup]="Haskell Toolchain Manager"
)

for cmd in "${!tools[@]}"; do
  if ! command -v "$cmd" &>/dev/null; then
    log_warning "${tools[$cmd]} ($cmd) not found in PATH"
  else
    log_success "${tools[$cmd]} is installed: $($cmd --version 2>/dev/null || echo "version info unavailable")"
  fi
done

if [[ "$ENV_TYPE" == "WSL2" ]]; then
  log_info "WSL2 detected. Some changes may require a WSL restart."
  log_info "To restart WSL, run 'wsl --shutdown' in PowerShell."
  log_info "Then reopen your WSL terminal."
fi

log_success "All requested components installed successfully."
log_info "Restart your terminal or re-login for full effect."
finish_logging
