#!/usr/bin/env bash
# setup-devtools.sh - Dev tools setup using util-install
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-log.sh"
source "$SCRIPT_DIR/util-env.sh"
source "$SCRIPT_DIR/util-install.sh"

LOGFILE="/var/log/ubuntu-dev-tools.log"
init_logging "$LOGFILE"

# Define installation steps for progress tracking
declare -a INSTALL_STEPS=(
  "update_package_index"
  "system_monitoring"
  "cli_utilities" 
  "eza_from_github"
  "zsh_setup"
)

current_step=0
total_steps=${#INSTALL_STEPS[@]}

# Step 1: Update package index
((current_step++))
log_info "[$current_step/$total_steps] Updating package index..."
show_progress "$current_step" "$total_steps" "DevTools Setup"
start_spinner "Updating package index"
update_package_index
stop_spinner "Updating package index"

# Step 2: Install system monitoring tools
((current_step++))
log_info "[$current_step/$total_steps] Installing system monitoring tools..."
show_progress "$current_step" "$total_steps" "DevTools Setup"
start_spinner "Installing system monitoring tools"
install_packages htop btop glances ncdu iftop
stop_spinner "Installing system monitoring tools"

# Step 3: Install CLI utilities
((current_step++))
log_info "[$current_step/$total_steps] Installing CLI utilities..."
show_progress "$current_step" "$total_steps" "DevTools Setup"
start_spinner "Installing CLI utilities"
install_packages bat fzf ripgrep
stop_spinner "Installing CLI utilities"

# Step 4: Install eza from GitHub
((current_step++))
log_info "[$current_step/$total_steps] Installing eza from GitHub..."
show_progress "$current_step" "$total_steps" "DevTools Setup"
start_spinner "Installing eza from GitHub"
# Check if eza is already installed
if command -v eza &> /dev/null; then
  log_info "eza is already installed, skipping..."
else
  install_from_github "eza-community/eza" "_amd64.deb" "sudo dpkg -i {}" "eza" || {
    log_warning "Failed to install eza from GitHub. Creating alias to ls instead."
    echo 'alias eza="ls"' >> "$HOME/.bashrc"
  }
fi
stop_spinner "Installing eza from GitHub"

# Step 5: Install Zsh & Oh-My-Zsh
((current_step++))
log_info "[$current_step/$total_steps] Installing Zsh & Oh-My-Zsh..."
show_progress "$current_step" "$total_steps" "DevTools Setup"
start_spinner "Installing Zsh & Oh-My-Zsh"
install_packages zsh
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(wget -qO- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" >/dev/null 2>&1
fi
stop_spinner "Installing Zsh & Oh-My-Zsh"

log_success "DevTools setup completed successfully!"

finish_logging
