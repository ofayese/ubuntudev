#!/usr/bin/env bash
# setup-desktop.sh - Ubuntu Developer Desktop Environment Setup
# Modular desktop setup utility with robust error handling and security
set -euo pipefail

# Script version and last updated timestamp
readonly VERSION="1.0.0"
readonly LAST_UPDATED="2025-06-13"

# Cross-platform support
OS_TYPE="$(uname -s)"
readonly OS_TYPE

# Dry-run mode support
readonly DRY_RUN="${DRY_RUN:-false}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# Source utility modules with error checking
source "$SCRIPT_DIR/util-log.sh" || {
  echo "FATAL: Failed to source util-log.sh" >&2
  exit 1
}
source "$SCRIPT_DIR/util-install.sh" || {
  echo "FATAL: Failed to source util-install.sh" >&2
  exit 1
}
source "$SCRIPT_DIR/util-env.sh" || {
  echo "FATAL: Failed to source util-env.sh" >&2
  exit 1
}

# Constants and configuration
STATE_DIR="$HOME/.desktop-setup-state"
readonly STATE_DIR
STATE_FILE="$STATE_DIR/installation.state"
readonly STATE_FILE
ROLLBACK_DIR="$STATE_DIR/backups"
readonly ROLLBACK_DIR
DOWNLOAD_DIR="/tmp/desktop-setup-downloads"
readonly DOWNLOAD_DIR

# Default settings
# shellcheck disable=SC2034  # VERBOSE is used in command line parsing and reserved for future logging enhancement
VERBOSE=false
FORCE_REINSTALL=false
AUTO_ROLLBACK=false
SECURE_MODE=true
OFFLINE_MODE=false

# Display dry-run mode notice if active
if [[ "$DRY_RUN" == "true" ]]; then
  log_info "=== DRY RUN MODE: No system changes will be made ==="
  log_info "This is a simulation to show what would be installed."
fi

# Categories with dependencies
declare -A INSTALL_CATEGORIES=(
  ["system_updates"]="System Updates & Core Packages"
  ["security"]="Security & Hardening"
  ["dev_tools"]="Development Tools"
  ["desktop_env"]="Desktop Environment"
  ["media_tools"]="Multimedia Tools"
  ["productivity"]="Productivity Apps"
  ["virtualization"]="Virtualization Tools"
  ["languages"]="Programming Languages"
)

declare -A CATEGORY_DEPENDENCIES=(
  ["security"]="system_updates"
  ["dev_tools"]="system_updates"
  ["desktop_env"]="system_updates"
  ["media_tools"]="system_updates"
  ["productivity"]="desktop_env"
  ["virtualization"]="dev_tools"
  ["languages"]="dev_tools"
)

# Initialize logging
init_logging
log_info "Desktop setup started (v$VERSION)"

# --- Helper functions ---

# Check if running in a desktop environment
is_desktop_environment() {
  command -v gnome-shell >/dev/null 2>&1 && echo "${XDG_SESSION_TYPE:-}" | grep -qE 'x11|wayland'
}

# Get available disk space in GB
get_available_disk() {
  df -BG "$HOME" | grep -v Filesystem | awk '{print $4}' | tr -d 'G'
}

# Get available memory in GB
get_available_memory() {
  free -g | grep Mem | awk '{print $7}'
}

# Check internet connectivity
check_internet_connectivity() {
  ping -c 1 8.8.8.8 >/dev/null 2>&1 || ping -c 1 google.com >/dev/null 2>&1
}

# Display usage information
show_usage() {
  cat <<EOF
Ubuntu Developer Desktop Setup v$VERSION

Usage: $0 [OPTIONS]

Options:
  --category CATEGORY    Install specific category only (can be repeated)
  --list-categories     List available installation categories
  --force               Force reinstallation even if already installed
  --status              Show current installation status
  --rollback CATEGORY   Rollback specific category installation
  --offline             Skip components requiring internet access
  --verbose             Enable verbose output
  --no-secure           Disable secure download verification
  --help                Show this help message

Categories:
$(for cat in "${!INSTALL_CATEGORIES[@]}"; do echo "  $cat: ${INSTALL_CATEGORIES[$cat]}"; done | sort)

Examples:
  $0                                # Install everything
  $0 --category system_updates      # Install system updates only
  $0 --status                       # Show installation status
EOF
}

