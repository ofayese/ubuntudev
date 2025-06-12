#!/usr/bin/env bash
# check-prerequisites.sh - Verify system requirements for installation
set -euo pipefail

# Source utility modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-log.sh"
source "$SCRIPT_DIR/util-env.sh"

# Initialize logging
init_logging
log_info "Prerequisites check started"

# Define prerequisite checks for progress tracking
declare -a PREREQ_CHECKS=(
  "root_check"
  "sudo_privileges"
  "internet_connectivity"
  "ubuntu_version"
  "disk_space"
  "essential_commands"
  "apt_functionality"
  "environment_detection"
  "memory_check"
)

PREREQUISITES_MET=true
current_check=0
total_checks=${#PREREQ_CHECKS[@]}

# Check 1: Root user check
((current_check++))
log_info "[$current_check/$total_checks] Checking user privileges..."
show_progress "$current_check" "$total_checks" "Prerequisites Check"

if [[ $EUID -eq 0 ]]; then
   log_warning "Running as root is not recommended. Please run as a regular user with sudo privileges."
fi

# Check 2: Sudo privileges
((current_check++))
log_info "[$current_check/$total_checks] Checking sudo privileges..."
show_progress "$current_check" "$total_checks" "Prerequisites Check"

if ! sudo -n true 2>/dev/null; then
    log_warning "sudo privileges are required for package installation"
    if ! sudo -v; then
        log_error "Failed to obtain sudo privileges"
        PREREQUISITES_MET=false
    fi
fi

# Check 3: Internet connectivity
((current_check++))
log_info "[$current_check/$total_checks] Checking internet connectivity..."
show_progress "$current_check" "$total_checks" "Prerequisites Check"

if ping -c 1 google.com >/dev/null 2>&1; then
    log_success "Internet connectivity confirmed"
else
    log_error "No internet connectivity - required for package downloads"
    PREREQUISITES_MET=false
fi

# Check 4: Ubuntu version
((current_check++))
log_info "[$current_check/$total_checks] Checking Ubuntu version..."
show_progress "$current_check" "$total_checks" "Prerequisites Check"

ubuntu_version=$(get_ubuntu_version)

if [[ "$ubuntu_version" == "non-ubuntu" ]]; then
    log_warning "Non-Ubuntu distribution detected. Some features may not work."
elif [[ "$ubuntu_version" == "unknown" ]]; then
    log_warning "Unable to determine Ubuntu version"
else
    log_success "Ubuntu $ubuntu_version detected"
    
    # Check if version is supported (20.04+)
    VERSION_MAJOR=$(echo "$ubuntu_version" | cut -d. -f1)
    VERSION_MINOR=$(echo "$ubuntu_version" | cut -d. -f2)
    
    if [[ "$VERSION_MAJOR" -gt 20 ]] || [[ "$VERSION_MAJOR" -eq 20 && "$VERSION_MINOR" -ge 4 ]]; then
        log_success "Ubuntu version is supported"
    else
        log_warning "Ubuntu $ubuntu_version may not be fully supported (recommended: 20.04+)"
    fi
fi

# Check 5: Available disk space
((current_check++))
log_info "[$current_check/$total_checks] Checking available disk space..."
show_progress "$current_check" "$total_checks" "Prerequisites Check"

AVAILABLE_SPACE_GB=$(get_available_disk)

if [[ "$AVAILABLE_SPACE_GB" -ge 5 ]]; then
    log_success "Sufficient disk space available: ${AVAILABLE_SPACE_GB}GB"
else
    log_warning "Low disk space: ${AVAILABLE_SPACE_GB}GB available (5GB+ recommended)"
fi

# Check 6: Essential commands
((current_check++))
log_info "[$current_check/$total_checks] Checking essential commands..."
show_progress "$current_check" "$total_checks" "Prerequisites Check"

ESSENTIAL_COMMANDS=("curl" "wget" "git" "sudo" "bc")

for cmd in "${ESSENTIAL_COMMANDS[@]}"; do
    if command_exists "$cmd"; then
        log_success "$cmd is available"
    else
        log_error "$cmd is not available"
        PREREQUISITES_MET=false
    fi
done

# Check 7: APT functionality
((current_check++))
log_info "[$current_check/$total_checks] Testing apt update..."
show_progress "$current_check" "$total_checks" "Prerequisites Check"

if sudo apt update >/dev/null 2>&1; then
    log_success "apt update successful"
else
    log_error "apt update failed - check network and repository configuration"
    PREREQUISITES_MET=false
fi

# Check 8: Environment detection
((current_check++))
log_info "[$current_check/$total_checks] Environment detection..."
show_progress "$current_check" "$total_checks" "Prerequisites Check"

ENV_TYPE=$(detect_environment)

if [[ "$ENV_TYPE" == "$ENV_WSL" ]]; then
    log_success "WSL environment detected"
    
    # Check WSL version
    wsl_version=$(get_wsl_version)
    if [[ "$wsl_version" == "2" ]]; then
        log_success "WSL2 environment confirmed"
        
        if ! is_systemd_running; then
            log_warning "systemd is not running - add 'systemd=true' to /etc/wsl.conf and restart WSL"
        else
            log_success "systemd is running"
        fi
    else
        log_warning "WSL1 detected - some features require WSL2"
    fi
elif [[ "$ENV_TYPE" == "$ENV_DESKTOP" ]]; then
    log_success "Desktop environment detected"
else
    log_success "Headless environment detected"
fi

# Check 9: Memory
((current_check++))
log_info "[$current_check/$total_checks] Checking available memory..."
show_progress "$current_check" "$total_checks" "Prerequisites Check"

mem_available=$(get_available_memory)
log_info "Available memory: ${mem_available}GB"
if (( $(echo "$mem_available < 2" | bc -l) )); then
    log_warning "Low memory available: ${mem_available}GB (2GB+ recommended)"
fi

# Final summary
echo ""
log_info "Prerequisites Check Summary:"
if $PREREQUISITES_MET; then
    show_completion_summary "PREREQUISITES CHECK" "" "SUCCESS"
    log_success "All prerequisites met! You can proceed with installation."
    finish_logging
    exit 0
else
    show_completion_summary "PREREQUISITES CHECK" "" "FAILED"
    log_error "Some prerequisites are not met. Please address the issues above before proceeding."
    finish_logging
    exit 1
fi

