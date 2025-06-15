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

  # Quick, non-blocking package list update only
  log_info "Updating package lists (quick mode)..."
  if timeout 30 sudo apt-get update -q >/dev/null 2>&1; then
    log_success "Package lists updated"
  else
    log_warning "Package list update skipped (timeout or permission issue)"
  fi

  log_success "System packages check completed"
}

# Function to update version managers and languages
update_languages() {
  log_info "Updating language environments..."
  start_spinner "Updating language environments"

  # Update Node.js via NVM
  if command -v nvm >/dev/null 2>&1; then
    log_info "Updating NVM..."

    # Source NVM in the current shell
    export NVM_DIR="$HOME/.nvm"
    # shellcheck disable=SC1091
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    # Try to update Node.js versions, but don't fail if they already exist
    if nvm install --lts >/dev/null 2>&1; then
      log_success "Updated Node.js LTS"
    else
      log_info "Node.js LTS already at latest version or update failed"
    fi

    if nvm install node >/dev/null 2>&1; then
      log_success "Updated Node.js current"
    else
      log_info "Node.js current already at latest version or update failed"
    fi

    if nvm use --lts >/dev/null 2>&1; then
      log_success "Set LTS as default"
    else
      log_warning "Failed to set LTS as default"
    fi
  else
    log_warning "NVM not found, skipping Node.js update"
  fi

  # Update Python via pyenv
  if command -v pyenv >/dev/null 2>&1; then
    log_info "Updating pyenv..."

    # Update pyenv itself
    if (cd "$HOME/.pyenv" && git pull) >/dev/null 2>&1; then
      log_success "Updated pyenv"
    else
      log_warning "Failed to update pyenv"
    fi

    # Update Python versions - allow these to fail gracefully
    if pyenv install -s 3.12.0 >/dev/null 2>&1; then
      log_success "Python 3.12.0 ready"
    else
      log_info "Python 3.12.0 install skipped or failed"
    fi

    if pyenv install -s 3.11.8 >/dev/null 2>&1; then
      log_success "Python 3.11.8 ready"
    else
      log_info "Python 3.11.8 install skipped or failed"
    fi

    if pyenv rehash >/dev/null 2>&1; then
      log_success "Pyenv rehashed"
    else
      log_warning "Pyenv rehash failed"
    fi
  else
    log_warning "pyenv not found, skipping Python update"
  fi

  # Update Rust via rustup
  if command -v rustup >/dev/null 2>&1; then
    log_info "Updating Rust toolchain..."
    if rustup update >/dev/null 2>&1; then
      log_success "Rust toolchain updated"
    else
      log_warning "Failed to update Rust toolchain"
    fi
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
    if sdk selfupdate >/dev/null 2>&1; then
      log_success "SDKMAN updated"
    else
      log_warning "Failed to update SDKMAN"
    fi

    # Check for updates
    if sdk update >/dev/null 2>&1; then
      log_success "SDKMAN packages checked for updates"
    else
      log_warning "Failed to check SDKMAN updates"
    fi
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
    if code --update-extensions >/dev/null 2>&1; then
      log_success "VS Code extensions updated"
    else
      log_warning "Failed to update VS Code extensions"
    fi
  fi

  # Update VS Code Insiders extensions
  if command -v code-insiders >/dev/null 2>&1; then
    log_info "Updating VS Code Insiders extensions..."
    if code-insiders --update-extensions >/dev/null 2>&1; then
      log_success "VS Code Insiders extensions updated"
    else
      log_warning "Failed to update VS Code Insiders extensions"
    fi
  fi

  log_success "VS Code extensions updated"
}

# Function to update npm global packages
update_npm_packages() {
  log_info "Updating npm global packages..."

  if command -v npm >/dev/null 2>&1; then
    # Update npm itself
    if npm install -g npm@latest >/dev/null 2>&1; then
      log_success "npm updated"
    else
      log_warning "Failed to update npm"
    fi

    # Update global packages
    if npm update -g >/dev/null 2>&1; then
      log_success "npm global packages updated"
    else
      log_warning "Failed to update npm global packages"
    fi

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
    if python -m pip install --upgrade pip >/dev/null 2>&1; then
      log_success "pip updated"
    else
      log_warning "Failed to update pip"
    fi

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
        if python -m pip install --upgrade "$package" >/dev/null 2>&1; then
          log_success "Updated $package"
        else
          log_warning "Failed to update $package"
        fi
      fi
    done

    log_success "Python packages updated"
  else
    log_warning "pip not found, skipping Python packages update"
  fi
}

# Function to run the full update
run_full_update() {
  # Define update steps for progress tracking
  declare -a UPDATE_STEPS=(
    "system_packages"
    "languages"
    "containers"
    "vscode_extensions"
    "npm_packages"
    "python_packages"
  )

  # Add WSL step if applicable
  if [ "$ENV_TYPE" = "WSL2" ]; then
    UPDATE_STEPS+=("wsl_config")
  fi

  local current_step=0
  local total_steps=${#UPDATE_STEPS[@]}

  log_info "Starting full environment update with $total_steps steps"

  # Step 1: Update system packages
  ((current_step++))
  log_info "[$current_step/$total_steps] Updating system packages..."
  show_progress "$current_step" "$total_steps" "Environment Update"
  update_system_packages

  # Step 2: Update languages
  ((current_step++))
  log_info "[$current_step/$total_steps] Updating language environments..."
  show_progress "$current_step" "$total_steps" "Environment Update"
  update_languages

  # Step 3: Update containers
  ((current_step++))
  log_info "[$current_step/$total_steps] Updating container tools..."
  show_progress "$current_step" "$total_steps" "Environment Update"
  update_containers

  # Step 4: Update VS Code extensions
  ((current_step++))
  log_info "[$current_step/$total_steps] Updating VS Code extensions..."
  show_progress "$current_step" "$total_steps" "Environment Update"
  update_vscode_extensions

  # Step 5: Update npm packages
  ((current_step++))
  log_info "[$current_step/$total_steps] Updating npm packages..."
  show_progress "$current_step" "$total_steps" "Environment Update"
  update_npm_packages

  # Step 6: Update Python packages
  ((current_step++))
  log_info "[$current_step/$total_steps] Updating Python packages..."
  show_progress "$current_step" "$total_steps" "Environment Update"
  update_python_packages

  # WSL-specific updates (Step 7 if applicable)
  if [ "$ENV_TYPE" = "WSL2" ]; then
    ((current_step++))
    log_info "[$current_step/$total_steps] Updating WSL configuration..."
    show_progress "$current_step" "$total_steps" "Environment Update"
    start_spinner "Checking WSL configuration"

    # Source util-wsl.sh and run setup, but don't fail the entire update if it fails
    if source "$SCRIPT_DIR/util-wsl.sh" && setup_wsl_environment >/dev/null 2>&1; then
      log_success "WSL configuration updated"
    else
      log_warning "WSL configuration update had issues"
    fi

    stop_spinner "Checking WSL configuration"
  fi

  log_success "Full environment update completed!"
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
    --help | -h)
      show_help
      exit 0
      ;;
    *)
      log_error "Unknown option: $arg"
      show_help
      exit 1
      ;;
    esac
  done
fi

log_success "Update completed successfully."
finish_logging
