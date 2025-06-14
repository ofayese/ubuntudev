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

# Start logging
log_info "Node.js and Python setup started"

# --- Detect if running in WSL ---
detect_wsl
IS_WSL=$?
if [[ $IS_WSL -eq 1 ]]; then
  log_info "WSL environment detected"
fi

# --- System Resource Management ---
declare -A SYSTEM_REQUIREMENTS=(
  ["min_memory_gb"]="2"
  ["min_disk_gb"]="5"
  ["node_install_size_mb"]="250"
  ["python_install_size_mb"]="300"
  ["npm_packages_size_mb"]="200"
  ["python_packages_size_mb"]="150"
)

validate_system_resources() {
  log_info "Validating system resources for installation..."

  # Check memory
  local memory_gb
  memory_gb=$(free -g | awk '/^Mem:/ {print $2}')

  # Check disk space
  local disk_gb
  disk_gb=$(df "$HOME" | awk 'NR==2 {print int($4/1024/1024)}')

  # Check CPU cores
  local cpu_cores
  cpu_cores=$(nproc)

  # Calculate total space needed with 20% buffer
  local total_space_needed
  total_space_needed=$(((\
    ${SYSTEM_REQUIREMENTS[node_install_size_mb]} + \
    ${SYSTEM_REQUIREMENTS[python_install_size_mb]} + \
    ${SYSTEM_REQUIREMENTS[npm_packages_size_mb]} + \
    ${SYSTEM_REQUIREMENTS[python_packages_size_mb]}) * 120 / 100 / 1024 + 1))

  log_info "System resources: ${memory_gb}GB RAM, ${disk_gb}GB available disk space, ${cpu_cores} CPU cores"
  log_info "Estimated space required: ${total_space_needed}GB"

  # Memory validation
  if [[ $memory_gb -lt ${SYSTEM_REQUIREMENTS[min_memory_gb]} ]]; then
    log_warning "Low memory detected: ${memory_gb}GB (recommended: ${SYSTEM_REQUIREMENTS[min_memory_gb]}GB)"
    log_info "Consider closing unnecessary applications during installation"
    suggest_memory_optimization
  fi

  # Disk space validation
  if [[ $disk_gb -lt $total_space_needed ]]; then
    log_error "Insufficient disk space: ${disk_gb}GB (required: ${total_space_needed}GB)"
    suggest_disk_cleanup
    return 1
  fi

  # Set installation strategy based on available resources
  if [[ $memory_gb -ge 8 && $cpu_cores -ge 4 ]]; then
    export INSTALL_STRATEGY="aggressive"
    export PARALLEL_INSTALLS="true"
    log_info "Using aggressive installation strategy (high-resource system)"
  elif [[ $memory_gb -ge 4 && $cpu_cores -ge 2 ]]; then
    export INSTALL_STRATEGY="balanced"
    export PARALLEL_INSTALLS="false"
    log_info "Using balanced installation strategy (medium-resource system)"
  else
    export INSTALL_STRATEGY="conservative"
    export PARALLEL_INSTALLS="false"
    log_info "Using conservative installation strategy (low-resource system)"
  fi

  # Verify network connectivity
  if ! validate_network_connectivity; then
    log_warning "Network connectivity issues detected - installation may be slower or fail"
  fi

  return 0
}

