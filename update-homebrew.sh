#!/usr/bin/env bash
# update-homebrew.sh - Install and update Homebrew packages
set -euo pipefail

# Source utility modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-log.sh"
source "$SCRIPT_DIR/util-env.sh"

# Initialize logging
init_logging
log_info "Starting Homebrew installation and updates"

# Set error trap
set_error_trap

# Check if Homebrew is installed, install if not
if ! command_exists brew; then
    log_info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Check environment and add path configurations
    ENV_TYPE=$(detect_environment)
    if [[ "$ENV_TYPE" == "$ENV_WSL" ]]; then
        # WSL-specific setup
        if [[ -d "/home/linuxbrew" ]]; then
            log_info "Adding Homebrew to PATH for WSL..."
            echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> "$HOME/.profile"
            eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
        fi
    else
        # Regular Linux setup
        if [[ -d "/home/linuxbrew" ]]; then
            log_info "Adding Homebrew to PATH..."
            echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> "$HOME/.profile"
            eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
        fi
    fi
    
    log_success "Homebrew installed successfully"
else
    log_info "Homebrew is already installed"
fi

# Update Homebrew
log_info "Updating Homebrew..."
brew update
log_success "Homebrew updated successfully"

# Install common packages
log_info "Installing/updating common packages..."
BREW_PACKAGES=(
  "bat"       # Better cat
  "exa"       # Better ls
  "fd"        # Better find
  "fzf"       # Fuzzy finder
  "gh"        # GitHub CLI
  "jq"        # JSON processor
  "ripgrep"   # Better grep
  "tldr"      # Simplified man pages
  "zoxide"    # Better cd
  "starship"  # Cross-shell prompt
)

for pkg in "${BREW_PACKAGES[@]}"; do
    log_info "Installing/updating $pkg..."
    if brew list "$pkg" &>/dev/null; then
        brew upgrade "$pkg" || log_warning "Failed to upgrade $pkg"
    else
        brew install "$pkg" || log_warning "Failed to install $pkg"
    fi
done

# Cleanup
log_info "Running brew cleanup..."
brew cleanup

log_success "Homebrew packages installation and update complete"
finish_logging