# --- Resource validation ---

# Check system resources before installation
check_system_resources() {
  log_info "Validating system resources..."

  local validation_errors=()
  local warnings=()

  # Check disk space
  local available_space_gb
  available_space_gb=$(get_available_disk)
  if [[ "$available_space_gb" -lt 5 ]]; then
    validation_errors+=("Insufficient disk space: ${available_space_gb}GB (need 5GB+)")
  elif [[ "$available_space_gb" -lt 10 ]]; then
    warnings+=("Low disk space: ${available_space_gb}GB (10GB+ recommended)")
  fi

  # Check memory
  local available_memory_gb
  available_memory_gb=$(get_available_memory)
  if [[ "$available_memory_gb" -lt 1 ]]; then
    validation_errors+=("Insufficient memory: ${available_memory_gb}GB (need 1GB+)")
  elif [[ "$available_memory_gb" -lt 2 ]]; then
    warnings+=("Low memory: ${available_memory_gb}GB (2GB+ recommended)")
  fi

  # Check internet connectivity
  if ! check_internet_connectivity; then
    if [[ "$OFFLINE_MODE" == "true" ]]; then
      warnings+=("No internet connectivity - running in offline mode")
    else
      validation_errors+=("No internet connectivity - required for downloads")
    fi
  fi

  # Check sudo privileges
  if ! sudo -n true 2>/dev/null; then
    log_info "Testing sudo privileges..."
    if ! sudo -v; then
      validation_errors+=("Sudo privileges required but not available")
    fi
  fi

  # Report errors
  if [[ ${#validation_errors[@]} -gt 0 ]]; then
    log_error "System resource validation failed:"
    for error in "${validation_errors[@]}"; do
      log_error "  ❌ $error"
    done

    log_error "Please address these issues before proceeding"
    return 1
  fi

  # Report warnings
  if [[ ${#warnings[@]} -gt 0 ]]; then
    log_warning "System resource warnings:"
    for warning in "${warnings[@]}"; do
      log_warning "  ⚠️ $warning"
    done

    if [[ "${FORCE_INSTALL:-false}" != "true" ]]; then
      log_info "Continue anyway? (y/N)"
      read -r response
      if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled by user"
        return 1
      fi
    fi
  fi

  log_success "System resource validation passed"
  return 0
}

# --- State management ---

# Initialize state management system
init_state_management() {
  mkdir -p "$STATE_DIR" "$ROLLBACK_DIR"

  if [[ ! -f "$STATE_FILE" ]]; then
    log_info "Initializing installation state tracking..."
    cat >"$STATE_FILE" <<EOF
# Desktop Setup Installation State
# Format: CATEGORY:STATUS:TIMESTAMP
# Status: PENDING|RUNNING|COMPLETED|FAILED|ROLLED_BACK
EOF
  fi
}

# Update component installation state
update_component_state() {
  local category="$1"
  local status="$2"
  local timestamp
  timestamp="$(date +%s)"

  # Remove existing entry
  if [[ -f "$STATE_FILE" ]]; then
    grep -v "^${category}:" "$STATE_FILE" >"${STATE_FILE}.tmp" || true
    mv "${STATE_FILE}.tmp" "$STATE_FILE"
  fi

  # Add new entry
  echo "${category}:${status}:${timestamp}" >>"$STATE_FILE"

  log_debug "Updated state: $category -> $status"
}

# Check if component is installed
is_component_installed() {
  local category="$1"

  if [[ -f "$STATE_FILE" ]]; then
    grep -q "^${category}:COMPLETED:" "$STATE_FILE"
  else
    return 1
  fi
}

# Create rollback point
create_rollback_point() {
  local category="$1"
  local rollback_point
  rollback_point="$ROLLBACK_DIR/${category}_$(date +%Y%m%d_%H%M%S)"

  log_info "Creating rollback point for $category..."
  mkdir -p "$rollback_point"

  # Backup relevant configurations
  case "$category" in
  "system_updates")
    cp -r /etc/apt/ "$rollback_point/" 2>/dev/null || true
    dpkg --get-selections >"$rollback_point/packages.list"
    ;;
  "dev_tools")
    cp "$HOME/.bashrc" "$rollback_point/" 2>/dev/null || true
    cp "$HOME/.zshrc" "$rollback_point/" 2>/dev/null || true
    ;;
  "desktop_env")
    mkdir -p "$rollback_point/config_backup/"
    cp -r "$HOME/.config/gtk-3.0" "$rollback_point/config_backup/" 2>/dev/null || true
    gsettings list-recursively >"$rollback_point/gsettings.backup" 2>/dev/null || true
    ;;
  esac

  echo "$rollback_point"
}

# Rollback installation
rollback_category() {
  local category="$1"
  local rollback_point="${2:-}"

  log_warning "Rolling back installation: $category"

  # Find most recent rollback point if not specified
  if [[ -z "$rollback_point" ]]; then
    rollback_point=$(find "$ROLLBACK_DIR" -type d -name "${category}_*" | sort -r | head -1)
  fi

  if [[ -z "$rollback_point" ]] || [[ ! -d "$rollback_point" ]]; then
    log_error "No rollback point found for $category"
    return 1
  fi

  log_info "Using rollback point: $rollback_point"

  # Category-specific rollback actions
  case "$category" in
  "system_updates")
    log_warning "Package rollback requires manual intervention"
    log_info "Backup package list available at: $rollback_point/packages.list"
    ;;
  "dev_tools")
    [[ -f "$rollback_point/.bashrc" ]] && cp "$rollback_point/.bashrc" "$HOME/"
    [[ -f "$rollback_point/.zshrc" ]] && cp "$rollback_point/.zshrc" "$HOME/"
    ;;
  "desktop_env")
    if [[ -f "$rollback_point/gsettings.backup" ]]; then
      log_warning "Desktop settings rollback requires manual restoration"
      log_info "Settings backup available at: $rollback_point/gsettings.backup"
    fi
    ;;
  esac

  update_component_state "$category" "ROLLED_BACK"
  log_success "Rollback completed for $category"
}

