#!/usr/bin/env bash
# update-environment.sh - Updates the development environment components
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check for required utility scripts
for util in "$SCRIPT_DIR/util-log.sh" "$SCRIPT_DIR/util-env.sh"; do
  if [ ! -f "$util" ]; then
    echo "[ERROR] Required utility script $util not found. Exiting." >&2
    exit 1
  fi
done

source "$SCRIPT_DIR/util-log.sh"
source "$SCRIPT_DIR/util-env.sh"

# Initialize logging
init_logging

# Set error trap
set_error_trap

# Detect environment
ENV_TYPE=$(detect_environment)
log_info "Detected environment: $ENV_TYPE"

# Function to update system packages
update_system_packages() {
  log_info "Updating system packages..."
  
  # Update package lists
  log_cmd "sudo apt-get update -q" "Updating package lists"
  
  # Upgrade packages
  log_cmd "sudo apt-get upgrade -y" "Upgrading packages"
  
  # Clean up
  log_cmd "sudo apt-get autoremove -y" "Removing unused packages"
  log_cmd "sudo apt-get autoclean -y" "Cleaning package cache"
  
  log_success "System packages updated"
}

# Function to update version managers and languages
update_languages() {
  log_info "Updating language environments..."
  
  # Update Node.js via NVM
  if command -v nvm >/dev/null 2>&1; then
    log_info "Updating NVM..."
    
    # Source NVM in the current shell
    export NVM_DIR="$HOME/.nvm"
    # shellcheck disable=SC1091
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    log_cmd "nvm install --lts" "Updating Node.js LTS"
    log_cmd "nvm install node" "Updating Node.js current"
    log_cmd "nvm use --lts" "Setting LTS as default"
  else
    log_warning "NVM not found, skipping Node.js update"
  fi
  
  # Update Python via pyenv
  if command -v pyenv >/dev/null 2>&1; then
    log_info "Updating pyenv..."
    
    # Update pyenv itself
    log_cmd "(cd \"$HOME/.pyenv\" && git pull)" "Updating pyenv"
    
    # Update Python versions
    log_cmd "pyenv install -s 3.12.0" "Installing/updating Python 3.12" || true
    log_cmd "pyenv install -s 3.11.8" "Installing/updating Python 3.11" || true
    log_cmd "pyenv rehash" "Rehashing pyenv"
  else
    log_warning "pyenv not found, skipping Python update"
  fi
  
  # Update Rust via rustup
  if command -v rustup >/dev/null 2>&1; then
    log_info "Updating Rust toolchain..."
    log_cmd "rustup update" "Updating Rust"
  else
    log_warning "rustup not found, skipping Rust update"
  fi
  
  # Update SDKMAN packages
  if [ -d "$HOME/.sdkman" ]; then
    log_info "Updating SDKMAN packages..."
    
    # Source SDKMAN
    export SDKMAN_DIR="$HOME/.sdkman"
    # shellcheck disable=SC1091
    [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"
    
    # Update SDKMAN itself
    log_cmd "sdk selfupdate" "Updating SDKMAN"
    
    # Update installed Java versions
    log_cmd "sdk update" "Checking for updates"
  else
    log_warning "SDKMAN not found, skipping Java updates"
  fi
  
  log_success "Language environments updated"
}

# Function to update container tools
update_containers() {
  log_info "Updating container tools..."
  
  # Update containerd if installed
  if command -v containerd >/dev/null 2>&1; then
    log_info "containerd detected - managed by package system"
  fi
  
  # Update nerdctl if installed directly (not via package manager)
  if command -v nerdctl >/dev/null 2>&1; then
    log_info "Checking for nerdctl updates..."
    
    # Get installed version
    CURRENT_VERSION=$(nerdctl version | grep "Version:" | awk '{print $2}')
    
    # Get latest version
    LATEST_VERSION=$(curl -s https://api.github.com/repos/containerd/nerdctl/releases/latest | 
                    grep tag_name | cut -d '"' -f 4 | sed 's/v//')
    
    if [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
      log_info "Updating nerdctl from $CURRENT_VERSION to $LATEST_VERSION..."
      
      # Download latest nerdctl
      NERDCTL_URL=$(curl -s https://api.github.com/repos/containerd/nerdctl/releases/latest |
        grep browser_download_url | grep 'nerdctl-.*-linux-amd64.tar.gz' | head -1 | cut -d '"' -f 4)
      
      if [ -n "$NERDCTL_URL" ]; then
        log_cmd "wget -q -O /tmp/nerdctl.tar.gz $NERDCTL_URL" "Downloading nerdctl"
        log_cmd "sudo tar -C /usr/local/bin -xzf /tmp/nerdctl.tar.gz nerdctl" "Installing nerdctl"
        log_cmd "sudo chmod +x /usr/local/bin/nerdctl" "Setting permissions"
        log_cmd "rm -f /tmp/nerdctl.tar.gz" "Cleaning up"
      else
        log_warning "Failed to get nerdctl download URL"
      fi
    else
      log_info "nerdctl is already at the latest version ($CURRENT_VERSION)"
    fi
  fi
  
  log_success "Container tools updated"
}

# Function to update VS Code extensions
update_vscode_extensions() {
  log_info "Checking VS Code..."
  
  # Check if in WSL mode
  if [ "$ENV_TYPE" = "WSL2" ]; then
    log_info "WSL environment detected - extensions managed by Windows VS Code"
    return
  fi
  
  # Update VS Code extensions for stable
  if command -v code >/dev/null 2>&1; then
    log_info "Updating VS Code extensions..."
    log_cmd "code --update-extensions" "Updating extensions"
  fi
  
  # Update VS Code Insiders extensions
  if command -v code-insiders >/dev/null 2>&1; then
    log_info "Updating VS Code Insiders extensions..."
    log_cmd "code-insiders --update-extensions" "Updating Insiders extensions"
  fi
  
  log_success "VS Code extensions updated"
}

# Function to update npm global packages
update_npm_packages() {
  log_info "Updating npm global packages..."
  
  if command -v npm >/dev/null 2>&1; then
    # Update npm itself
    log_cmd "npm install -g npm@latest" "Updating npm"
    
    # Update global packages
    log_cmd "npm update -g" "Updating global packages"
    
    log_success "npm packages updated"
  else
    log_warning "npm not found, skipping npm packages update"
  fi
}

# Function to update Python packages
update_python_packages() {
  log_info "Updating Python packages..."
  
  if command -v pip >/dev/null 2>&1; then
    # Update pip itself
    log_cmd "python -m pip install --upgrade pip" "Updating pip"
    
    # Update common global packages
    common_packages=(
      "virtualenv"
      "pipx"
      "poetry"
      "black"
      "ruff"
      "mypy"
      "pre-commit"
    )
    
    for package in "${common_packages[@]}"; do
      if pip list | grep -q "^$package "; then
        log_cmd "python -m pip install --upgrade $package" "Updating $package"
      fi
    done
    
    log_success "Python packages updated"
  else
    log_warning "pip not found, skipping Python packages update"
  fi
}

# Function to run the full update
run_full_update() {
  update_system_packages
  update_languages
  update_containers
  update_vscode_extensions
  update_npm_packages
  update_python_packages
  
  # WSL-specific updates
  if [ "$ENV_TYPE" = "WSL2" ]; then
    log_info "Checking WSL configuration..."
    source "$SCRIPT_DIR/util-wsl.sh"
    setup_wsl_environment
  fi
}

# Parse arguments
show_help() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  --all         Update everything (default if no options provided)"
  echo "  --system      Update system packages only"
  echo "  --languages   Update language environments (Node.js, Python, Rust, Java)"
  echo "  --containers  Update container tools"
  echo "  --npm         Update npm global packages"
  echo "  --python      Update Python packages"
  echo "  --help        Show this help message"
}

# Parse arguments or run full update if none provided
if [ $# -eq 0 ]; then
  run_full_update
else
  for arg in "$@"; do
    case "$arg" in
      --all) run_full_update ;;
      --system) update_system_packages ;;
      --languages) update_languages ;;
      --containers) update_containers ;;
      --vscode) update_vscode_extensions ;;
      --npm) update_npm_packages ;;
      --python) update_python_packages ;;
      --help|-h) show_help; exit 0 ;;
      *) log_error "Unknown option: $arg"; show_help; exit 1 ;;
    esac
  done
fi

log_success "Update completed successfully."
finish_logging
