#!/usr/bin/env bash
set -euo pipefail

# Source utility modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-log.sh"
source "$SCRIPT_DIR/util-env.sh"
source "$SCRIPT_DIR/util-install.sh"
source "$SCRIPT_DIR/util-containers.sh"

# Initialize logging
init_logging
log_info "Dev Containers setup started"

# Detect environment using utility function
ENV_TYPE=$(detect_environment)
print_env_banner

# Main logic based on environment
if [[ "$ENV_TYPE" == "$ENV_WSL" ]]; then
  log_info "Validating Docker Desktop for Windows integration..."

  if ! check_docker; then
    log_error "Docker not running in Windows or not connected to WSL2"
    log_info "Please launch Docker Desktop in Windows and enable WSL integration"
    finish_logging
    exit 1
  fi
  
  # Additional WSL-specific Docker validation
  if ! check_wsl_docker_integration; then
    log_error "WSL Docker integration validation failed"
    finish_logging
    exit 1
  fi

else
  log_info "Installing Docker Desktop for Ubuntu Desktop..."
  if ! install_docker_desktop_linux; then
    log_error "Failed to install Docker Desktop for Linux"
    finish_logging
    exit 1
  fi
fi

# Add current user to docker group using utility function
setup_docker_user

log_success "Docker Desktop setup complete. Please log out and log in again for group changes to apply"
finish_logging