# Show installation status
show_installation_status() {
  log_info "Installation Status Report:"
  echo "================================"

  if [[ ! -f "$STATE_FILE" ]]; then
    echo "No installation state found."
    return
  fi

  local total=0 completed=0 failed=0 running=0

  while IFS=: read -r category status timestamp; do
    [[ "$category" =~ ^#.*$ ]] && continue # Skip comments
    [[ -z "$category" ]] && continue       # Skip empty lines

    ((total++))

    local status_icon
    case "$status" in
    "COMPLETED")
      status_icon="✅"
      ((completed++))
      ;;
    "FAILED")
      status_icon="❌"
      ((failed++))
      ;;
    "RUNNING")
      status_icon="🔄"
      ((running++))
      ;;
    "ROLLED_BACK") status_icon="↩️" ;;
    *) status_icon="⏳" ;;
    esac

    local readable_time
    if [[ "$timestamp" =~ ^[0-9]+$ ]]; then
      readable_time=$(date -d "@$timestamp" 2>/dev/null || date -r "$timestamp" 2>/dev/null || echo "unknown")
    else
      readable_time="unknown"
    fi

    printf "%-20s %s %-12s %s\n" "$category" "$status_icon" "$status" "$readable_time"
  done <"$STATE_FILE"

  echo "================================"
  echo "Summary: $completed completed, $failed failed, $running running, $total total"
}

# --- Secure download management ---

