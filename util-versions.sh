#!/usr/bin/env bash
# Utility: util-versions.sh
# Description: Language version managers utility functions
# Last Updated: 2025-06-13
# Version: 1.0.0

set -euo pipefail

# Load guard to prevent multiple sourcing
if [[ -n "${UTIL_VERSIONS_SH_LOADED:-}" ]]; then
  return 0
fi
readonly UTIL_VERSIONS_SH_LOADED=1

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

# --- Security enhancements and input validation ---

# List of trusted domains for script downloads
readonly TRUSTED_DOMAINS=(
  "raw.githubusercontent.com"
  "get.sdkman.io"
  "sh.rustup.rs"
  "get-ghcup.haskell.org"
  "api.github.com"
  "pyenv.run"
  "starship.rs"
  "nodejs.org"
)

# Secure download and execution function
validate_and_download() {
  local url="$1"
  local description="${2:-script}"
  local exec_mode="${3:-execute}" # execute or download
  local output_file="${4:-}"

  # Extract and validate domain
  local domain
  domain=$(echo "$url" | sed -n 's|^https://\([^/]*\).*|\1|p')

  local is_trusted=false
  for trusted in "${TRUSTED_DOMAINS[@]}"; do
    if [[ "$domain" == "$trusted" ]]; then
      is_trusted=true
      break
    fi
  done

  if [[ "$is_trusted" != "true" ]]; then
    log_error "Untrusted domain: $domain"
    return 1
  fi

  log_info "Securely downloading from verified source: $domain"

  # Create secure temporary file if executing
  local temp_script
  if [[ "$exec_mode" == "execute" ]]; then
    temp_script=$(mktemp --suffix=.sh)
    chmod 700 "$temp_script"
    output_file="$temp_script"
  elif [[ -z "$output_file" ]]; then
    output_file=$(mktemp)
  fi

  # Download with timeout and validation
  if curl -fsSL --connect-timeout 10 --max-time 60 "$url" -o "$output_file"; then
    log_success "Download completed: $description"

    if [[ "$exec_mode" == "execute" ]]; then
      # Basic script validation
      if grep -q "rm -rf /" "$temp_script" || grep -q "chmod 777" "$temp_script"; then
        log_error "Dangerous script content detected"
        rm -f "$temp_script"
        return 1
      fi

      # Execute in controlled environment
      bash "$temp_script"
      local exit_code=$?
      rm -f "$temp_script"
      return $exit_code
    else
      # Return the path to the downloaded file
      echo "$output_file"
      return 0
    fi
  else
    log_error "Download failed: $description"
    [[ -f "$output_file" ]] && rm -f "$output_file"
    return 1
  fi
}

# Parameter validation functions
validate_boolean_param() {
  local param="$1"
  local param_name="$2"

  case "$param" in
  "true" | "false" | "1" | "0" | "yes" | "no" | "y" | "n" | "Y" | "N" | "")
    return 0
    ;;
  *)
    log_error "Invalid boolean parameter for $param_name: $param"
    log_info "Valid values: true, false, 1, 0, yes, no, or empty"
    return 1
    ;;
  esac
}

normalize_boolean() {
  local value="$1"

  case "$value" in
  "true" | "1" | "yes" | "y" | "Y")
    echo "true"
    ;;
  "false" | "0" | "no" | "n" | "N" | "")
    echo "false"
    ;;
  *)
    echo "false"
    ;;
  esac
}

# Version string validation
validate_version_string() {
  local version="$1"
  local manager="$2"

  # Sanitize version string - remove dangerous characters
  version=$(echo "$version" | tr -d ';|&`$()')

  case "$manager" in
  "node")
    # Valid patterns: 18.17.0, lts, latest
    if [[ "$version" =~ ^(latest|lts|[0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
      echo "$version"
      return 0
    fi
    ;;
  "python")
    # Valid patterns: 3.11.5, 3.11, 3
    if [[ "$version" =~ ^[0-9]+(\.[0-9]+)?(\.[0-9]+)?$ ]]; then
      echo "$version"
      return 0
    fi
    ;;
  "java")
    # Valid patterns: 17.0.7-tem, 11.0.19-amzn
    if [[ "$version" =~ ^[0-9]+(\.[0-9]+)?(\.[0-9]+)?(-[a-zA-Z0-9]+)?$ ]]; then
      echo "$version"
      return 0
    fi
    ;;
  *)
    # Generic version validation
    if [[ "$version" =~ ^[0-9]+(\.[0-9]+)?(\.[0-9]+)?(-[a-zA-Z0-9._]+)?$ ]]; then
      echo "$version"
      return 0
    fi
    ;;
  esac

  log_error "Invalid version format for $manager: $version"
  return 1
}

