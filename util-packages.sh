#!/usr/bin/env bash
# util-packages.sh - Package installation and management utilities
set -euo pipefail

# --- Source utility scripts ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-log.sh"

# --- Download and installation utilities ---

# Install packages from apt with error handling
safe_apt_install() {
  init_logging
  local packages=("$@")
  local failed_packages=()
  
  for pkg in "${packages[@]}"; do
    log_info "Installing $pkg..."
    if sudo apt-get install -y "$pkg" 2>/dev/null; then
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

# Install a .deb package file
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

# Download and install a tool from GitHub releases
install_from_github() {
  init_logging
  local repo="$1"          # GitHub repository (e.g., "eza-community/eza")
  local pattern="$2"        # File pattern to download (e.g., "eza_.*_amd64.deb")
  local install_cmd="$3"    # Command to run for installation, use \$1 as placeholder for the download path
  local binary_name="${4:-$(echo "$repo" | cut -d/ -f2)}"
  
  # Check if already installed
  if command -v "$binary_name" >/dev/null 2>&1; then
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
    local cmd="${install_cmd/\$1/$temp_file}"
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

# Add an APT repository with proper error handling
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

# Install snap package with fallback to apt
safe_install_snap() {
  init_logging
  local package="$1"
  local classic_flag="${2:-}"
  
  if ! command -v snap >/dev/null 2>&1; then
    log_info "snap not installed, attempting to install via apt..."
    safe_apt_install snapd
  fi
  
  if command -v snap >/dev/null 2>&1; then
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

# Check if package is installed
is_package_installed() {
  local package="$1"
  dpkg -l "$package" 2>/dev/null | grep -q "^ii"
}

# Check if pip package is installed
is_pip_installed() {
  local package="$1"
  pip list 2>/dev/null | grep -i "^$package " >/dev/null
}

# Check if npm package is installed (globally)
is_npm_global_installed() {
  local package="$1"
  npm list -g "$package" --depth=0 2>/dev/null | grep -q " $package@"
}

# Main function for demonstration
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Package utilities loaded. Use by sourcing this file."
  exit 0
fi