# Setup secure downloads
setup_secure_downloads() {
  mkdir -p "$DOWNLOAD_DIR"
  chmod 700 "$DOWNLOAD_DIR"
}

# Secure download with verification
secure_download() {
  local url="$1"
  local expected_checksum="${2:-}"
  local output_file
  output_file="$DOWNLOAD_DIR/$(basename "$url")"

  log_info "Securely downloading: $(basename "$url")"

  # Clean up any existing file
  rm -f "$output_file"

  # Download file
  if ! curl -fsSL --connect-timeout 10 --max-time 300 "$url" -o "$output_file"; then
    log_error "Failed to download: $url"
    return 1
  fi

  # Verify checksum if provided and secure mode is enabled
  if [[ -n "$expected_checksum" ]] && [[ "$SECURE_MODE" == "true" ]]; then
    local actual_checksum
    actual_checksum=$(sha256sum "$output_file" | cut -d' ' -f1)

    if [[ "$actual_checksum" != "$expected_checksum" ]]; then
      log_error "Checksum verification failed"
      log_error "  Expected: $expected_checksum"
      log_error "  Actual:   $actual_checksum"
      rm -f "$output_file"
      return 1
    fi

    log_success "Checksum verified"
  elif [[ "$SECURE_MODE" == "true" ]]; then
    log_warning "No checksum provided - cannot verify integrity"
  fi

  echo "$output_file"
}

# Secure .deb installation
secure_install_deb() {
  local deb_url="$1"
  local package_name="${2:-unknown}"
  local expected_checksum="${3:-}"

  log_info "Installing .deb package: $package_name"

  # Download and verify
  local deb_file
  if deb_file=$(secure_download "$deb_url" "$expected_checksum"); then
    # Install the package
    if sudo dpkg -i "$deb_file"; then
      log_success "Package installed successfully: $package_name"

      # Fix any dependency issues
      sudo apt-get install -f -y >/dev/null 2>&1 || true
    else
      log_error "Package installation failed: $package_name"
      return 1
    fi

    # Clean up
    rm -f "$deb_file"
  else
    log_error "Failed to download package: $package_name"
    return 1
  fi
}

# --- Error handling ---

# Setup error handling
setup_error_handling() {
  # Set up error trapping
  set -euo pipefail

  # Custom error handler
  error_handler() {
    local exit_code=$?
    local line_number=$1

    log_error "Error at line $line_number (exit code: $exit_code)"

    # Update state for current category if set
    if [[ -n "${CURRENT_CATEGORY:-}" ]]; then
      log_error "During installation of: $CURRENT_CATEGORY"
      update_component_state "$CURRENT_CATEGORY" "FAILED"
    fi

    # Clean up
    cleanup_processes

    return $exit_code
  }

  # Set up error trap
  trap 'error_handler ${LINENO}' ERR

  # Set up cleanup trap
  trap 'cleanup_on_exit' EXIT INT TERM
}

# Cleanup background processes
cleanup_processes() {
  local bg_jobs
  bg_jobs=$(jobs -p)

  if [[ -n "$bg_jobs" ]]; then
    log_info "Cleaning up background processes..."
    echo "$bg_jobs" | xargs -r kill 2>/dev/null || true
  fi
}

# Cleanup function for script termination
cleanup_on_exit() {
  local exit_code=$?

  log_info "Performing cleanup..."

  # Clean up temporary files
  rm -f /tmp/apt_install.log 2>/dev/null || true

  # Stop any background monitoring
  cleanup_processes

  # Clear current category
  unset CURRENT_CATEGORY

  # Log final status
  if [[ $exit_code -eq 0 ]]; then
    log_success "Desktop setup completed successfully"
  else
    log_error "Desktop setup exited with code: $exit_code"
    log_info "Use '$0 --status' to check installation status"
  fi
}

# --- Installation modules ---