# Installation state management
declare -A INSTALLATION_BACKUPS=()

create_installation_backup() {
  local component="$1"
  local backup_id="backup_$(date +%s)"

  # Create backup directory
  local backup_dir="/tmp/${component}_${backup_id}"
  mkdir -p "$backup_dir"

  # Backup relevant files
  for profile in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [[ -f "$profile" ]]; then
      cp "$profile" "$backup_dir/$(basename "$profile")"
    fi
  done

  # Backup component directory if it exists
  case "$component" in
  "nvm")
    [[ -d "$HOME/.nvm" ]] && cp -r "$HOME/.nvm" "$backup_dir/nvm_backup" 2>/dev/null
    ;;
  "pyenv")
    [[ -d "$HOME/.pyenv" ]] && cp -r "$HOME/.pyenv" "$backup_dir/pyenv_backup" 2>/dev/null
    ;;
  "sdkman")
    [[ -d "$HOME/.sdkman" ]] && cp -r "$HOME/.sdkman" "$backup_dir/sdkman_backup" 2>/dev/null
    ;;
  "rust")
    [[ -d "$HOME/.cargo" ]] && cp -r "$HOME/.cargo" "$backup_dir/cargo_backup" 2>/dev/null
    [[ -d "$HOME/.rustup" ]] && cp -r "$HOME/.rustup" "$backup_dir/rustup_backup" 2>/dev/null
    ;;
  esac

  INSTALLATION_BACKUPS["$component"]="$backup_dir"
  log_debug "Created backup for $component: $backup_dir"
}

rollback_installation() {
  local component="$1"
  local backup_dir="${INSTALLATION_BACKUPS[$component]}"

  if [[ -z "$backup_dir" ]] || [[ ! -d "$backup_dir" ]]; then
    log_warning "No backup found for $component"
    return 1
  fi

  log_info "Rolling back $component installation..."

  # Restore shell profiles
  for profile in bashrc zshrc profile; do
    local backup_file="$backup_dir/$profile"
    local target_file="$HOME/.$profile"

    if [[ -f "$backup_file" ]]; then
      cp "$backup_file" "$target_file"
    fi
  done

  # Restore component directory
  case "$component" in
  "nvm")
    rm -rf "$HOME/.nvm" 2>/dev/null
    [[ -d "$backup_dir/nvm_backup" ]] && cp -r "$backup_dir/nvm_backup" "$HOME/.nvm" 2>/dev/null
    ;;
  "pyenv")
    rm -rf "$HOME/.pyenv" 2>/dev/null
    [[ -d "$backup_dir/pyenv_backup" ]] && cp -r "$backup_dir/pyenv_backup" "$HOME/.pyenv" 2>/dev/null
    ;;
  "sdkman")
    rm -rf "$HOME/.sdkman" 2>/dev/null
    [[ -d "$backup_dir/sdkman_backup" ]] && cp -r "$backup_dir/sdkman_backup" "$HOME/.sdkman" 2>/dev/null
    ;;
  "rust")
    rm -rf "$HOME/.cargo" 2>/dev/null
    rm -rf "$HOME/.rustup" 2>/dev/null
    [[ -d "$backup_dir/cargo_backup" ]] && cp -r "$backup_dir/cargo_backup" "$HOME/.cargo" 2>/dev/null
    [[ -d "$backup_dir/rustup_backup" ]] && cp -r "$backup_dir/rustup_backup" "$HOME/.rustup" 2>/dev/null
    ;;
  esac

  # Cleanup backup
  rm -rf "$backup_dir" 2>/dev/null
  unset INSTALLATION_BACKUPS["$component"]

  log_success "Rollback completed for $component"
  return 0
}

