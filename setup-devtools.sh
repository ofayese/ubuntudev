#!/usr/bin/env bash
# setup-devtools.sh - Dev tools setup using util-install
# Version: 1.0.0
# Last updated: 2025-06-13
set -euo pipefail

# shellcheck disable=SC2034  # VERSION used in logging/reporting
readonly VERSION="1.0.0"
readonly SCRIPT_DIR
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Dry-run mode support
readonly DRY_RUN="${DRY_RUN:-false}"

# Operating system detection for cross-platform compatibility
# shellcheck disable=SC2034  # OS_TYPE may be used by sourced utilities
readonly OS_TYPE
# shellcheck disable=SC2034  # OS_TYPE may be used by sourced utilities
OS_TYPE="$(uname -s)"

# Source utility modules with error checking
source "$SCRIPT_DIR/util-log.sh" || {
  echo "FATAL: Failed to source util-log.sh" >&2
  exit 1
}
source "$SCRIPT_DIR/util-env.sh" || {
  echo "FATAL: Failed to source util-env.sh" >&2
  exit 1
}
source "$SCRIPT_DIR/util-install.sh" || {
  echo "FATAL: Failed to source util-install.sh" >&2
  exit 1
}

# Use more accessible log path
readonly LOGFILE="${HOME}/.cache/ubuntu-dev-tools.log}"
mkdir -p "$(dirname "$LOGFILE")"
init_logging "$LOGFILE"

# Set up error handling - disable automatic exit on error and handle manually
set +e # Don't exit on errors, handle them manually

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

# Update with error handling
if sudo apt-get update -y >/dev/null 2>&1; then
  log_success "Package index updated successfully"
else
  log_warning "Package index update had some issues, but continuing..."
fi

stop_spinner "Updating package index"

# Step 2: Install system monitoring tools
((current_step++))
log_info "[$current_step/$total_steps] Installing system monitoring tools..."
show_progress "$current_step" "$total_steps" "DevTools Setup"
start_spinner "Installing system monitoring tools"

# Install packages individually with error tolerance
monitoring_packages=(htop btop glances ncdu iftop)
failed_monitoring=()

for pkg in "${monitoring_packages[@]}"; do
  log_info "Attempting to install $pkg..."
  if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" >/dev/null 2>&1; then
    log_success "Installed $pkg"
  else
    log_warning "Failed to install $pkg - may not be available"
    failed_monitoring+=("$pkg")
  fi
done

if [ ${#failed_monitoring[@]} -gt 0 ]; then
  log_warning "Some monitoring tools failed to install: ${failed_monitoring[*]}"
  log_info "Basic monitoring tools (like htop) should still be available"
fi

stop_spinner "Installing system monitoring tools"

# Step 3: Install CLI utilities
((current_step++))
log_info "[$current_step/$total_steps] Installing CLI utilities..."
show_progress "$current_step" "$total_steps" "DevTools Setup"
start_spinner "Installing CLI utilities"

# Install packages individually with error tolerance
cli_packages=(bat fzf ripgrep git wget curl)
failed_cli=()

for pkg in "${cli_packages[@]}"; do
  log_info "Attempting to install $pkg..."
  if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" >/dev/null 2>&1; then
    log_success "Installed $pkg"
  else
    log_warning "Failed to install $pkg - may not be available"
    failed_cli+=("$pkg")
  fi
done

if [ ${#failed_cli[@]} -gt 0 ]; then
  log_warning "Some CLI utilities failed to install: ${failed_cli[*]}"
  log_info "Trying alternative names or fallbacks..."

  # Try alternative package names
  for pkg in "${failed_cli[@]}"; do
    case "$pkg" in
    "bat")
      if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y batcat >/dev/null 2>&1; then
        log_success "Installed batcat (bat alternative)"
        echo 'alias bat=batcat' >>"$HOME/.bashrc"
      fi
      ;;
    "ripgrep")
      if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y rg >/dev/null 2>&1; then
        log_success "Installed rg (ripgrep alternative)"
      fi
      ;;
    esac
  done
fi

stop_spinner "Installing CLI utilities"

# Step 4: Install eza from GitHub
((current_step++))
log_info "[$current_step/$total_steps] Installing eza from GitHub..."
show_progress "$current_step" "$total_steps" "DevTools Setup"
start_spinner "Installing eza from GitHub"

# Check if eza is already installed
if command -v eza &>/dev/null; then
  log_info "eza is already installed, skipping..."
else
  log_info "Attempting to install eza..."

  # First try installing from apt (available in newer Ubuntu/Debian)
  if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y eza >/dev/null 2>&1; then
    log_success "eza installed successfully via apt"
  else
    log_info "eza not available via apt, trying binary download..."

    # Try downloading the binary version from GitHub
    temp_dir="/tmp/eza_install_$$"
    mkdir -p "$temp_dir"

    if wget -q -O "$temp_dir/eza.tar.gz" "https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-gnu.tar.gz"; then
      log_info "Downloaded eza binary, installing..."
      if (cd "$temp_dir" && tar -xzf eza.tar.gz && sudo install -m 755 eza /usr/local/bin/eza); then
        log_success "eza installed successfully from binary"
        rm -rf "$temp_dir"
      else
        log_warning "Failed to install eza binary"
        rm -rf "$temp_dir"
      fi
    else
      log_warning "Failed to download eza binary. Creating alias to ls instead."
      # Ensure .bashrc exists and add the alias
      touch "$HOME/.bashrc"
      if ! grep -q 'alias eza=' "$HOME/.bashrc"; then
        echo 'alias eza="ls --color=auto"' >>"$HOME/.bashrc"
      fi
      log_info "eza alias created, will use ls with color output"
    fi
  fi
fi

stop_spinner "Installing eza from GitHub"

# Step 5: Install Zsh & Oh-My-Zsh
((current_step++))
log_info "[$current_step/$total_steps] Installing Zsh & Oh-My-Zsh..."
show_progress "$current_step" "$total_steps" "DevTools Setup"
start_spinner "Installing Zsh & Oh-My-Zsh"

# Install Zsh with error handling
if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y zsh >/dev/null 2>&1; then
  log_success "Installed zsh"

  # Install Oh-My-Zsh if not already present
  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    log_info "Installing Oh-My-Zsh..."
    if timeout 60 sh -c "RUNZSH=no CHSH=no KEEP_ZSHRC=yes $(wget --timeout=30 -qO- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" >/dev/null 2>&1; then
      log_success "Oh-My-Zsh installed successfully"
    else
      log_warning "Failed to install Oh-My-Zsh, but zsh is available"
    fi
  else
    log_info "Oh-My-Zsh is already installed"
  fi
else
  log_warning "Failed to install zsh"
fi

stop_spinner "Installing Zsh & Oh-My-Zsh"

log_success "DevTools setup completed successfully!"

# Report any issues but don't fail the entire script
total_failed=$((${#failed_monitoring[@]} + ${#failed_cli[@]}))
if [ $total_failed -gt 0 ]; then
  log_warning "Some optional packages failed to install, but core development tools are ready"
  log_info "You can manually install missing packages later if needed"
fi

# Verify critical tools are available
critical_missing=()
command -v wget >/dev/null || critical_missing+=("wget")
command -v curl >/dev/null || critical_missing+=("curl")
command -v git >/dev/null || critical_missing+=("git")

if [ ${#critical_missing[@]} -gt 0 ]; then
  log_error "Critical tools missing: ${critical_missing[*]}"
  log_error "DevTools setup failed - essential tools not available"
  finish_logging
  exit 1
fi

log_success "All critical development tools are available"
finish_logging
exit 0