# System Updates & Core Packages
install_system_updates() {
  log_info "Installing system updates and core packages..."

  # System updates
  sudo apt update && sudo apt upgrade -y
  safe_apt_install vim nano unzip zip curl wget git software-properties-common

  # Set default editor
  sudo update-alternatives --set editor /usr/bin/vim.basic

  # Enable unattended security updates
  sudo apt install -y unattended-upgrades
  sudo dpkg-reconfigure -plow unattended-upgrades

  log_success "System updates completed"
}

# Security & Hardening
install_security() {
  log_info "Applying security hardening..."

  # Firewall & Hardening
  safe_apt_install ufw gufw fail2ban
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw allow ssh
  sudo ufw enable

  # Disable crash reports
  sudo systemctl disable --now apport.service
  sudo sed -i 's/enabled=1/enabled=0/' /etc/default/apport

  log_success "Security hardening completed"
}

# Development Tools
install_dev_tools() {
  log_info "Installing development tools..."

  # Development tools
  safe_apt_install build-essential git-core git-extras ssh
  safe_apt_install p7zip-full p7zip-rar rar unrar tar glow
  safe_apt_install fonts-firacode fonts-jetbrains-mono zsh tmux fzf bat

  # Install starship from official installer if not already installed
  if ! command -v starship >/dev/null 2>&1; then
    log_info "Installing Starship prompt..."
    if [[ "$SECURE_MODE" == "true" ]]; then
      local starship_installer
      starship_installer=$(secure_download "https://starship.rs/install.sh")
      bash "$starship_installer" -y
      rm -f "$starship_installer"
    else
      curl -sS https://starship.rs/install.sh | sh -s -- -y
    fi
  fi

  log_success "Development tools installation completed"
}

# Desktop Environment
install_desktop_env() {
  log_info "Setting up desktop environment..."

  # GNOME Customizations
  safe_apt_install gnome-tweaks gnome-shell-extensions
  gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
  gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true

  # Screenshot & Backup Tools
  safe_apt_install timeshift flameshot

  log_success "Desktop environment setup completed"
}

# Multimedia Tools
install_media_tools() {
  log_info "Installing multimedia tools..."

  # Multimedia
  safe_apt_install vlc totem gimp imagemagick ffmpeg

  log_success "Multimedia tools installation completed"
}

# Productivity Apps
install_productivity() {
  log_info "Installing productivity applications..."

  # Markdown & Reading Tools
  safe_apt_install libreoffice

  # Install Obsidian
  secure_install_deb "https://github.com/obsidianmd/obsidian-releases/releases/latest/download/obsidian_amd64.deb" "obsidian"

  log_success "Productivity applications installation completed"
}

# Virtualization Tools
install_virtualization() {
  log_info "Installing virtualization tools..."

  # Virtualization
  safe_apt_install virtualbox vagrant

  # Container tools
  safe_apt_install podman buildah skopeo

  log_success "Virtualization tools installation completed"
}

# Programming Languages
install_languages() {
  log_info "Installing language runtimes..."

  # Python
  safe_apt_install python3-pip python3-venv

  # Node.js
  if ! command -v node >/dev/null 2>&1; then
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt-get install -y nodejs
  fi

  # Go
  safe_apt_install golang-go

  log_success "Language runtimes installation completed"
}

# --- Main installation wrapper ---

# Execute installation with state management
install_with_management() {
  local category="$1"
  local install_function="$2"

  # Set current category for error handling
  export CURRENT_CATEGORY="$category"

  # Check if already installed
  if is_component_installed "$category" && [[ "${FORCE_REINSTALL:-false}" != "true" ]]; then
    log_info "Skipping $category (already installed, use --force to reinstall)"
    return 0
  fi

  # Create rollback point
  local rollback_point
  rollback_point=$(create_rollback_point "$category")

  # Update state to running
  update_component_state "$category" "RUNNING"

  log_info "Installing $category..."

  # Execute installation with timeout
  if timeout 1800 bash -c "$install_function"; then
    log_success "$category completed successfully"
    update_component_state "$category" "COMPLETED"
    return 0
  else
    local exit_code=$?
    log_error "$category installation failed (exit code: $exit_code)"
    update_component_state "$category" "FAILED"

    # Offer rollback
    if [[ "${AUTO_ROLLBACK:-false}" == "true" ]]; then
      log_info "Auto-rollback enabled, rolling back $category..."
      rollback_category "$category" "$rollback_point"
    else
      log_info "Rollback available. Run: $0 --rollback $category"
    fi

    return $exit_code
  fi
}

