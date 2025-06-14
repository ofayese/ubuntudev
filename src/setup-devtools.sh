#!/usr/bin/env bash
# setup-devtools.sh - Dev tools setup with improved progress reporting and timeout protection
# Version: 1.0.0
# Last updated: 2025-06-14
set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# Source utility modules
# shellcheck disable=SC1091
source "$SCRIPT_DIR/util-log.sh" || {
  echo "FATAL: Failed to source util-log.sh" >&2
  exit 1
}

# shellcheck disable=SC1091
source "$SCRIPT_DIR/util-install.sh" || {
  echo "FATAL: Failed to source util-install.sh" >&2
  exit 1
}

# Total number of setup steps for progress tracking
readonly TOTAL_STEPS=5
current_step=0

# Start setup with timestamped header
log_step_start "DevTools Setup" $((++current_step)) "$TOTAL_STEPS"

# 1. Update package index with timeout protection
log_substep "Updating package index" "IN PROGRESS"
if run_with_timeout "sudo apt-get update -y" "Package index update" 120; then
  log_substep "Package index updated" "SUCCESS"
else
  log_substep "Package index update" "WARNING" "Continuing despite issues"
fi

# 2. Install system monitoring tools with progress tracking
log_substep "Installing system monitoring tools" "IN PROGRESS"
monitoring_packages=(htop btop glances ncdu iftop)
total_packages=${#monitoring_packages[@]}
installed=0
failed=()

for pkg in "${monitoring_packages[@]}"; do
  ((installed++))
  show_progress "$installed" "$total_packages" "Installing monitoring tools"

  if run_with_timeout "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $pkg" "Installing $pkg" 120; then
    log_substep "Installing $pkg" "SUCCESS"
  else
    log_substep "Installing $pkg" "WARNING" "Failed to install, continuing anyway"
    failed+=("$pkg")
  fi
done

if [ ${#failed[@]} -gt 0 ]; then
  log_substep "Monitoring tools installation" "WARNING" "${#failed[@]} packages failed: ${failed[*]}"
else
  log_substep "Monitoring tools installation" "SUCCESS" "All packages installed successfully"
fi

log_step_complete "Install System Monitoring Tools" "$current_step" "$TOTAL_STEPS"

# 3. Install CLI utilities with progress tracking
log_step_start "Install CLI Utilities" $((++current_step)) "$TOTAL_STEPS"
cli_packages=(bat fzf ripgrep git wget curl)
total_packages=${#cli_packages[@]}
installed=0
failed=()

for pkg in "${cli_packages[@]}"; do
  ((installed++))
  show_progress "$installed" "$total_packages" "Installing CLI utilities"

  if run_with_timeout "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $pkg" "Installing $pkg" 120; then
    log_substep "Installing $pkg" "SUCCESS"
  else
    log_substep "Installing $pkg" "WARNING" "Failed to install, continuing anyway"
    failed+=("$pkg")
  fi
done

# Try alternative package names for failed installs
command -v bat &>/dev/null || {
  log_substep "Installing batcat (bat alternative)" "IN PROGRESS"
  if run_with_timeout "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends batcat" "Installing batcat" 120; then
    log_substep "Installing batcat alias" "IN PROGRESS"
    echo 'alias bat=batcat' >>"$HOME/.bashrc"
    log_substep "Installing batcat" "SUCCESS" "Added alias bat=batcat to .bashrc"
  else
    log_substep "Installing batcat" "WARNING" "Failed to install alternative"
  fi
}

log_step_complete "Install CLI Utilities" "$current_step" "$TOTAL_STEPS"

# 4. Install eza from GitHub with proper progress reporting
log_step_start "Install eza File Lister" $((++current_step)) "$TOTAL_STEPS"

if command -v eza &>/dev/null; then
  log_substep "eza already installed" "SUCCESS" "$(eza --version 2>&1 | head -n1 || echo 'Unknown version')"
else
  log_substep "Installing eza via apt" "IN PROGRESS"
  if run_with_timeout "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y eza" "Installing eza via apt" 120; then
    log_substep "Installing eza via apt" "SUCCESS"
  else
    log_substep "eza not available via apt" "WARNING" "Trying binary download instead"
    temp_dir="/tmp/eza_install_$$"
    mkdir -p "$temp_dir"

    log_substep "Downloading eza from GitHub" "IN PROGRESS"
    if run_with_timeout "wget -q -O \"$temp_dir/eza.tar.gz\" \"https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-gnu.tar.gz\"" "Downloading eza" 60; then
      log_substep "Installing eza binary" "IN PROGRESS"
      if run_with_timeout "(cd \"$temp_dir\" && tar -xzf eza.tar.gz && sudo install -m 755 eza /usr/local/bin/eza)" "Installing eza binary" 30; then
        log_substep "Installing eza binary" "SUCCESS"
      else
        log_substep "Installing eza binary" "FAILED" "Could not extract or install"
        log_substep "Creating eza alias" "IN PROGRESS"
        touch "$HOME/.bashrc"
        if ! grep -q 'alias eza=' "$HOME/.bashrc"; then
          echo 'alias eza="ls --color=auto"' >>"$HOME/.bashrc"
          log_substep "Created eza alias" "SUCCESS" "Using ls as fallback"
        fi
      fi
    else
      log_substep "Downloading eza" "FAILED" "Could not download from GitHub"
      log_substep "Creating eza alias" "IN PROGRESS"
      touch "$HOME/.bashrc"
      if ! grep -q 'alias eza=' "$HOME/.bashrc"; then
        echo 'alias eza="ls --color=auto"' >>"$HOME/.bashrc"
        log_substep "Created eza alias" "SUCCESS" "Using ls as fallback"
      fi
    fi

    # Cleanup temp directory
    rm -rf "$temp_dir"
  fi
fi

log_step_complete "Install eza File Lister" "$current_step" "$TOTAL_STEPS"

# 5. Install Zsh & Oh-My-Zsh with proper progress reporting
log_step_start "Install Zsh & Oh-My-Zsh" $((++current_step)) "$TOTAL_STEPS"

log_substep "Installing Zsh" "IN PROGRESS"
if run_with_timeout "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y zsh" "Installing Zsh" 180; then
  log_substep "Installing Zsh" "SUCCESS"
else
  log_substep "Installing Zsh" "WARNING" "Failed to install Zsh, continuing anyway"
fi

if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  log_substep "Installing Oh-My-Zsh" "IN PROGRESS"
  if run_with_timeout "RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \"$(wget --timeout=30 -qO- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\"" "Installing Oh-My-Zsh" 180; then
    log_substep "Installing Oh-My-Zsh" "SUCCESS"
  else
    log_substep "Installing Oh-My-Zsh" "WARNING" "Failed to install Oh-My-Zsh"
  fi
else
  log_substep "Oh-My-Zsh" "SUCCESS" "Already installed"
fi

log_step_complete "Install Zsh & Oh-My-Zsh" "$current_step" "$TOTAL_STEPS"

# Verify critical tools are installed
log_substep "Verifying critical tools" "IN PROGRESS"
critical_missing=()
command -v wget >/dev/null || critical_missing+=("wget")
command -v curl >/dev/null || critical_missing+=("curl")
command -v git >/dev/null || critical_missing+=("git")

if [ ${#critical_missing[@]} -gt 0 ]; then
  log_error "Critical tools missing: ${critical_missing[*]}"
  log_error "DevTools setup failed - essential tools not available"
  exit 1
else
  log_substep "Verifying critical tools" "SUCCESS" "All critical tools available"
fi

# Final summary with timestamp
log_success "DevTools setup completed successfully at $(date '+%Y-%m-%d %H:%M:%S')"
exit 0