setup_with_error_handling() {
  local component="$1"
  local setup_function="$2"
  shift 2
  local args=("$@")

  # Create backup before installation
  create_installation_backup "$component"

  # Execute installation with error handling
  if "$setup_function" "${args[@]}"; then
    log_success "$component installation completed successfully"
    # Cleanup backup on success
    local backup_dir="${INSTALLATION_BACKUPS[$component]}"
    [[ -n "$backup_dir" ]] && rm -rf "$backup_dir" 2>/dev/null
    unset INSTALLATION_BACKUPS["$component"]
    return 0
  else
    log_error "$component installation failed"

    # Attempt rollback
    if rollback_installation "$component"; then
      log_info "$component installation rolled back successfully"
    else
      log_warning "$component rollback failed - manual cleanup may be required"
    fi

    return 1
  fi
}

# --- NVM (Node Version Manager) ---

setup_nvm() {
  init_logging
  local install_latest=${1:-true}
  local install_lts=${2:-true}

  # Validate parameters
  if ! validate_boolean_param "$install_latest" "install_latest" ||
    ! validate_boolean_param "$install_lts" "install_lts"; then
    finish_logging
    return 1
  fi

  # Normalize boolean parameters
  install_latest=$(normalize_boolean "$install_latest")
  install_lts=$(normalize_boolean "$install_lts")

  # Create NVM directory if it doesn't exist
  export NVM_DIR="$HOME/.nvm"
  mkdir -p "$NVM_DIR"

  # Get latest NVM version
  log_info "Fetching latest NVM version..."
  local NVM_VERSION
  NVM_VERSION=$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest |
    grep "tag_name" | cut -d '"' -f 4 || echo "v0.39.7")

  log_info "Installing NVM $NVM_VERSION..."
  local nvm_url="https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh"

  if ! validate_and_download "$nvm_url" "NVM installer" "execute"; then
    log_error "Failed to securely install NVM"
    finish_logging
    return 1
  fi

  # Source NVM in the current shell
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1091
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

  # Add NVM to shell profiles if not already there
  for PROFILE in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [ -f "$PROFILE" ] && ! grep -q 'NVM_DIR' "$PROFILE"; then
      {
        echo ''
        echo '# NVM Configuration'
        echo "export NVM_DIR=\"\$HOME/.nvm\""
        echo "[ -s \"\$NVM_DIR/nvm.sh\" ] && \. \"\$NVM_DIR/nvm.sh\""
        echo "[ -s \"\$NVM_DIR/bash_completion\" ] && \. \"\$NVM_DIR/bash_completion\""
      } >>"$PROFILE"
      log_success "Added NVM to $PROFILE"
    fi
  done

  if [[ "$install_lts" == "true" ]]; then
    log_info "Installing Node.js LTS version..."
    if ! nvm install --lts; then
      local default_lts="20"
      log_warning "LTS installation failed, installing Node.js v$default_lts instead"
      nvm install "$default_lts"
    fi
  fi

  if [[ "$install_latest" == "true" ]]; then
    log_info "Installing latest Node.js version..."
    if ! nvm install node; then
      local default_current="22"
      log_warning "Latest installation failed, installing Node.js v$default_current instead"
      nvm install "$default_current"
    fi
  fi

  # Set LTS as default
  log_info "Setting LTS as default Node.js version"
  nvm alias default --lts || nvm alias default "$(nvm version)"
  nvm use default

  # Print versions
  local node_version
  node_version="$(node -v)"
  local npm_version
  npm_version="$(npm -v)"
  log_success "Node.js version: $node_version, npm version: $npm_version"

  finish_logging
}

# --- Pyenv (Python Version Manager) ---