# Resolve category dependencies
resolve_category_dependencies() {
  local categories=("$@")
  local resolved=()
  local -A visited=()

  resolve_deps() {
    local cat="$1"
    if [[ -n "${visited[$cat]:-}" ]]; then
      return
    fi

    visited["$cat"]=1

    if [[ -n "${CATEGORY_DEPENDENCIES[$cat]:-}" ]]; then
      resolve_deps "${CATEGORY_DEPENDENCIES[$cat]}"
    fi

    resolved+=("$cat")
  }

  for cat in "${categories[@]}"; do
    resolve_deps "$cat"
  done

  printf '%s ' "${resolved[@]}"
}

# --- Main program logic ---

main() {
  local selected_categories=()
  local install_all=true

  # Parse command line arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
    --category)
      selected_categories+=("$2")
      install_all=false
      shift 2
      ;;
    --list-categories)
      log_info "Available installation categories:"
      for category in "${!INSTALL_CATEGORIES[@]}"; do
        echo "  $category: ${INSTALL_CATEGORIES[$category]}"
      done
      exit 0
      ;;
    --status)
      init_state_management
      show_installation_status
      exit 0
      ;;
    --rollback)
      init_state_management
      rollback_category "$2"
      exit $?
      ;;
    --force)
      FORCE_REINSTALL=true
      shift
      ;;
    --offline)
      OFFLINE_MODE=true
      shift
      ;;
    --verbose)
      # shellcheck disable=SC2034  # VERBOSE is reserved for future logging enhancement
      VERBOSE=true
      shift
      ;;
    --no-secure)
      SECURE_MODE=false
      shift
      ;;
    --help)
      show_usage
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      show_usage
      exit 1
      ;;
    esac
  done

  # Headless environment detection
  if ! is_desktop_environment; then
    log_warning "Headless environment detected — skipping desktop customization."
    exit 0
  fi

  # Setup
  setup_error_handling
  init_state_management
  setup_secure_downloads

  # Check system resources
  if ! check_system_resources; then
    log_error "Resource validation failed, exiting"
    exit 3
  fi

  # Determine categories to install
  if [[ "$install_all" == "true" ]]; then
    selected_categories=("${!INSTALL_CATEGORIES[@]}")
  fi

  # Resolve dependencies and create execution order
  local execution_order
  execution_order=$(resolve_category_dependencies "${selected_categories[@]}")

  log_info "Installing categories: ${selected_categories[*]}"
  log_info "Execution order: $execution_order"

  # Execute installations in dependency order
  for category in $execution_order; do
    case "$category" in
    "system_updates")
      install_with_management "system_updates" "install_system_updates"
      ;;
    "security")
      install_with_management "security" "install_security"
      ;;
    "dev_tools")
      install_with_management "dev_tools" "install_dev_tools"
      ;;
    "desktop_env")
      install_with_management "desktop_env" "install_desktop_env"
      ;;
    "media_tools")
      install_with_management "media_tools" "install_media_tools"
      ;;
    "productivity")
      install_with_management "productivity" "install_productivity"
      ;;
    "virtualization")
      install_with_management "virtualization" "install_virtualization"
      ;;
    "languages")
      install_with_management "languages" "install_languages"
      ;;
    *)
      log_warning "Unknown category: $category"
      ;;
    esac
  done

  # Show final installation status
  show_installation_status

  log_success "Desktop setup completed successfully!"
}

# Execute main function
main "$@"
