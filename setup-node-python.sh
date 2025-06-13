#!/usr/bin/env bash
# setup-node-python.sh - Set up Node.js and Python development environments
set -euo pipefail

# Source utility scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/util-log.sh"
source "${SCRIPT_DIR}/util-env.sh"
source "${SCRIPT_DIR}/util-versions.sh"

# --- Python Version Configuration ---
declare -A PYTHON_CONFIG=(
  ["primary_version"]="3.12"
  ["fallback_versions"]="3.11 3.10"
  ["minimum_version"]="3.10"
)

# --- Node.js Version Configuration ---
declare -A NODE_CONFIG=(
  ["lts_version"]="lts/*"
  ["current_version"]="node"
  ["minimum_version"]="18.0.0"
)

# --- Network Operation Configuration ---
declare -A NETWORK_CONFIG=(
  ["timeout"]="30"
  ["retries"]="3"
  ["retry_delay"]="5"
  ["user_agent"]="Ubuntu-DevTools-Setup/1.0"
)

init_logging

# --- Detect if running in WSL ---
detect_wsl
IS_WSL=$?
if [[ $IS_WSL -eq 1 ]]; then
  log_info "WSL environment detected"
fi

# --- System Resource Validation ---
validate_system_resources() {
  log_info "Validating system resources for installation..."

  # Check memory
  local memory_gb
  memory_gb=$(free -g | awk '/^Mem:/ {print $2}')

  # Check disk space
  local disk_gb
  disk_gb=$(df "$HOME" | awk 'NR==2 {print int($4/1024/1024)}')

  # Minimum requirements
  local min_memory=2
  local min_disk=5

  log_info "System resources: ${memory_gb}GB RAM, ${disk_gb}GB available disk space"

  if [[ $memory_gb -lt $min_memory ]]; then
    log_warning "Low memory detected: ${memory_gb}GB (recommended: ${min_memory}GB)"
    log_info "Consider closing unnecessary applications during installation"
  fi

  if [[ $disk_gb -lt $min_disk ]]; then
    log_error "Insufficient disk space: ${disk_gb}GB (required: ${min_disk}GB)"
    log_info "Please free up disk space before continuing"
    return 1
  fi

  return 0
}

# --- Enhanced Network Operations ---
download_with_retry() {
  local url="$1"
  local output_file="$2"
  local description="$3"
  local max_attempts="${NETWORK_CONFIG[retries]}"
  local timeout="${NETWORK_CONFIG[timeout]}"
  local retry_delay="${NETWORK_CONFIG[retry_delay]}"
  local attempt=1

  log_info "Downloading $description..."

  while [[ $attempt -le $max_attempts ]]; do
    log_debug "Download attempt $attempt/$max_attempts: $url"

    if curl -fsSL --connect-timeout 10 --max-time "$timeout" \
      --retry 3 --retry-delay 2 --user-agent "${NETWORK_CONFIG[user_agent]}" \
      "$url" -o "$output_file" 2>/dev/null; then
      log_success "Download completed: $description"
      return 0
    else
      local exit_code=$?

      if [[ $attempt -eq $max_attempts ]]; then
        log_error "Download failed after $max_attempts attempts: $description"
        return $exit_code
      else
        log_warning "Download attempt $attempt failed, retrying in ${retry_delay}s..."
        sleep "$retry_delay"
        retry_delay=$((retry_delay + 2)) # Progressive backoff
      fi
    fi

    ((attempt++))
  done

  return 1
}

