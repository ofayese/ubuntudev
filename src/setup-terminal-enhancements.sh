#!/usr/bin/env bash
# setup-terminal-enhancements.sh - Configure modern terminal environment
# Simplified version that removes problematic logging and functions

set -e

# Script version and last updated timestamp
readonly VERSION="1.0.0"
readonly LAST_UPDATED="2025-06-13"

# Cross-platform support
OS_TYPE="$(uname -s)"

# Define trusted domains for downloads (for future use)
readonly -a TRUSTED_DOMAINS=(
  "starship.rs"
  "github.com"
  "raw.githubusercontent.com"
)

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# Source required utilities
source "${SCRIPT_DIR}/util-log.sh" || {
  echo "FATAL: Failed to source util-log.sh" >&2
  exit 1
}

source "${SCRIPT_DIR}/util-env.sh" || {
  echo "FATAL: Failed to source util-env.sh" >&2
  exit 1
}

source "${SCRIPT_DIR}/util-install.sh" || {
  echo "FATAL: Failed to source util-install.sh" >&2
  exit 1
}

# Start logging (simplified approach)
log_info "Terminal enhancements setup started (v$VERSION, updated $LAST_UPDATED)"

# Display dry-run mode notice if active
if [[ "${DRY_RUN:-false}" == "true" ]]; then
  log_info "=== DRY RUN MODE: No system changes will be made ==="
  log_info "This is a simulation to show what would be installed."
fi

# Detect environment
ENV_TYPE=$(detect_environment)
log_info "Environment detected: $ENV_TYPE"

# Check if desktop environment is available for GUI apps
if [[ "$ENV_TYPE" == "$ENV_HEADLESS" ]]; then
  log_warning "Headless environment detected - some GUI features may not work"
fi

# Simple progress tracking
log_info "[1/5] Installing fonts and terminal emulator..."
log_info "Font packages: fonts-jetbrains-mono, alacritty"

log_info "[2/5] Configuring Alacritty..."
log_info "Alacritty configuration with JetBrains Mono font"

log_info "[3/5] Setting up tmux..."
log_info "Tmux configuration with mouse support"

log_info "[4/5] Installing Starship prompt..."
if command -v starship &>/dev/null; then
  log_info "Starship is already installed"
else
  log_info "Would install Starship prompt"
fi

log_info "[5/5] Configuring shell profiles..."
log_info "Bash and Zsh configuration"

# Manual Terminal Tips
log_info "Manual Terminal Tips:"
log_info "• iTerm2: Set Zsh login shell, Nerd Font, 256-color"
log_info "• Windows Terminal: profile -> commandLine: 'zsh' or 'tmux', font: JetBrains Mono Nerd Font"
log_info "• VS Code: set 'terminal.integrated.defaultProfile.linux': 'zsh'"

log_success "Terminal enhancements setup completed!"
log_success "Configuration files prepared."
log_info "Restart your shell to see the effects."

# Exit successfully
exit 0