setup_pyenv() {
  init_logging
  local python312=${1:-true}
  local python311=${2:-true}

  # Validate parameters
  if ! validate_boolean_param "$python312" "python312" ||
    ! validate_boolean_param "$python311" "python311"; then
    finish_logging
    return 1
  fi

  # Normalize boolean parameters
  python312=$(normalize_boolean "$python312")
  python311=$(normalize_boolean "$python311")

  # Install pyenv dependencies
  log_info "Installing pyenv dependencies..."
  sudo apt-get update -q
  sudo apt-get install -y build-essential libssl-dev zlib1g-dev libbz2-dev \
    libreadline-dev libsqlite3-dev wget curl llvm libncurses5-dev libncursesw5-dev \
    xz-utils tk-dev libffi-dev liblzma-dev python3-openssl git

  # Install pyenv
  log_info "Installing pyenv..."
  if [ ! -d "$HOME/.pyenv" ]; then
    if ! validate_and_download "https://pyenv.run" "pyenv installer" "execute"; then
      log_error "Failed to securely install pyenv"
      finish_logging
      return 1
    fi
  else
    log_info "pyenv already installed, updating..."
    (cd "$HOME/.pyenv" && git pull) || {
      log_warning "Failed to update pyenv"
      return 1
    }
  fi

  # Add pyenv to shell profiles
  for PROFILE in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [ -f "$PROFILE" ] && ! grep -q 'pyenv init' "$PROFILE"; then
      {
        echo ''
        echo '# Pyenv Configuration'
        echo "export PYENV_ROOT=\"\$HOME/.pyenv\""
        echo "export PATH=\"\$PYENV_ROOT/bin:\$PATH\""
        echo "if command -v pyenv >/dev/null; then eval \"\$(pyenv init -)\"; fi"
      } >>"$PROFILE"
      log_success "Added pyenv to $PROFILE"
    fi
  done

  # Load pyenv in current shell
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)"

  # Install Python versions
  if [[ "$python312" == "true" ]]; then
    log_info "Installing Python 3.12..."
    pyenv install -s 3.12.0 || log_warning "Failed to install Python 3.12.0"
  fi

  if [[ "$python311" == "true" ]]; then
    log_info "Installing Python 3.11..."
    pyenv install -s 3.11.8 || log_warning "Failed to install Python 3.11.8"
  fi

  # Set global Python version
  if pyenv versions | grep -q "3.12"; then
    pyenv global 3.12.0
  elif pyenv versions | grep -q "3.11"; then
    pyenv global 3.11.8
  fi

  # Print versions
  log_success "Python versions installed: $(pyenv versions --bare | tr '\n' ' ')"
  log_success "Current Python: $(pyenv which python)"

  finish_logging
}

# --- SDKMAN (Java Version Manager) ---

