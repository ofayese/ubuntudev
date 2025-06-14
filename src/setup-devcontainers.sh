#!/usr/bin/env bash
set -euo pipefail

# Source utility modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-log.sh"
source "$SCRIPT_DIR/util-env.sh"
source "$SCRIPT_DIR/util-install.sh"
source "$SCRIPT_DIR/util-containers.sh"

# Start logging (removed problematic init_logging call)
log_info "Dev Containers setup started"

# Detect environment using utility function
ENV_TYPE=$(detect_environment)
log_info "Environment detected: $ENV_TYPE"

# Main logic based on environment
if [[ "$ENV_TYPE" == "$ENV_WSL" ]]; then
  log_info "Validating Docker Desktop for Windows integration..."

  if ! check_docker; then
    log_error "Docker not running in Windows or not connected to WSL2"
    log_info "Please launch Docker Desktop in Windows and enable WSL integration"

    # Create a file with instructions for the user
    cat >~/docker-desktop-instructions.txt <<'EOF'
# Docker Desktop Setup Instructions for WSL2

1. Install Docker Desktop for Windows if not already installed:
   - Download from: https://www.docker.com/products/docker-desktop
   - Run the installer and follow the instructions

2. Configure Docker Desktop for WSL2:
   - Open Docker Desktop > Settings > Resources > WSL Integration
   - Enable integration with your WSL2 distro
   - Click "Apply & Restart"

3. Verify the setup:
   - Open your WSL2 terminal and run: docker version
   - If successful, you should see both client and server information

For more information, visit: https://docs.docker.com/desktop/wsl/
EOF

    log_info "Created setup instructions at: ~/docker-desktop-instructions.txt"
    exit 1
  fi

  # Additional WSL-specific Docker validation
  if ! check_wsl_docker_integration; then
    log_error "WSL Docker integration validation failed"
    log_info "Attempting to fix Docker context..."

    # Try to fix Docker context
    docker context use default >/dev/null 2>&1 || true

    # Check again
    if ! check_wsl_docker_integration; then
      log_error "WSL Docker integration validation failed after attempted fix"
      exit 1
    else
      log_success "Successfully fixed Docker context"
    fi
  fi

else
  log_info "Installing Docker Desktop for Ubuntu Desktop..."
  if ! install_docker_desktop_linux; then
    log_error "Failed to install Docker Desktop for Linux"
    exit 1
  fi
fi

# Add current user to docker group using utility function
setup_docker_user

log_success "Docker Desktop setup complete. Please log out and log in again for group changes to apply"

# Exit successfully
exit 0
