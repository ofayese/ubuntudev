#!/usr/bin/env bash
# util-install.sh - Centralized installation and package management functions
set -euo pipefail

# Guard against multiple sourcing
if [[ "${UTIL_INSTALL_LOADED:-}" == "true" ]]; then
  return 0
fi
readonly UTIL_INSTALL_LOADED="true"

source "$(dirname "${BASH_SOURCE[0]}")/util-log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/util-env.sh"

ENV_TYPE="${ENV_TYPE:-$(detect_environment)}"

# --- Package Installation Functions ---

update_package_index() {
  log_info "Updating package index..."
  sudo apt-get update -y || { log_error "apt update failed."; return 1; }
}

# Install packages from apt with error handling (consolidated from util-packages.sh)
safe_apt_install() {
  init_logging
  local packages=("$@")
  local failed_packages=()
  
  update_package_index
  
  for pkg in "${packages[@]}"; do
    log_info "Installing $pkg..."
    if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -o DPkg::Lock::Timeout=30 "$pkg" 2>/dev/null; then
      log_success "Installed $pkg"
    else
      log_warning "Could not install $pkg - may not be available in this Ubuntu version"
      failed_packages+=("$pkg")
    fi
  done
  
  if [ ${#failed_packages[@]} -gt 0 ]; then
    log_warning "Failed to install: ${failed_packages[*]}"
    return 1
  fi
  
  finish_logging
  return 0
}

# Legacy function for compatibility - redirects to safe_apt_install
install_packages() {
  local pkgs=("$@")
  if [[ "$ENV_TYPE" == "WSL2" && -x "$(command -v brew)" ]]; then
    local failed=()
    for p in "${pkgs[@]}"; do
      log_info "Installing $p via brew..."
      brew install "$p" || failed+=("$p")
    done
    [[ ${#failed[@]} -eq 0 ]] || { log_error "Failed: ${failed[*]}"; return 1; }
  else
    safe_apt_install "${pkgs[@]}"
  fi
}

# Install snap package with fallback to apt (from util-packages.sh)
safe_install_snap() {
  init_logging
  local package="$1"
  local classic_flag="${2:-}"
  
  if ! command_exists snap; then
    log_info "snap not installed, attempting to install via apt..."
    safe_apt_install snapd
  fi
  
  if command_exists snap; then
    local cmd="sudo snap install $package"
    
    if [ "$classic_flag" = "--classic" ]; then
      cmd="$cmd --classic"
    fi
    
    log_info "Installing $package via snap..."
    if eval "$cmd"; then
      log_success "Successfully installed $package via snap"
      finish_logging
      return 0
    else
      log_warning "Failed to install $package via snap, trying apt..."
    fi
  fi
  
  # Fallback to apt
  log_info "Attempting to install $package via apt..."
  if safe_apt_install "$package"; then
    log_success "Successfully installed $package via apt"
    finish_logging
    return 0
  else
    log_error "Failed to install $package via both snap and apt"
    finish_logging
    return 1
  fi
}

# Legacy function for compatibility
install_snap() {
  local s="$1" c="${2:-}"
  safe_install_snap "$s" "$c"
}

# Install a .deb package file (consolidated from util-packages.sh)
safe_install_deb() {
  init_logging
  local url="$1"
  local pkg_name="${2:-$(basename "$url" .deb)}"
  local temp_file="/tmp/${pkg_name}_$(date +%s).deb"
  
  log_info "Downloading $pkg_name from $url..."
  if wget -q -O "$temp_file" "$url"; then
    log_success "Download complete"
    
    log_info "Installing $pkg_name..."
    if sudo apt install -y "$temp_file"; then
      log_success "Successfully installed $pkg_name"
      rm -f "$temp_file"
      finish_logging
      return 0
    else
      log_error "Failed to install $pkg_name"
      rm -f "$temp_file"
      finish_logging
      return 1
    fi
  else
    log_error "Failed to download $pkg_name"
    rm -f "$temp_file"
    finish_logging
    return 1
  fi
}

# Legacy function for compatibility
install_deb_package() {
  local url="$1" name="${2:-$(basename "$url" .deb)}"
  safe_install_deb "$url" "$name"
}

# Download and install a tool from GitHub releases (consolidated from util-packages.sh)
install_from_github() {
  init_logging
  local repo="$1"          # GitHub repository (e.g., "eza-community/eza")
  local pattern="$2"        # File pattern to download (e.g., "eza_.*_amd64.deb")
  local install_cmd="$3"    # Command to run for installation, use $1 as placeholder for the download path
  local binary_name="${4:-$(echo "$repo" | cut -d/ -f2)}"
  
  # Check if already installed
  if command_exists "$binary_name"; then
    local current_version
    current_version=$("$binary_name" --version 2>&1 | head -n1 | awk '{print $NF}' || echo "unknown")
    log_info "$binary_name is already installed (version: $current_version)"
    finish_logging
    return 0
  fi
  
  log_info "Installing $binary_name from GitHub ($repo)..."
  
  # Get latest release download URL
  local download_url
  download_url=$(curl -s "https://api.github.com/repos/$repo/releases/latest" | \
                 grep browser_download_url | grep -E "$pattern" | head -1 | cut -d '"' -f 4)
  
  if [ -z "$download_url" ]; then
    log_error "No download URL found for $binary_name with pattern $pattern"
    finish_logging
    return 1
  fi
  
  # Download the file
  local temp_file="/tmp/${binary_name}_download"
  log_info "Downloading from $download_url"
  
  if wget -q -O "$temp_file" "$download_url"; then
    log_success "Download complete"
    
    # Install using the provided command
    local cmd="${install_cmd//\$1/$temp_file}"
    log_info "Installing with command: $cmd"
    
    if eval "$cmd"; then
      log_success "$binary_name installed successfully"
      rm -f "$temp_file"
      finish_logging
      return 0
    else
      log_error "Failed to install $binary_name"
      rm -f "$temp_file"
      finish_logging
      return 1
    fi
  else
    log_error "Failed to download $binary_name"
    rm -f "$temp_file"
    finish_logging
    return 1
  fi
}

# Add an APT repository with proper error handling (from util-packages.sh)
safe_add_apt_repository() {
  init_logging
  local repo="$1"
  local desc="${2:-APT repository}"
  
  log_info "Adding $desc ($repo)..."
  
  # First make sure software-properties-common is installed
  safe_apt_install software-properties-common apt-transport-https
  
  if sudo add-apt-repository -y "$repo" 2>/dev/null; then
    log_success "Successfully added repository: $repo"
    sudo apt-get update -q
    finish_logging
    return 0
  else
    log_warning "Failed to add repository: $repo"
    log_info "Continuing without it..."
    finish_logging
    return 1
  fi
}

install_python_package() {
  local pkg="$1"
  log_info "Installing Python pkg: $pkg"
  command_exists pip3 || safe_apt_install python3-pip
  pip3 install -U "$pkg" || { log_error "pip install $pkg failed"; return 1; }
}

install_node_package() {
  local pkg="$1"
  log_info "Installing Node pkg: $pkg"
  npm install -g "$pkg" || { log_error "npm install $pkg failed"; return 1; }
}

# --- Package Checking Functions ---

# Check if package is installed (from util-packages.sh)
is_package_installed() {
  local package="$1"
  dpkg -l "$package" 2>/dev/null | grep -q "^ii"
}

# Check if pip package is installed (from util-packages.sh)
is_pip_installed() {
  local package="$1"
  pip list 2>/dev/null | grep -i "^$package " >/dev/null
}

# Check if npm package is installed (globally) (from util-packages.sh)
is_npm_global_installed() {
  local package="$1"
  npm list -g "$package" --depth=0 2>/dev/null | grep -q " $package@"
}

# --- Docker Utilities ---

# Check Docker availability (consolidated from multiple scripts)
check_docker() {
  if ! command_exists docker; then
    log_error "Docker CLI not found."
    return 1
  fi
  if ! docker info >/dev/null 2>&1; then
    log_error "Docker daemon not accessible. Is Docker Desktop running?"
    return 1
  fi
  log_success "Docker is installed and accessible."
  return 0
}

# Check if running in WSL with Docker Desktop integration
check_wsl_docker_integration() {
  if [[ "$(detect_environment)" == "$ENV_WSL" ]]; then
    log_info "Checking Docker context in WSL2..."
    local context
    context=$(docker context show)
    if [[ "$context" != "default" && "$context" != *"wsl"* ]]; then
      log_warning "Unexpected Docker context: $context"
      log_info "Use 'docker context use default' or ensure WSL integration is active in Docker Desktop."
      return 1
    else
      log_success "Docker context: $context (WSL-compatible)"
    fi
  fi
  return 0
}

# --- Component Installation with Progress ---

# Install a component script with proper error handling and progress
install_component() {
  local script="$1"
  local description="$2"
  local script_path
  
  # Resolve script path
  if [[ -f "$script" ]]; then
    script_path="$script"
  elif [[ -f "$SCRIPT_DIR/$script" ]]; then
    script_path="$SCRIPT_DIR/$script"
  else
    log_error "Component script not found: $script"
    return 1
  fi
  
  log_info "Starting component: $description"
  start_spinner "Installing $description"
  
  # Execute the component script
  if bash "$script_path" >/dev/null 2>&1; then
    stop_spinner "Installing $description"
    log_success "Component completed: $description"
    return 0
  else
    local exit_code=$?
    stop_spinner "Installing $description"
    log_error "Component failed: $description (exit code: $exit_code)"
    return $exit_code
  fi
}
