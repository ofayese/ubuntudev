#!/usr/bin/env bash
# Minimal test to isolate the issue

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# Source utilities
source "${SCRIPT_DIR}/util-log.sh" || {
    echo "FATAL: Failed to source util-log.sh" >&2
    exit 1
}
source "${SCRIPT_DIR}/util-env.sh" || {
    echo "FATAL: Failed to source util-env.sh" >&2
    exit 1
}

echo "DEBUG: Starting minimal test"

# Start logging (removed problematic init_logging call)
log_info "Terminal enhancements setup started (minimal test)"

echo "DEBUG: After log_info"

# Detect environment
ENV_TYPE=$(detect_environment)
log_info "Environment detected: $ENV_TYPE"

echo "DEBUG: After environment detection"

# Check if desktop environment is available for GUI apps
if [[ "$ENV_TYPE" == "$ENV_HEADLESS" ]]; then
    log_warning "Headless environment detected - some GUI features may not work"
fi

echo "DEBUG: After headless check"

# Define installation steps for progress tracking
declare -a SETUP_STEPS
SETUP_STEPS=(
    "fonts_and_terminal"
    "alacritty_config"
    "tmux_setup"
    "starship_install"
    "shell_configs"
)

echo "DEBUG: After SETUP_STEPS definition"

current_step=0
total_steps=${#SETUP_STEPS[@]}

echo "DEBUG: Steps configured - $current_step/$total_steps"

# Step 1: Install Alacritty + Fonts
((current_step++))
log_info "[$current_step/$total_steps] Installing fonts and terminal emulator..."

echo "DEBUG: After step 1 log"

show_progress "$current_step" "$total_steps" "Terminal Setup"

echo "DEBUG: After show_progress call"

log_success "Minimal test completed successfully"
