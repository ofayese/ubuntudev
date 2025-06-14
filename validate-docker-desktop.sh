#!/usr/bin/env bash
set -euo pipefail

# Source utility modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-log.sh"
source "$SCRIPT_DIR/util-env.sh"
source "$SCRIPT_DIR/util-install.sh"

# Initialize logging
init_logging
log_info "Docker Desktop validation started"

# Check Docker availability using consolidated function
if ! check_docker; then
  log_error "Docker validation failed"
  log_info "Please start Docker Desktop and ensure WSL2 integration is enabled"
  finish_logging
  exit 1
fi

# Check WSL Docker integration
ENV_TYPE=$(detect_environment)
if [[ "$ENV_TYPE" == "$ENV_WSL" ]]; then
  log_info "Checking WSL2 Docker integration..."
  
  if ! check_wsl_docker_integration; then
    log_error "WSL Docker integration validation failed"
    finish_logging
    exit 1
  fi
  
  # Check systemd status in WSL2
  log_info "Checking systemd status in WSL2..."
  if is_systemd_running; then
    log_success "systemd is running inside WSL2"
  else
    log_error "systemd is not running inside WSL2"
    log_info "Ensure you have 'systemd=true' under [boot] in /etc/wsl.conf and restart WSL"
    finish_logging
    exit 1
  fi
fi

log_success "All checks passed! Docker Desktop with WSL2/systemd is ready"
finish_logging
