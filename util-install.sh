#!/usr/bin/env bash
# Utility: util-install.sh
# Description: Centralized installation and package management functions
# Last Updated: 2025-06-13
# Version: 1.0.0

set -euo pipefail

# Load guard to prevent multiple sourcing
if [[ -n "${UTIL_INSTALL_SH_LOADED:-}" ]]; then
  return 0
fi
readonly UTIL_INSTALL_SH_LOADED=1

# ------------------------------------------------------------------------------
# Global Variable Initialization (Safe conditional pattern)
# ------------------------------------------------------------------------------

# Script directory (only declare once globally)
if [[ -z "${SCRIPT_DIR:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  readonly SCRIPT_DIR
fi

# Version & timestamp (only declare once globally)
if [[ -z "${VERSION:-}" ]]; then
  VERSION="1.0.0"
  readonly VERSION
fi

if [[ -z "${LAST_UPDATED:-}" ]]; then
  LAST_UPDATED="2025-06-13"
  readonly LAST_UPDATED
fi

# OS detection (only declare once globally)
if [[ -z "${OS_TYPE:-}" ]]; then
  OS_TYPE="$(uname -s)"
  readonly OS_TYPE
fi

# Dry run support (only declare once globally)
if [[ -z "${DRY_RUN:-}" ]]; then
  DRY_RUN="false"
  readonly DRY_RUN
fi

# ------------------------------------------------------------------------------
# Dependencies: Load required utilities
# ------------------------------------------------------------------------------

if [[ -z "${UTIL_LOG_SH_LOADED:-}" && -f "${SCRIPT_DIR}/util-log.sh" ]]; then
  source "${SCRIPT_DIR}/util-log.sh" || {
    echo "[ERROR] Failed to source util-log.sh" >&2
    exit 1
  }
fi

if [[ -z "${UTIL_ENV_SH_LOADED:-}" && -f "${SCRIPT_DIR}/util-env.sh" ]]; then
  source "${SCRIPT_DIR}/util-env.sh" || {
    echo "[ERROR] Failed to source util-env.sh" >&2
    exit 1
  }
fi

# ------------------------------------------------------------------------------
# Module Functions
# ------------------------------------------------------------------------------

# --- Package Installation Functions ---

update_package_index() {
  log_info "Updating package index..."
  sudo apt-get update -y || {
    log_error "apt update failed."
    return 1
  }
}

# Install packages from apt with error handling and timeout protection
safe_apt_install() {
  init_logging
  local packages
  packages=("$@")
  local failed_packages
  failed_packages=()
  local timeout
  timeout=120 # 2 minutes per package

  update_package_index

  for pkg in "${packages[@]}"; do
    log_substep "Installing $pkg" "IN PROGRESS"

    if run_with_timeout "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -o DPkg::Lock::Timeout=30 $pkg" "Installing $pkg" "$timeout"; then
      log_substep "Installing $pkg" "SUCCESS"
    else
      log_substep "Installing $pkg" "WARNING" "May not be available in this Ubuntu version"
      failed_packages+=("$pkg")
    fi
  done

  if [ ${#failed_packages[@]} -gt 0 ]; then
    log_substep "Some packages failed to install" "WARNING" "${failed_packages[*]}"
    finish_logging
    return 1
  fi

  finish_logging
  return 0
}

# Legacy function for compatibility - redirects to safe_apt_install
install_packages() {
  local pkgs
  pkgs=("$@")
  if [[ "$ENV_TYPE" == "WSL2" && -x "$(command -v brew)" ]]; then
    local failed
    failed=()
    for p in "${pkgs[@]}"; do
      log_info "Installing $p via brew..."
      brew install "$p" || failed+=("$p")
    done
    [[ ${#failed[@]} -eq 0 ]] || {
      log_error "Failed: ${failed[*]}"
      return 1
    }
  else
    safe_apt_install "${pkgs[@]}"
  fi
}

# Install snap package with fallback to apt and timeout protection
safe_install_snap() {
  init_logging
  local package
  package="$1"
  local classic_flag
  classic_flag="${2:-}"
  local snap_timeout
  snap_timeout=180 # 3 minutes for snap operations

  log_substep "Preparing to install $package" "IN PROGRESS"

  if ! command_exists snap; then
    log_substep "snap not available" "WARNING" "Installing snapd via apt"
    safe_apt_install snapd
  fi

  if command_exists snap; then
    local cmd="sudo snap install $package"

    if [ "$classic_flag" = "--classic" ]; then
      cmd="$cmd --classic"
      log_substep "Installing $package via snap (classic mode)" "IN PROGRESS"
    else
      log_substep "Installing $package via snap" "IN PROGRESS"
    fi

    if run_with_timeout "$cmd" "Installing via snap: $package" "$snap_timeout"; then
      log_substep "Installing $package via snap" "SUCCESS"
      finish_logging
      return 0
    else
      log_substep "snap installation failed" "WARNING" "Trying apt as fallback"
    fi
  fi

  # Fallback to apt
  log_substep "Attempting installation via apt" "IN PROGRESS" "Package: $package"
  if safe_apt_install "$package"; then
    log_substep "Installing $package via apt" "SUCCESS"
    finish_logging
    return 0
  else
    log_substep "Installing $package" "FAILED" "Both snap and apt methods failed"
    log_error "Failed to install $package via both snap and apt"
    finish_logging
    return 1
  fi
}

# Legacy function for compatibility
install_snap() {
  local s
  s="$1"
  local c
  c="${2:-}"
  safe_install_snap "$s" "$c"
}

# Install a .deb package file (consolidated from util-packages.sh)
safe_install_deb() {
  init_logging
  local url
  url="$1"
  local pkg_name
  pkg_name="${2:-$(basename "$url" .deb)}"
  local temp_file
  temp_file="/tmp/${pkg_name}_$(date +%s).deb"

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
  local url
  url="$1"
  local name
  name="${2:-$(basename "$url" .deb)}"
  safe_install_deb "$url" "$name"
}

# Download and install a tool from GitHub releases (consolidated from util-packages.sh)
install_from_github() {
  init_logging
  local repo
  repo="$1" # GitHub repository (e.g., "eza-community/eza")
  local pattern
  pattern="$2" # File pattern to download (e.g., "eza_.*_amd64.deb")
  local install_cmd
  install_cmd="$3" # Command to run for installation, use $1 as placeholder for the download path
  local binary_name
  binary_name="${4:-$(echo "$repo" | cut -d/ -f2)}"

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
  download_url=$(curl -s "https://api.github.com/repos/$repo/releases/latest" |
    grep browser_download_url | grep -E "$pattern" | head -1 | cut -d '"' -f 4)

  if [ -z "$download_url" ]; then
    log_error "No download URL found for $binary_name with pattern $pattern"
    finish_logging
    return 1
  fi

  # Download the file
  local temp_file
  temp_file="/tmp/${binary_name}_download"
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
  local repo
  repo="$1"
  local desc
  desc="${2:-APT repository}"

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
  pip3 install -U "$pkg" || {
    log_error "pip install $pkg failed"
    return 1
  }
}

install_node_package() {
  local pkg="$1"
  log_info "Installing Node pkg: $pkg"
  npm install -g "$pkg" || {
    log_error "npm install $pkg failed"
    return 1
  }
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

# Maximum timeout for component scripts (in seconds)
readonly COMPONENT_TIMEOUT=600 # 10 minutes

# Install a component script with proper error handling and enhanced progress reporting
install_component() {
  local script="$1"
  local description="$2"
  local script_dir="${3:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
  local script_path
  local current_component="${4:-0}"
  local total_components="${5:-0}"

  # Use global readonly COMPONENT_TIMEOUT (default: 10 minutes/600 seconds)

  # Resolve script path
  if [[ -f "$script" ]]; then
    script_path="$script"
  elif [[ -f "$script_dir/$script" ]]; then
    script_path="$script_dir/$script"
  else
    log_error "Component script not found: $script (looked in: $script_dir)"
    return 1
  fi # Use enhanced timestamped progress reporting
  if [[ "$current_component" -gt 0 && "$total_components" -gt 0 ]]; then
    log_progress_start "$description" "$current_component" "$total_components"
  else
    log_progress_start "$description"
  fi

  # Execute the component script with visible output and timeout
  local temp_output
  temp_output=$(mktemp)
  local start_time
  start_time=$(date +%s)
  local exit_code=0
  local timeout_happened=false

  # Run the script with timeout to prevent hanging and show output in real-time
  # Use tee with process substitution to avoid pipe issues
  if timeout --foreground "$COMPONENT_TIMEOUT" bash "$script_path" 2>&1 | tee "$temp_output"; then
    exit_code=0
  else
    exit_code=$?
    # Check if it was a timeout (124 is the exit code for timeout)
    if [[ $exit_code -eq 124 ]]; then
      timeout_happened=true
      log_progress_update "$description" "Operation timed out after ${COMPONENT_TIMEOUT}s"
    fi
  fi

  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))

  # Format duration for display
  local duration_str=""
  if [[ $duration -ge 3600 ]]; then
    duration_str="$((duration / 3600))h $(((duration % 3600) / 60))m $((duration % 60))s"
  elif [[ $duration -ge 60 ]]; then
    duration_str="$((duration / 60))m $((duration % 60))s"
  else
    duration_str="${duration}s"
  fi

  # Report completion with status
  if [[ "$exit_code" -eq 0 ]]; then
    # Report successful completion
    if [[ "$current_component" -gt 0 && "$total_components" -gt 0 ]]; then
      log_progress_complete "$description" "SUCCESS" "$current_component" "$total_components"
    else
      log_progress_complete "$description" "SUCCESS"
    fi
    log_component_result "$description" "SUCCESS" "Completed in ${duration_str}"
  else
    # Report failure with details
    local status="FAILED"
    local details="Exit code: ${exit_code}, Duration: ${duration_str}"

    if [[ "$timeout_happened" == "true" ]]; then
      details="TIMED OUT after ${COMPONENT_TIMEOUT}s. ${details}"
    fi

    if [[ "$current_component" -gt 0 && "$total_components" -gt 0 ]]; then
      log_progress_complete "$description" "FAILED" "$current_component" "$total_components"
    else
      log_progress_complete "$description" "FAILED"
    fi
    log_component_result "$description" "FAILED" "$details"

    # Format duration for display
    local duration_str=""
    if [[ $duration -ge 60 ]]; then
      duration_str="$((duration / 60))m $((duration % 60))s"
    else
      duration_str="${duration}s"
    fi

    # Check if it was a timeout
    if [[ $exit_code -eq 124 ]]; then
      log_error "Component timed out after ${COMPONENT_TIMEOUT}s: $description"
      log_substep "Installation timed out" "FAILED" "Component: $description"
    else
      log_error "Component failed: $description (exit code: $exit_code, duration: $duration_str)"
      log_substep "Installation failed" "FAILED" "Exit code: $exit_code"
    fi

    # Log the last few lines of output for debugging
    if [[ -f "$temp_output" && -s "$temp_output" ]]; then
      log_error "Last output from failed component:"
      tail -n 10 "$temp_output" | while IFS= read -r line; do
        log_error "  $line"
      done
    fi

    if [[ "$current_component" -gt 0 && "$total_components" -gt 0 ]]; then
      log_step_complete "$description" "$current_component" "$total_components" "FAILED"
    fi

    rm -f "$temp_output"
    return $exit_code
  fi
}

# Safer update_package_index with timeout and better error handling
update_package_index() {
  log_substep "Updating package index" "IN PROGRESS"

  local start_time=$(date +%s)
  if timeout 120 sudo apt-get update -y; then
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log_substep "Package index updated" "SUCCESS" "Completed in ${duration}s"
    return 0
  else
    local exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
      log_substep "Package index update" "FAILED" "Timed out after 120s"
    else
      log_substep "Package index update" "FAILED" "Exit code: $exit_code"
    fi
    return 1
  fi
}