# === Node.js Setup via NVM ===
install_nvm_and_node() {
  log_info "Setting up Node.js (LTS and Current)..."

  # Create NVM directory
  export NVM_DIR="$HOME/.nvm"
  mkdir -p "$NVM_DIR"

  # Get latest NVM version from GitHub API
  log_info "Fetching latest NVM version..."
  local nvm_version_url="https://api.github.com/repos/nvm-sh/nvm/releases/latest"
  local nvm_version_file
  nvm_version_file=$(mktemp)

  if download_with_retry "$nvm_version_url" "$nvm_version_file" "NVM version info"; then
    NVM_VERSION=$(grep "tag_name" "$nvm_version_file" | cut -d '"' -f 4)
    if [[ -z "$NVM_VERSION" ]]; then
      NVM_VERSION="v0.39.7" # fallback if parsing fails
      log_warning "Could not parse NVM version, using fallback: $NVM_VERSION"
    else
      log_info "Latest NVM version: $NVM_VERSION"
    fi
  else
    NVM_VERSION="v0.39.7" # fallback if download fails
    log_warning "Could not fetch NVM version, using fallback: $NVM_VERSION"
  fi

  rm -f "$nvm_version_file"

  # Download and run NVM install script
  local nvm_install_url="https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh"
  local nvm_install_script
  nvm_install_script=$(mktemp)

  if download_with_retry "$nvm_install_url" "$nvm_install_script" "NVM installer"; then
    log_info "Running NVM installation script..."
    chmod +x "$nvm_install_script"
    bash "$nvm_install_script"
    local exit_code=$?
    rm -f "$nvm_install_script"

    if [[ $exit_code -ne 0 ]]; then
      log_error "NVM installation script failed with exit code: $exit_code"
      return $exit_code
    fi
  else
    log_error "Failed to download NVM installer"
    rm -f "$nvm_install_script"
    return 1
  fi

  # Load NVM in current shell
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1091
  [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

  # Configure shell profiles using improved function from util-versions.sh
  configure_nvm_environment

  # Install Node.js versions
  log_info "Installing Node.js versions..."

  # Install LTS version
  log_info "Installing Node.js LTS version..."
  if ! nvm install --lts; then
    log_warning "Failed to install Node.js LTS, trying specific version..."
    nvm install 20 || {
      log_error "Failed to install Node.js LTS"
      return 1
    }
  fi

  # Install current version
  log_info "Installing Node.js current version..."
  if ! nvm install node; then
    log_warning "Failed to install Node.js current, trying specific version..."
    nvm install 22 || log_warning "Failed to install Node.js current version"
  fi

  # Set LTS as default
  log_info "Setting Node.js LTS as default..."
  nvm alias default lts/* || nvm alias default "$(nvm version-remote --lts)" || {
    log_warning "Could not set LTS as default, using latest installed version"
    nvm alias default "$(nvm version)"
  }
  nvm use default

  # Install global npm packages with validation
  install_npm_packages

  return 0
}

# Improved npm package installation with validation
install_npm_packages() {
  log_info "Installing global npm packages..."

  # First upgrade npm itself
  log_info "Upgrading npm to latest version..."
  if ! npm install -g npm@latest; then
    log_warning "Failed to upgrade npm, continuing with current version"
  fi

  # Essential development packages
  local packages=(
    "yarn"
    "pnpm"
    "nx"
    "@angular/cli"
    "typescript"
    "ts-node"
    "eslint"
    "prettier"
    "nodemon"
  )

  local installed_count=0
  local failed_packages=()

  for package in "${packages[@]}"; do
    log_info "Installing $package..."
    if npm install -g "$package"; then
      ((installed_count++))
      log_success "Installed $package successfully"
    else
      failed_packages+=("$package")
      log_warning "Failed to install $package"
    fi

    # Small delay between packages to prevent rate limiting
    sleep 1
  done

  if [[ ${#failed_packages[@]} -eq 0 ]]; then
    log_success "All npm packages installed successfully"
  else
    log_warning "Some npm packages failed to install: ${failed_packages[*]}"
  fi

  log_info "Node.js installation results:"
  log_info "Installed Node.js versions:"
  nvm ls
  log_success "Current Node.js version: $(node -v)"
  log_success "Current npm version: $(npm -v)"

  return 0
}

# === Python Setup via pyenv ===
install_python() {
  log_info "Setting up Python development environment..."

  # Core dependencies
  log_info "Installing Python core dependencies..."
  sudo apt-get update -q
  sudo apt-get install -y python3 python3-pip python3-dev python3-venv python3-setuptools python3-wheel

  # Install Python build dependencies
  log_info "Installing Python build dependencies..."
  sudo apt-get install -y build-essential libssl-dev zlib1g-dev libbz2-dev \
    libreadline-dev libsqlite3-dev libncursesw5-dev xz-utils tk-dev \
    libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev curl

  # Install pyenv
  log_info "Installing pyenv..."
  local pyenv_installer_url="https://pyenv.run"
  local pyenv_installer_script
  pyenv_installer_script=$(mktemp)

  if download_with_retry "$pyenv_installer_url" "$pyenv_installer_script" "pyenv installer"; then
    log_info "Running pyenv installation script..."
    chmod +x "$pyenv_installer_script"
    bash "$pyenv_installer_script"
    local exit_code=$?
    rm -f "$pyenv_installer_script"

    if [[ $exit_code -ne 0 ]]; then
      log_error "pyenv installation script failed with exit code: $exit_code"
      return $exit_code
    fi
  else
    log_error "Failed to download pyenv installer"
    rm -f "$pyenv_installer_script"
    return 1
  fi

  # Configure shell profiles
  configure_pyenv_environment

  # Load pyenv in current shell
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)"

  # Install specific Python versions
  install_python_versions

  # Install Python packages
  install_python_packages

  return 0
}

# Function to install Python versions with fallback logic
install_python_versions() {
  log_info "Installing Python versions..."

  local primary_version="${PYTHON_CONFIG[primary_version]}"
  local fallback_versions="${PYTHON_CONFIG[fallback_versions]}"
  local installed=false

  # Try primary version first
  log_info "Attempting to install Python $primary_version..."

  # Find latest patch version for major.minor
  local latest_version
  latest_version=$(pyenv install --list | grep -E "^\s*${primary_version}\.[0-9]+$" | tail -1 | xargs)

  if [[ -n "$latest_version" ]]; then
    log_info "Installing Python $latest_version..."
    if pyenv install -s "$latest_version"; then
      log_success "Installed Python $latest_version"
      pyenv global "$latest_version"
      installed=true
    else
      log_warning "Failed to install Python $latest_version"
    fi
  else
    log_warning "No Python $primary_version versions found"
  fi

  # Try fallback versions if primary fails
  if [[ "$installed" != "true" ]]; then
    log_info "Trying fallback Python versions..."

    for version in $fallback_versions; do
      log_info "Attempting to install Python $version..."

      # Find latest patch version for this major.minor
      local fallback_latest
      fallback_latest=$(pyenv install --list | grep -E "^\s*${version}\.[0-9]+$" | tail -1 | xargs)

      if [[ -n "$fallback_latest" ]]; then
        log_info "Installing Python $fallback_latest..."
        if pyenv install -s "$fallback_latest"; then
          log_success "Installed Python $fallback_latest"
          pyenv global "$fallback_latest"
          installed=true
          break
        else
          log_warning "Failed to install Python $fallback_latest"
        fi
      fi
    done
  fi

  if [[ "$installed" != "true" ]]; then
    log_error "Failed to install any Python version"
    return 1
  fi

  # Verify installation
  log_info "Python setup complete"
  log_success "Active Python version: $(python --version 2>&1)"
  log_success "Python interpreter: $(pyenv which python)"

  return 0
}

# Function to install Python packages with validation
install_python_packages() {
  log_info "Installing Python packages..."

  # Upgrade pip first
  log_info "Upgrading pip..."
  python -m pip install --upgrade pip

  # Essential Python packages
  local packages=(
    "pipx"
    "pipenv"
    "virtualenv"
    "poetry"
    "black"
    "isort"
    "pytest"
    "mypy"
  )

  local installed_count=0
  local failed_packages=()

  # Install pipx first and ensure path
  python -m pip install --user pipx
  python -m pipx ensurepath

  # Install remaining packages
  for package in "${packages[@]}"; do
    # Skip pipx since we already installed it
    if [[ "$package" == "pipx" ]]; then
      ((installed_count++))
      continue
    fi

    log_info "Installing $package..."
    if python -m pip install --user "$package"; then
      ((installed_count++))
      log_success "Installed $package successfully"
    else
      failed_packages+=("$package")
      log_warning "Failed to install $package"
    fi
  done

  if [[ ${#failed_packages[@]} -eq 0 ]]; then
    log_success "All Python packages installed successfully"
  else
    log_warning "Some Python packages failed to install: ${failed_packages[*]}"
  fi

  # Show pip version
  log_success "Pip version: $(pip --version)"

  return 0
}

# Main function
main() {
  log_header "Setting up Node.js and Python Development Environment"

  # Validate system resources
  if ! validate_system_resources; then
    log_error "System resource validation failed"
    finish_logging
    exit 1
  fi

  # Install Node.js with NVM
  if ! install_nvm_and_node; then
    log_error "Node.js installation failed"
    finish_logging
    exit 1
  fi

  # Install Python with pyenv
  if ! install_python; then
    log_error "Python installation failed"
    finish_logging
    exit 1
  fi

  log_success "Node.js and Python environments are fully set up!"
  finish_logging
  return 0
}

# Execute main function
main