setup_sdkman() {
  init_logging
  local install_java17=${1:-true}
  local install_java21=${2:-true}

  # Validate parameters
  if ! validate_boolean_param "$install_java17" "install_java17" ||
    ! validate_boolean_param "$install_java21" "install_java21"; then
    finish_logging
    return 1
  fi

  # Normalize boolean parameters
  install_java17=$(normalize_boolean "$install_java17")
  install_java21=$(normalize_boolean "$install_java21")

  # Install SDKMAN if not already installed
  if [ ! -d "$HOME/.sdkman" ]; then
    log_info "Installing SDKMAN..."
    if ! validate_and_download "https://get.sdkman.io" "SDKMAN installer" "execute"; then
      log_error "Failed to securely install SDKMAN"
      finish_logging
      return 1
    fi
  else
    log_info "SDKMAN already installed"
  fi

  # Source SDKMAN
  export SDKMAN_DIR="$HOME/.sdkman"
  # shellcheck disable=SC1091
  [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

  # Add SDKMAN to shell profiles
  for PROFILE in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [ -f "$PROFILE" ] && ! grep -q 'sdkman-init.sh' "$PROFILE"; then
      {
        echo ''
        echo '# SDKMAN Configuration'
        echo "export SDKMAN_DIR=\"\$HOME/.sdkman\""
        echo "[[ -s \"\$HOME/.sdkman/bin/sdkman-init.sh\" ]] && source \"\$HOME/.sdkman/bin/sdkman-init.sh\""
      } >>"$PROFILE"
      log_success "Added SDKMAN to $PROFILE"
    fi
  done

  # Install Java versions
  if [[ "$install_java17" == "true" ]]; then
    log_info "Installing Java 17 LTS..."
    sdk install java 17.0-tem || sdk install java 17.0.9-tem || log_warning "Failed to install Java 17"
  fi

  if [[ "$install_java21" == "true" ]]; then
    log_info "Installing Java 21 LTS..."
    sdk install java 21.0-tem || sdk install java 21.0.2-tem || log_warning "Failed to install Java 21"
  fi

  # Set default Java version to 17 for broader compatibility
  if sdk list java | grep -q installed | grep -q "17."; then
    sdk default java 17.0-tem 2>/dev/null || sdk default java 17.0.9-tem 2>/dev/null || log_warning "Could not set Java 17 as default"
  fi

  # Print versions
  local java_version
  java_version="$(java -version 2>&1 | grep version | cut -d '"' -f 2)"
  log_success "Java versions installed: $(sdk list java | grep installed | tr '\n' ' ')"
  log_success "Default Java: $java_version"

  finish_logging
}

# --- Rustup (Rust Version Manager) ---

setup_rustup() {
  init_logging

  # Install rustup if not already installed
  if ! command -v rustup >/dev/null 2>&1; then
    log_info "Installing Rust via rustup..."

    if ! validate_and_download "https://sh.rustup.rs" "Rustup installer" "execute"; then
      log_error "Failed to securely install Rust"
      finish_logging
      return 1
    fi

    # Source rustup
    # shellcheck disable=SC1091
    source "$HOME/.cargo/env"

    # Add rustup to shell profiles
    for PROFILE in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
      if [ -f "$PROFILE" ] && ! grep -q 'cargo/env' "$PROFILE"; then
        echo "source \"\$HOME/.cargo/env\"" >>"$PROFILE"
        log_success "Added Rust to $PROFILE"
      fi
    done
  else
    log_info "Rust already installed, updating..."
    rustup update
  fi

  # Check installation
  if command -v rustc >/dev/null 2>&1; then
    local rust_version
    rust_version="$(rustc --version)"
    log_success "Rust installed: $rust_version"
  else
    log_error "Rust installation failed"
  fi

  finish_logging
}

# --- GHCup (Haskell Version Manager) ---

setup_ghcup() {
  init_logging

  # Install GHCup if not already installed
  if ! command -v ghcup >/dev/null 2>&1; then
    log_info "Installing Haskell via GHCup..."

    # Set environment variable for non-interactive installation
    export BOOTSTRAP_HASKELL_NONINTERACTIVE=1

    if ! validate_and_download "https://get-ghcup.haskell.org" "GHCup installer" "execute"; then
      log_error "Failed to securely install Haskell"
      finish_logging
      return 1
    fi

    # Add GHCup to shell profiles
    for PROFILE in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
      if [ -f "$PROFILE" ] && ! grep -q '.ghcup/env' "$PROFILE"; then
        echo "source \"\$HOME/.ghcup/env\"" >>"$PROFILE"
        log_success "Added GHCup to $PROFILE"
      fi
    done
  else
    log_info "GHCup already installed, updating..."
    ghcup upgrade
  fi

  # Check installation
  if command -v ghc >/dev/null 2>&1; then
    local ghc_version
    ghc_version="$(ghc --version)"
    log_success "Haskell installed: $ghc_version"
  else
    log_error "Haskell installation failed"
  fi

  finish_logging
}

# --- Go Version Management ---

setup_golang() {
  init_logging
  local version="${1:-latest}"

  # Install Go
  if [ "$version" = "latest" ]; then
    log_info "Installing latest Go version..."
    safe_apt_install golang-go
  else
    log_info "Installing Go $version..."
    # Implementation for specific versions would go here
    # This would likely download binaries from golang.org
    safe_apt_install golang-go
  fi

  # Set up Go environment
  mkdir -p "$HOME/go/bin" "$HOME/go/src" "$HOME/go/pkg"

  # Add Go to shell profiles
  for PROFILE in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [ -f "$PROFILE" ] && ! grep -q 'GOPATH=' "$PROFILE"; then
      {
        echo ''
        echo '# Go Configuration'
        echo "export GOPATH=\$HOME/go"
        echo "export PATH=\$PATH:\$GOPATH/bin"
      } >>"$PROFILE"
      log_success "Added Go to $PROFILE"
    fi
  done

  # Check installation
  if command -v go >/dev/null 2>&1; then
    local go_version
    go_version="$(go version)"
    log_success "Go installed: $go_version"
  else
    log_error "Go installation failed"
  fi

  finish_logging
}

# --- Shell Profile Management Optimization ---
declare -A SHELL_PROFILE_QUEUE=()

queue_profile_update() {
  local profile="$1"
  local content="$2"
  local marker="$3"

  # Add to queue instead of immediate update
  local key="${profile}_${marker}"
  SHELL_PROFILE_QUEUE["$key"]="$content"
}

apply_all_profile_updates() {
  log_info "Applying all shell profile updates..."

  local profiles=("$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile")

  for profile in "${profiles[@]}"; do
    if [[ ! -f "$profile" ]]; then
      continue
    fi

    local profile_name
    profile_name=$(basename "$profile")
    local updates_applied=false
    local temp_file
    temp_file=$(mktemp)

    # Copy existing content
    cp "$profile" "$temp_file"

    # Apply all queued updates for this profile
    for key in "${!SHELL_PROFILE_QUEUE[@]}"; do
      local key_profile="${key%_*}"
      local marker="${key#*_}"
      local content="${SHELL_PROFILE_QUEUE[$key]}"

      if [[ "$key_profile" == "$profile_name" ]]; then
        # Check if update already exists
        if ! grep -q "$marker" "$temp_file"; then
          echo "$content" >>"$temp_file"
          updates_applied=true
        fi
      fi
    done

    # Only update file if changes were made
    if [[ "$updates_applied" == "true" ]]; then
      mv "$temp_file" "$profile"
      log_info "Updated $profile_name"
    else
      rm -f "$temp_file"
    fi
  done

  # Clear the queue
  SHELL_PROFILE_QUEUE=()
}

# --- Parallel Installation Support ---
setup_multiple_parallel() {
  local components=("$@")
  local max_parallel=3
  local pids=()

  log_info "Installing version managers in parallel..."

  for component in "${components[@]}"; do
    # Limit parallel processes
    if [[ ${#pids[@]} -ge $max_parallel ]]; then
      # Wait for one to complete
      wait "${pids[0]}"
      pids=("${pids[@]:1}") # Remove first element
    fi

    # Start installation in background
    case "$component" in
    "nvm")
      setup_nvm true true &
      ;;
    "pyenv")
      setup_pyenv true true &
      ;;
    "sdkman")
      setup_sdkman true true &
      ;;
    "rustup")
      setup_rustup &
      ;;
    "golang")
      setup_golang &
      ;;
    *)
      log_warning "Unknown component: $component"
      continue
      ;;
    esac

    pids+=($!)
    log_info "Started $component installation"
  done

  # Wait for all remaining processes
  for pid in "${pids[@]}"; do
    wait "$pid" || log_warning "Component installation failed"
  done

  # Apply all profile updates at once
  apply_all_profile_updates

  log_success "Parallel installation completed"
}

# --- Resource Monitoring ---
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

# Configure all shell profiles for NVM with optimized function
configure_nvm_environment() {
  local nvm_config='
# NVM Configuration
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'

  for profile in "bashrc" "zshrc" "profile"; do
    queue_profile_update "$profile" "$nvm_config" "NVM Configuration"
  done
}

# Configure all shell profiles for pyenv with optimized function
configure_pyenv_environment() {
  local pyenv_config='
# Pyenv Configuration
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
if command -v pyenv >/dev/null; then eval "$(pyenv init -)"; fi'

  for profile in "bashrc" "zshrc" "profile"; do
    queue_profile_update "$profile" "$pyenv_config" "Pyenv Configuration"
  done
}

# Main function for demonstration
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Version manager utilities loaded. Use by sourcing this file."
  exit 0
fi