validate_network_connectivity() {
  log_debug "Validating network connectivity..."

  # Test basic connectivity to essential sites
  local test_hosts=("nodejs.org" "pypi.org" "github.com")
  local failed_hosts=0

  for host in "${test_hosts[@]}"; do
    if ! ping -c 1 -W 5 "$host" >/dev/null 2>&1; then
      log_warning "Cannot reach $host"
      ((failed_hosts++))
    fi
  done

  if [[ $failed_hosts -eq ${#test_hosts[@]} ]]; then
    log_error "Cannot reach any required hosts - check your internet connection"
    return 1
  fi

  return 0
}

suggest_memory_optimization() {
  log_info "Memory optimization suggestions:"
  echo "1. Close unnecessary applications and browser tabs"
  echo "2. Clear system cache: sudo sync && sudo sysctl vm.drop_caches=1"
  echo "3. Check for memory leaks: ps aux --sort=-%mem | head -10"
  echo "4. Consider increasing swap space if needed"
}

suggest_disk_cleanup() {
  log_info "Disk cleanup suggestions:"
  echo "1. Clean package cache: sudo apt autoremove && sudo apt autoclean"
  echo "2. Remove old kernels: sudo apt autoremove --purge"
  echo "3. Clear temporary files: sudo rm -rf /tmp/* && rm -rf ~/.cache/*"
  echo "4. Check large files: du -ah $HOME | sort -rh | head -20"
  echo "5. Empty trash: rm -rf ~/.local/share/Trash/*"
}

monitor_resource_usage() {
  local operation_name="$1"
  local log_file="/tmp/resource_${operation_name}.log"

  log_debug "Starting resource monitoring for $operation_name"
  echo "# Resource monitoring for $operation_name - $(date)" >"$log_file"

  (
    while true; do
      local timestamp memory_usage disk_usage cpu_usage
      timestamp=$(date '+%Y-%m-%d %H:%M:%S')
      memory_usage=$(free | awk '/^Mem:/ {printf "%.1f", $3/$2 * 100}')
      disk_usage=$(df "$HOME" | awk 'NR==2 {print $5}' | tr -d '%')
      cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | tr -d '%us,')

      echo "$timestamp,$memory_usage,$disk_usage,$cpu_usage" >>"$log_file"

      # Alert on extremely high resource usage
      if (($(echo "$memory_usage > 95" | bc -l 2>/dev/null || echo 0))); then
        log_warning "Critical memory usage detected: ${memory_usage}%"
      fi

      sleep 30
    done
  ) &

  echo $! # Return PID of background process
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

# Enhanced npm package installation with validation and priorities
install_npm_packages() {
  log_info "Installing global npm packages..."

  # First upgrade npm itself
  log_info "Upgrading npm to latest version..."
  if ! npm install -g npm@latest; then
    log_warning "Failed to upgrade npm, continuing with current version"
  fi

  # Define packages with priorities
  declare -A NPM_PACKAGES=(
    ["yarn"]="essential"
    ["pnpm"]="essential"
    ["typescript"]="essential"
    ["ts-node"]="standard"
    ["eslint"]="standard"
    ["prettier"]="standard"
    ["nodemon"]="standard"
    ["nx"]="optional"
    ["@angular/cli"]="optional"
    ["npm-check-updates"]="standard"
    ["serve"]="standard"
  )

  local installed_count=0
  local failed_packages=()
  local manifest_file
  manifest_file=$(mktemp)

  echo "# NPM Package Installation Manifest - $(date)" >"$manifest_file"

  # Validate npm environment
  if ! validate_npm_environment; then
    log_error "npm environment validation failed"
    return 1
  fi

  # Install essential packages first
  log_info "Installing essential npm packages..."
  for package in "${!NPM_PACKAGES[@]}"; do
    if [[ "${NPM_PACKAGES[$package]}" == "essential" ]]; then
      install_npm_package_with_validation "$package" "$manifest_file"
    fi
  done

  # Install standard packages
  log_info "Installing standard npm packages..."
  for package in "${!NPM_PACKAGES[@]}"; do
    if [[ "${NPM_PACKAGES[$package]}" == "standard" ]]; then
      install_npm_package_with_validation "$package" "$manifest_file"
    fi
  done

  # Install optional packages if resources allow
  if [[ "${INSTALL_STRATEGY:-balanced}" == "aggressive" ]]; then
    log_info "Installing optional npm packages..."
    for package in "${!NPM_PACKAGES[@]}"; do
      if [[ "${NPM_PACKAGES[$package]}" == "optional" ]]; then
        install_npm_package_with_validation "$package" "$manifest_file"
      fi
    done
  fi

  # Generate installation report
  generate_npm_installation_report "$manifest_file"
  rm -f "$manifest_file"

  log_info "Node.js installation results:"
  log_info "Installed Node.js versions:"
  nvm ls
  log_success "Current Node.js version: $(node -v)"
  log_success "Current npm version: $(npm -v)"

  return 0
}

validate_npm_environment() {
  log_debug "Validating npm environment..."

  # Check npm availability
  if ! command -v npm >/dev/null 2>&1; then
    log_error "npm command not found"
    return 1
  fi

  # Check npm version
  local npm_version
  npm_version=$(npm --version 2>/dev/null)
  if [[ -z "$npm_version" ]]; then
    log_error "Could not determine npm version"
    return 1
  fi

  log_debug "npm version: $npm_version"

  # Check global directory permissions
  local global_dir
  global_dir=$(npm config get prefix 2>/dev/null)

  if [[ -n "$global_dir" ]] && [[ -d "$global_dir" ]]; then
    if [[ ! -w "$global_dir" ]]; then
      log_warning "No write permission to npm global directory: $global_dir"
      log_info "You may need to fix permissions or use a user-level npm configuration"
    fi
  else
    log_warning "npm prefix not configured properly"
  fi

  return 0
}

install_npm_package_with_validation() {
  local package="$1"
  local manifest_file="$2"

  log_info "Installing npm package: $package"

  # Check if already installed
  if npm list -g "$package" >/dev/null 2>&1; then
    local current_version
    current_version=$(npm list -g "$package" --depth=0 2>/dev/null | grep "$package" | sed 's/.*@//')

    log_info "$package already installed (version: $current_version)"
    echo "$package@$current_version - ALREADY_INSTALLED" >>"$manifest_file"
    return 0
  fi

  # Install with retry logic
  local attempt=1
  local max_attempts=3
  local temp_log
  temp_log=$(mktemp)

  while [[ $attempt -le $max_attempts ]]; do
    log_debug "Installing $package (attempt $attempt/$max_attempts)"

    if npm install -g "$package" >"$temp_log" 2>&1; then
      # Verify installation
      if npm list -g "$package" >/dev/null 2>&1; then
        local installed_version
        installed_version=$(npm list -g "$package" --depth=0 2>/dev/null | grep "$package" | sed 's/.*@//')

        log_success "Installed $package successfully (version: $installed_version)"
        echo "$package@$installed_version - SUCCESS" >>"$manifest_file"
        rm -f "$temp_log"
        return 0
      else
        log_warning "Package installed but verification failed: $package"
        echo "$package - VERIFICATION_FAILED" >>"$manifest_file"
        rm -f "$temp_log"
        return 1
      fi
    else
      if [[ $attempt -eq $max_attempts ]]; then
        log_warning "Failed to install npm package after $max_attempts attempts: $package"
        echo "$package - INSTALL_FAILED" >>"$manifest_file"

        # Extract error for debugging
        if [[ -s "$temp_log" ]]; then
          log_debug "Installation error details:"
          tail -5 "$temp_log" | log_debug
        fi

        rm -f "$temp_log"
        return 1
      else
        log_debug "Attempt $attempt failed, retrying..."
        sleep $((attempt * 2))
        ((attempt++))
      fi
    fi
  done
}

generate_npm_installation_report() {
  local manifest_file="$1"

  if [[ ! -f "$manifest_file" ]]; then
    return
  fi

  local success_count
  success_count=$(grep "SUCCESS" "$manifest_file" | wc -l)

  local already_count
  already_count=$(grep "ALREADY_INSTALLED" "$manifest_file" | wc -l)

  local failed_count
  failed_count=$(grep -E "INSTALL_FAILED|VERIFICATION_FAILED" "$manifest_file" | wc -l)

  log_info "npm Package Installation Summary:"
  log_info "- Successfully installed: $success_count packages"
  log_info "- Already installed: $already_count packages"

  if [[ $failed_count -gt 0 ]]; then
    log_warning "- Failed installations: $failed_count packages"
    grep -E "INSTALL_FAILED|VERIFICATION_FAILED" "$manifest_file" | cut -d' ' -f1 | log_warning
  fi
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

# Function to install Python packages with enhanced validation
install_python_packages() {
  log_info "Installing Python packages..."

  # Upgrade pip first
  log_info "Upgrading pip..."
  python -m pip install --upgrade pip setuptools wheel

  # Define packages with priorities
  declare -A PYTHON_PACKAGES=(
    ["pipx"]="essential"
    ["pipenv"]="essential"
    ["virtualenv"]="essential"
    ["poetry"]="standard"
    ["black"]="standard"
    ["isort"]="standard"
    ["pytest"]="standard"
    ["mypy"]="standard"
    ["ruff"]="standard"
    ["pre-commit"]="standard"
    ["jupyter"]="optional"
    ["ipython"]="optional"
  )

  local installed_count=0
  local failed_packages=()
  local manifest_file
  manifest_file=$(mktemp)

  echo "# Python Package Installation Manifest - $(date)" >"$manifest_file"

  # Install essential packages first
  log_info "Installing essential Python packages..."
  for package in "${!PYTHON_PACKAGES[@]}"; do
    if [[ "${PYTHON_PACKAGES[$package]}" == "essential" ]]; then
      install_python_package_with_validation "$package" "$manifest_file"
    fi
  done

  # Ensure pipx path is configured
  python -m pipx ensurepath >/dev/null 2>&1 || true

  # Install standard packages
  log_info "Installing standard Python packages..."
  for package in "${!PYTHON_PACKAGES[@]}"; do
    if [[ "${PYTHON_PACKAGES[$package]}" == "standard" ]]; then
      install_python_package_with_validation "$package" "$manifest_file"
    fi
  done

  # Install optional packages if resources allow
  if [[ "${INSTALL_STRATEGY:-balanced}" == "aggressive" ]]; then
    log_info "Installing optional Python packages..."
    for package in "${!PYTHON_PACKAGES[@]}"; do
      if [[ "${PYTHON_PACKAGES[$package]}" == "optional" ]]; then
        install_python_package_with_validation "$package" "$manifest_file"
      fi
    done
  fi

  # Generate installation report
  generate_python_installation_report "$manifest_file"
  rm -f "$manifest_file"

  # Show pip version
  log_success "Pip version: $(pip --version)"

  return 0
}

install_python_package_with_validation() {
  local package="$1"
  local manifest_file="$2"

  log_info "Installing Python package: $package"

  # Check if already installed
  if python -c "import $package" >/dev/null 2>&1; then
    local version_cmd="import $package; print(getattr($package, '__version__', 'unknown'))"
    local current_version
    current_version=$(python -c "$version_cmd" 2>/dev/null || echo "unknown")

    log_info "$package already installed (version: $current_version)"
    echo "$package@$current_version - ALREADY_INSTALLED" >>"$manifest_file"
    return 0
  fi

  # Install with enhanced error handling
  local temp_log
  temp_log=$(mktemp)

  if python -m pip install --user "$package" >"$temp_log" 2>&1; then
    # Verify installation
    if python -c "import $package" >/dev/null 2>&1; then
      local version_cmd="import $package; print(getattr($package, '__version__', 'unknown'))"
      local installed_version
      installed_version=$(python -c "$version_cmd" 2>/dev/null || echo "unknown")

      log_success "Installed $package successfully (version: $installed_version)"
      echo "$package@$installed_version - SUCCESS" >>"$manifest_file"
      rm -f "$temp_log"
      return 0
    else
      log_warning "Package installed but import failed: $package"
      echo "$package - IMPORT_FAILED" >>"$manifest_file"
      cat "$temp_log" | log_debug
      rm -f "$temp_log"
      return 1
    fi
  else
    log_warning "Failed to install Python package: $package"
    echo "$package - INSTALL_FAILED" >>"$manifest_file"

    # Extract error for debugging
    if [[ -s "$temp_log" ]]; then
      log_debug "Installation error details:"
      tail -5 "$temp_log" | log_debug
    fi

    rm -f "$temp_log"
    return 1
  fi
}

generate_python_installation_report() {
  local manifest_file="$1"

  if [[ ! -f "$manifest_file" ]]; then
    return
  fi

  local success_count
  success_count=$(grep "SUCCESS" "$manifest_file" | wc -l)

  local already_count
  already_count=$(grep "ALREADY_INSTALLED" "$manifest_file" | wc -l)

  local failed_count
  failed_count=$(grep -E "INSTALL_FAILED|IMPORT_FAILED" "$manifest_file" | wc -l)

  log_info "Python Package Installation Summary:"
  log_info "- Successfully installed: $success_count packages"
  log_info "- Already installed: $already_count packages"

  if [[ $failed_count -gt 0 ]]; then
    log_warning "- Failed installations: $failed_count packages"
    grep -E "INSTALL_FAILED|IMPORT_FAILED" "$manifest_file" | cut -d' ' -f1 | log_warning
  fi
}

# --- Error Recovery & Graceful Termination ---
cleanup_resources() {
  log_info "Cleaning up resources..."

  # Kill any resource monitors
  if [[ -n "${RESOURCE_MONITOR_PID:-}" ]]; then
    kill $RESOURCE_MONITOR_PID 2>/dev/null || true
  fi

  # Remove temporary files
  rm -f /tmp/resource_*.log 2>/dev/null || true

  log_info "Cleanup complete"
}

handle_exit() {
  local exit_code=$?
  log_info "Script exiting with code: $exit_code"

  # Only run cleanup if abnormal termination
  if [[ $exit_code -ne 0 ]]; then
    log_info "Abnormal termination detected, performing cleanup"
    cleanup_resources
  fi

  # Final status
  if [[ $exit_code -eq 0 ]]; then
    log_success "Node.js and Python setup completed successfully"
  else
    log_error "Setup failed with exit code $exit_code"
    log_info "You may need to run this script again after resolving any issues"
  fi

  exit $exit_code
}

# Main function
main() {
  log_header "Setting up Node.js and Python Development Environment"

  # Set up trap for graceful termination
  trap handle_exit EXIT INT TERM

  # Start overall resource monitoring
  RESOURCE_MONITOR_PID=$(monitor_resource_usage "setup_node_python")

  # Validate system resources
  if ! validate_system_resources; then
    log_error "System resource validation failed"
    return 1
  fi

  # Execute installation based on strategy
  case "${INSTALL_STRATEGY:-balanced}" in
  "aggressive")
    execute_parallel_installation
    ;;
  "balanced" | "conservative")
    execute_sequential_installation
    ;;
  *)
    execute_sequential_installation
    ;;
  esac

  # Generate installation report
  generate_installation_report

  log_success "Node.js and Python environments are fully set up!"

  # Display verification information
  verify_installations

  return 0
}

execute_parallel_installation() {
  log_info "Executing parallel installation strategy..."

  # Start Node.js and Python installations in parallel
  {
    log_info "Starting Node.js installation (background)..."
    install_nvm_and_node
    log_success "Node.js installation completed"
  } &
  local node_pid=$!

  # Short delay to avoid resource contention at startup
  sleep 5

  {
    log_info "Starting Python installation (background)..."
    install_python
    log_success "Python installation completed"
  } &
  local python_pid=$!

  # Wait for both processes to complete
  log_info "Waiting for installations to complete..."
  wait $node_pid || NODE_FAILED=true
  wait $python_pid || PYTHON_FAILED=true

  # Check results
  if [[ "${NODE_FAILED:-}" == "true" ]]; then
    log_error "Node.js installation failed"
    return 1
  fi

  if [[ "${PYTHON_FAILED:-}" == "true" ]]; then
    log_error "Python installation failed"
    return 1
  fi

  return 0
}

execute_sequential_installation() {
  log_info "Executing sequential installation strategy..."

  # Install Node.js with NVM
  if ! install_nvm_and_node; then
    log_error "Node.js installation failed"
    return 1
  fi

  # Install Python with pyenv
  if ! install_python; then
    log_error "Python installation failed"
    return 1
  fi

  return 0
}

generate_installation_report() {
  log_info "Installation Report"
  echo "=================="

  # Node.js report
  echo "Node.js Environment:"
  if command -v node >/dev/null 2>&1; then
    echo "- Node.js: $(node -v)"
    echo "- npm: $(npm -v)"
    echo "- Global packages: $(npm list -g --depth=0 | grep -v 'npm ERR!' | grep -v "^/" | tail -n +2)"
  else
    echo "- Node.js: Not installed or not in PATH"
  fi

  echo ""

  # Python report
  echo "Python Environment:"
  if command -v python >/dev/null 2>&1; then
    echo "- Python: $(python --version 2>&1)"
    echo "- pip: $(pip --version 2>&1 | cut -d' ' -f2)"
    echo "- Global packages: $(pip list --user | tail -n +3)"
  else
    echo "- Python: Not installed or not in PATH"
  fi

  echo ""

  # Resource usage summary
  if [[ -f "/tmp/resource_setup_node_python.log" ]]; then
    echo "Resource Usage:"
    local max_memory max_disk max_cpu
    max_memory=$(awk -F, 'NR>1 {if ($2 > max) max=$2} END {print max}' "/tmp/resource_setup_node_python.log")
    max_disk=$(awk -F, 'NR>1 {if ($3 > max) max=$3} END {print max}' "/tmp/resource_setup_node_python.log")
    max_cpu=$(awk -F, 'NR>1 {if ($4 > max) max=$4} END {print max}' "/tmp/resource_setup_node_python.log")

    echo "- Peak Memory Usage: ${max_memory}%"
    echo "- Peak Disk Usage: ${max_disk}%"
    echo "- Peak CPU Usage: ${max_cpu}%"
  fi
}

verify_installations() {
  log_info "Verifying installations..."

  # Check Node.js
  if command -v node >/dev/null 2>&1; then
    log_success "Node.js verification: $(node -v)"
  else
    log_error "Node.js verification failed: command not found"
  fi

  # Check npm
  if command -v npm >/dev/null 2>&1; then
    log_success "npm verification: $(npm -v)"
  else
    log_error "npm verification failed: command not found"
  fi

  # Check Python
  if command -v python >/dev/null 2>&1; then
    log_success "Python verification: $(python --version 2>&1)"
  else
    log_error "Python verification failed: command not found"
  fi

  # Check pip
  if command -v pip >/dev/null 2>&1; then
    log_success "pip verification: $(pip --version)"
  else
    log_error "pip verification failed: command not found"
  fi

  # Suggest shell restart if needed
  log_info "You may need to restart your shell or run 'source ~/.bashrc' to use newly installed tools"
}

# Execute main function
main
