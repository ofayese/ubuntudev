#!/usr/bin/env bash
# check-prerequisites.sh - Verify system requirements for installation
set -euo pipefail

# Source utility modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-log.sh"
source "$SCRIPT_DIR/util-env.sh"

# Configuration section - make all thresholds configurable
readonly SUDO_TIMEOUT="${SUDO_TIMEOUT:-30}"
readonly NETWORK_TIMEOUT="${NETWORK_TIMEOUT:-10}"
readonly APT_TIMEOUT="${APT_TIMEOUT:-60}"
readonly MIN_DISK_SPACE_GB="${MIN_DISK_SPACE_GB:-5}"
readonly MIN_MEMORY_GB="${MIN_MEMORY_GB:-2}"
readonly MIN_UBUNTU_VERSION_MAJOR="${MIN_UBUNTU_VERSION_MAJOR:-20}"
readonly MIN_UBUNTU_VERSION_MINOR="${MIN_UBUNTU_VERSION_MINOR:-4}"

# Recovery suggestions mapping
declare -A RECOVERY_SUGGESTIONS=(
    ["root_check"]="Please run as a regular user with sudo privileges instead."
    ["sudo_privileges"]="Install sudo: apt update && apt install sudo; Add user to sudo group: usermod -aG sudo \$USER"
    ["internet_connectivity"]="Check network: ping 8.8.8.8; Configure proxy: export HTTP_PROXY=http://proxy:port; Check DNS: cat /etc/resolv.conf"
    ["ubuntu_version"]="Upgrade Ubuntu: do-release-upgrade; Check version: lsb_release -a"
    ["disk_space"]="Free space: apt autoremove && apt autoclean; Check usage: df -h; Clean logs: journalctl --vacuum-time=7d"
    ["essential_commands"]="Install essentials: apt update && apt install curl wget git sudo bc"
    ["apt_functionality"]="Fix apt: apt --fix-broken install; Update sources: apt update; Check sources: cat /etc/apt/sources.list"
    ["memory_check"]="Free memory: sync && echo 3 > /proc/sys/vm/drop_caches; Check processes: top; Consider swap: swapon -s"
    ["cpu_architecture"]="For ARM64: Use ARM64-compatible packages; For x86: Check CPU virtualization support"
)

# Global variables for check execution
SKIP_CHECKS=()
ONLY_CHECKS=()
SHOW_REQUIREMENTS=false
FORCE_CONTINUE=false
declare -A CHECK_RESULTS

# Load configuration from file if available
if [[ -f "${SCRIPT_DIR}/prerequisites.conf" ]]; then
    log_info "Loading configuration from prerequisites.conf"
    source "${SCRIPT_DIR}/prerequisites.conf"
fi

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
    "cpu_architecture"
)

PREREQUISITES_MET=true
current_check=0
total_checks=${#PREREQ_CHECKS[@]}

# Display configuration
log_info "Using configuration: Disk=${MIN_DISK_SPACE_GB}GB, Memory=${MIN_MEMORY_GB}GB, Network Timeout=${NETWORK_TIMEOUT}s"

# Command line argument parsing for selective checks
parse_arguments() {
    local skip_checks=()
    local only_checks=()
    local show_requirements=false
    local force_continue=false

    while [[ $# -gt 0 ]]; do
        case $1 in
        --skip)
            IFS=',' read -ra skip_checks <<<"$2"
            shift 2
            ;;
        --only)
            IFS=',' read -ra only_checks <<<"$2"
            shift 2
            ;;
        --requirements)
            show_requirements=true
            shift
            ;;
        --force)
            force_continue=true
            shift
            ;;
        --help | -h)
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

    # Set global variables for check execution
    SKIP_CHECKS=("${skip_checks[@]}")
    ONLY_CHECKS=("${only_checks[@]}")
    SHOW_REQUIREMENTS="$show_requirements"
    FORCE_CONTINUE="$force_continue"
}

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Verify system requirements for Ubuntu development environment installation.

Options:
    --skip CHECKS       Skip specific checks (comma-separated)
                        Available: $(
        IFS=','
        echo "${PREREQ_CHECKS[*]}"
    )
    --only CHECKS       Run only specific checks (comma-separated)
    --requirements      Show detailed requirements information
    --force             Continue even if prerequisites are not met
    --help              Show this help message

Examples:
    $0                                    # Run all checks
    $0 --skip internet_connectivity       # Skip network check
    $0 --only sudo_privileges,disk_space  # Check only sudo and disk
    $0 --requirements                     # Show what's required
    $0 --force                            # Continue despite failures

EOF
}

# Detailed requirements documentation
show_detailed_requirements() {
    cat <<EOF
📋 Ubuntu Development Environment Prerequisites

System Requirements:
┌───────────────────┬───────────────────────┬───────────────────────┐
│ Component         │ Requirement           │ Purpose               │
├───────────────────┼───────────────────────┼───────────────────────┤
│ Ubuntu Version    │ ${MIN_UBUNTU_VERSION_MAJOR}.${MIN_UBUNTU_VERSION_MINOR} LTS or newer     │ Package compatibility │
│ Disk Space        │ ${MIN_DISK_SPACE_GB}GB available       │ Software installation │
│ Memory            │ ${MIN_MEMORY_GB}GB available       │ Build processes       │
│ Network           │ Internet connectivity  │ Package downloads     │
│ Privileges        │ sudo access            │ System modifications  │
│ Essential Commands│ curl, wget, git, bc    │ Setup operations      │
│ Package Manager   │ apt functionality      │ Software installation │
│ CPU Architecture  │ x86_64/ARM64 preferred │ Compatibility         │
└───────────────────┴───────────────────────┴───────────────────────┘

Environment Support:
• WSL2 (Windows Subsystem for Linux 2)
• Ubuntu Desktop (with GUI)
• Ubuntu Server (headless)

Optional Components:
• systemd (recommended for WSL2)
• Snap package manager (for additional software)

Network Requirements:
• Access to Ubuntu package repositories
• GitHub connectivity (for development tools)
• DNS resolution capability
• Proxy support (if in corporate environment)

EOF
}

# Abstract check execution pattern
execute_prerequisite_check() {
    local check_name="$1"
    local check_description="$2"
    local check_function="$3"
    local is_critical="${4:-true}"

    # Skip check if in SKIP_CHECKS or not in ONLY_CHECKS when specified
    if [[ " ${SKIP_CHECKS[*]} " == *" $check_name "* ]]; then
        log_info "Skipping $check_description (--skip option)"
        CHECK_RESULTS["$check_name"]="SKIPPED"
        return 0
    fi

    if [[ ${#ONLY_CHECKS[@]} -gt 0 ]] && [[ ! " ${ONLY_CHECKS[*]} " == *" $check_name "* ]]; then
        log_info "Skipping $check_description (not in --only list)"
        CHECK_RESULTS["$check_name"]="SKIPPED"
        return 0
    fi

    current_check=$((current_check + 1))
    log_info "[$current_check/$total_checks] $check_description..."
    show_progress "$current_check" "$total_checks" "Prerequisites Check"

    local check_start_time
    check_start_time=$(date +%s)

    if "$check_function"; then
        local duration=$(($(date +%s) - check_start_time))
        log_success "$check_description completed (${duration}s)"
        CHECK_RESULTS["$check_name"]="SUCCESS"
        return 0
    else
        local duration=$(($(date +%s) - check_start_time))
        if [[ "$is_critical" == "true" ]]; then
            log_error "$check_description failed (${duration}s)"
            CHECK_RESULTS["$check_name"]="FAILED"
            PREREQUISITES_MET=false
        else
            log_warning "$check_description failed but not critical (${duration}s)"
            CHECK_RESULTS["$check_name"]="WARNING"
        fi
        return 1
    fi
}

# Enhanced error reporting with recovery suggestions
report_check_failure() {
    local check_name="$1"
    local error_message="$2"

    log_error "$error_message"

    if [[ -n "${RECOVERY_SUGGESTIONS[$check_name]:-}" ]]; then
        log_info "Recovery suggestions for $check_name:"
        IFS=';' read -ra suggestions <<<"${RECOVERY_SUGGESTIONS[$check_name]}"
        for suggestion in "${suggestions[@]}"; do
            log_info "  → $suggestion"
        done
    fi

    # Provide context-specific additional help
    case "$check_name" in
    "sudo_privileges")
        if [[ "$ENV_TYPE" == "$ENV_WSL" ]]; then
            log_info "WSL-specific help:"
            log_info "  → Restart WSL: wsl --shutdown (from Windows)"
            log_info "  → Check WSL user: whoami"
        fi
        ;;
    "internet_connectivity")
        log_info "Network diagnostics:"
        log_info "  → Test DNS: nslookup google.com"
        log_info "  → Check routes: ip route show"
        log_info "  → Corporate networks may require proxy configuration"
        ;;
    "apt_functionality")
        log_info "APT troubleshooting:"
        log_info "  → Check disk space: df -h /"
        log_info "  → Verify repository access: apt-cache policy"
        log_info "  → Reset apt cache: rm -rf /var/lib/apt/lists/* && apt update"
        ;;
    esac
}

# Check 1: Root user check
check_root_user() {
    if [[ $EUID -eq 0 ]]; then
        log_warning "Running as root is not recommended. Please run as a regular user with sudo privileges."
        return 1
    fi
    return 0
}

# Check 2: Sudo privileges
check_sudo_privileges() {
    log_info "Testing sudo without password prompt..."
    if ! timeout "$SUDO_TIMEOUT" sudo -n true 2>/dev/null; then
        log_warning "sudo privileges are required for package installation"
        log_info "Requesting sudo password (timeout: ${SUDO_TIMEOUT} seconds)..."
        if ! timeout "$SUDO_TIMEOUT" sudo -v 2>/dev/null; then
            report_check_failure "sudo_privileges" "Failed to obtain sudo privileges or timed out"
            return 1
        else
            log_success "sudo privileges confirmed"
            return 0
        fi
    else
        log_success "sudo privileges available (no password required)"
        return 0
    fi
}

# Check 3: Internet connectivity with robust testing
check_internet_connectivity() {
    log_info "Testing internet connectivity (timeout: ${NETWORK_TIMEOUT} seconds)..."

    # Define multiple test targets for comprehensive connectivity testing
    local connectivity_targets=(
        "8.8.8.8"            # Google DNS
        "1.1.1.1"            # Cloudflare DNS
        "archive.ubuntu.com" # Ubuntu package repository
        "github.com"         # Development platform
        "microsoft.com"      # Enterprise-friendly target
    )

    local proxy_config=""
    if [[ -n "${HTTP_PROXY:-}" ]] || [[ -n "${http_proxy:-}" ]]; then
        proxy_config="--proxy ${HTTP_PROXY:-$http_proxy}"
        log_info "Proxy configuration detected: ${HTTP_PROXY:-$http_proxy}"
    fi

    local successful_connections=0
    local connection_details=()

    for target in "${connectivity_targets[@]}"; do
        local test_method="ping"
        local test_command="timeout ${NETWORK_TIMEOUT} ping -c 1 -W 3 $target"

        # For HTTP targets, use curl if available
        if [[ "$target" =~ \.(com|org|net)$ ]] && command -v curl >/dev/null 2>&1; then
            test_method="http"
            test_command="timeout ${NETWORK_TIMEOUT} curl -sf $proxy_config --connect-timeout 5 --max-time ${NETWORK_TIMEOUT} -I https://$target"
        fi

        if eval "$test_command" >/dev/null 2>&1; then
            ((successful_connections++))
            connection_details+=("✓ $target ($test_method)")
            log_info "Connection successful: $target"
        else
            connection_details+=("✗ $target ($test_method)")
            log_warning "Connection failed: $target"
        fi
    done

    # Evaluate connectivity based on successful connections
    if [[ $successful_connections -eq 0 ]]; then
        log_error "No internet connectivity detected"
        log_info "Connection test results:"
        printf '%s\n' "${connection_details[@]}" | while read -r line; do log_info "  $line"; done

        # Provide troubleshooting guidance
        report_check_failure "internet_connectivity" "No internet connectivity - required for package downloads"
        return 1
    elif [[ $successful_connections -lt 3 ]]; then
        log_warning "Limited internet connectivity ($successful_connections/${#connectivity_targets[@]} targets reachable)"
        log_info "This may cause issues with package downloads"
        return 0
    else
        log_success "Internet connectivity confirmed ($successful_connections/${#connectivity_targets[@]} targets reachable)"
        return 0
    fi
}

# Check 4: Ubuntu version with enhanced version comparison
check_ubuntu_version() {
    ubuntu_version=$(get_ubuntu_version)

    if [[ "$ubuntu_version" == "non-ubuntu" ]]; then
        log_warning "Non-Ubuntu distribution detected. Some features may not work."
        log_info "Supported distributions: Ubuntu ${MIN_UBUNTU_VERSION_MAJOR}.${MIN_UBUNTU_VERSION_MINOR}+, Linux Mint 20+"
        log_info "Detected distribution: $(lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown")"
        return 0 # Non-critical for some use cases
    elif [[ "$ubuntu_version" == "unknown" ]]; then
        log_warning "Unable to determine Ubuntu version"
        report_check_failure "ubuntu_version" "Version detection failed"
        return 1
    else
        log_success "Ubuntu $ubuntu_version detected"

        # Enhanced version comparison
        local version_major version_minor
        version_major=$(echo "$ubuntu_version" | cut -d. -f1)
        version_minor=$(echo "$ubuntu_version" | cut -d. -f2)

        if [[ "$version_major" -lt "$MIN_UBUNTU_VERSION_MAJOR" ]] ||
            [[ "$version_major" -eq "$MIN_UBUNTU_VERSION_MAJOR" && "$version_minor" -lt "$MIN_UBUNTU_VERSION_MINOR" ]]; then
            log_error "Ubuntu $ubuntu_version is not supported (minimum: ${MIN_UBUNTU_VERSION_MAJOR}.${MIN_UBUNTU_VERSION_MINOR})"
            report_check_failure "ubuntu_version" "Unsupported Ubuntu version"
            return 1
        else
            log_success "Ubuntu version is supported"
            return 0
        fi
    fi
}

# Check 5: Available disk space with threshold comparison
check_disk_space() {
    AVAILABLE_SPACE_GB=$(get_available_disk)

    if [[ "$AVAILABLE_SPACE_GB" -ge "$MIN_DISK_SPACE_GB" ]]; then
        log_success "Sufficient disk space available: ${AVAILABLE_SPACE_GB}GB"
        return 0
    else
        log_warning "Low disk space: ${AVAILABLE_SPACE_GB}GB available (${MIN_DISK_SPACE_GB}GB+ recommended)"
        report_check_failure "disk_space" "Insufficient disk space"
        return 1
    fi
}

# Check 6: Essential commands with comprehensive reporting
check_essential_commands() {
    ESSENTIAL_COMMANDS=("curl" "wget" "git" "sudo" "bc")
    local missing_commands=()
    local all_commands_available=true

    for cmd in "${ESSENTIAL_COMMANDS[@]}"; do
        if command_exists "$cmd"; then
            log_success "$cmd is available"
        else
            log_error "$cmd is not available"
            missing_commands+=("$cmd")
            all_commands_available=false
        fi
    done

    if ! $all_commands_available; then
        log_error "Missing essential commands: ${missing_commands[*]}"
        log_info "You can install missing commands with:"
        log_info "  sudo apt update && sudo apt install ${missing_commands[*]}"
        return 1
    fi

    return 0
}

# Check 7: APT functionality with proper error handling
check_apt_functionality() {
    log_info "Running apt update (timeout: ${APT_TIMEOUT} seconds)..."

    # Create a temporary file for apt output
    local apt_output
    apt_output=$(mktemp)

    if timeout "$APT_TIMEOUT" sudo apt update >"$apt_output" 2>&1; then
        log_success "apt update successful"
        rm -f "$apt_output"
        return 0
    else
        local exit_code=$?
        log_error "apt update failed or timed out (exit code: $exit_code)"

        # Extract and log useful error information
        if [[ -f "$apt_output" ]]; then
            log_info "APT error details:"
            grep -i "err\|fail\|could not\|problem" "$apt_output" | while read -r line; do
                log_info "  $line"
            done
            rm -f "$apt_output"
        fi

        report_check_failure "apt_functionality" "apt update failed - check network and repository configuration"
        return 1
    fi
}

# Check 8: Environment detection with specific recommendations
check_environment() {
    ENV_TYPE=$(detect_environment)

    if [[ "$ENV_TYPE" == "$ENV_WSL" ]]; then
        log_success "WSL environment detected"

        # Check WSL version
        wsl_version=$(get_wsl_version)
        if [[ "$wsl_version" == "2" ]]; then
            log_success "WSL2 environment confirmed"

            if ! is_systemd_running; then
                log_warning "systemd is not running in WSL2"
                log_info "To enable systemd in WSL2:"
                log_info "  1. Create or edit /etc/wsl.conf:"
                log_info "     sudo tee /etc/wsl.conf > /dev/null << EOF"
                log_info "     [boot]"
                log_info "     systemd=true"
                log_info "     EOF"
                log_info "  2. Restart WSL from PowerShell: wsl --shutdown"
                return 1
            else
                log_success "systemd is running"
            fi
        else
            log_warning "WSL1 detected - some features require WSL2"
            log_info "To upgrade to WSL2 from Windows:"
            log_info "  1. Run in PowerShell: wsl --set-version Ubuntu 2"
            log_info "  2. Set WSL2 as default: wsl --set-default-version 2"
            return 1
        fi
    elif [[ "$ENV_TYPE" == "$ENV_DESKTOP" ]]; then
        log_success "Desktop environment detected"
        # Check for recommended desktop packages
        if ! command_exists "gnome-terminal" && ! command_exists "konsole"; then
            log_warning "No standard terminal emulator detected"
            log_info "Consider installing: sudo apt install gnome-terminal"
        fi
    else
        log_success "Headless environment detected"
        # Check for server-specific recommendations
        if [[ -f /etc/systemd/system/multi-user.target.wants/snapd.service ]] && ! command_exists snap; then
            log_warning "Snap service enabled but snap command not available"
            log_info "Consider installing: sudo apt install snapd"
        fi
    fi

    return 0
}

# Check 9: Memory with threshold comparison and specific recommendations
check_memory() {
    mem_available=$(get_available_memory)
    log_info "Available memory: ${mem_available}GB"

    if (($(echo "$mem_available < $MIN_MEMORY_GB" | bc -l))); then
        log_warning "Low memory available: ${mem_available}GB (${MIN_MEMORY_GB}GB+ recommended)"

        # Check for memory-related optimizations
        if [[ "$ENV_TYPE" == "$ENV_WSL" ]]; then
            log_info "WSL memory optimization suggestions:"
            log_info "  1. Add to .wslconfig in Windows user profile:"
            log_info "     [wsl2]"
            log_info "     memory=${MIN_MEMORY_GB}GB"
            log_info "  2. Restart WSL: wsl --shutdown"
        else
            log_info "Memory optimization suggestions:"
            log_info "  1. Close unnecessary applications"
            log_info "  2. Add or increase swap: sudo fallocate -l 2G /swapfile"
            log_info "  3. Format and enable swap:"
            log_info "     sudo chmod 600 /swapfile"
            log_info "     sudo mkswap /swapfile"
            log_info "     sudo swapon /swapfile"
        fi

        return 1
    fi

    return 0
}

# Enhanced final summary with actionable information
generate_final_summary() {
    local failed_checks=()
    local warnings=()
    local recommendations=()

    echo ""
    echo "🔍 Prerequisites Check Complete"
    echo "════════════════════════════════════════════════════════════════"

    # Categorize results
    for check in "${PREREQ_CHECKS[@]}"; do
        if [[ -n "${CHECK_RESULTS[$check]:-}" ]]; then
            case "${CHECK_RESULTS[$check]}" in
            "FAILED")
                failed_checks+=("$check")
                ;;
            "WARNING")
                warnings+=("$check")
                ;;
            "SUCCESS" | "SKIPPED")
                # Nothing to do for successful checks
                ;;
            esac
        fi
    done

    # Calculate statistics safely
    local passed_count
    passed_count=$((${#PREREQ_CHECKS[@]} - ${#failed_checks[@]} - ${#warnings[@]}))

    # Display results summary
    echo "✅ Passed Checks: $passed_count"
    echo "⚠️  Warnings: ${#warnings[@]}"
    echo "❌ Failed Checks: ${#failed_checks[@]}"

    if [[ ${#warnings[@]} -gt 0 ]]; then
        echo ""
        echo "⚠️  Warnings (non-critical):"
        for warning in "${warnings[@]}"; do
            echo "   • $warning"
        done
    fi

    if [[ ${#failed_checks[@]} -gt 0 ]]; then
        echo ""
        echo "❌ Failed Prerequisites:"
        for failure in "${failed_checks[@]}"; do
            echo "   • $failure"
            if [[ -n "${RECOVERY_SUGGESTIONS[$failure]:-}" ]]; then
                echo "     Recovery: ${RECOVERY_SUGGESTIONS[$failure]%%';'*}..."
            fi
        done
        echo ""
        echo "📚 Run '$0 --help' for detailed recovery options"
    fi

    # Final recommendation
    if [[ "$PREREQUISITES_MET" == "true" ]] || [[ "$FORCE_CONTINUE" == "true" ]]; then
        echo ""
        echo "🚀 System is ready for Ubuntu development environment installation!"
        echo "   Next step: ./install-new.sh --all"
    else
        echo ""
        echo "🛠️  Please resolve the failed prerequisites before continuing."
        echo "   Use --force to override (not recommended)"
    fi

    echo "════════════════════════════════════════════════════════════════"
}

# Check CPU architecture compatibility
check_cpu_architecture() {
    local arch
    arch=$(uname -m)

    log_info "Detected CPU architecture: $arch"

    case "$arch" in
    x86_64)
        # Check for hardware virtualization support for Docker/VMs
        if command_exists grep && [[ -f /proc/cpuinfo ]]; then
            if grep -qE 'vmx|svm' /proc/cpuinfo; then
                log_success "CPU virtualization extensions detected (good for Docker/VMs)"
            else
                log_warning "CPU virtualization extensions not found - Docker/VMs may be slow"
                log_info "Check BIOS/UEFI settings to enable virtualization if supported"
            fi
        fi
        log_success "x86_64 architecture supported"
        return 0
        ;;
    aarch64 | arm64)
        log_success "ARM64 architecture detected"
        # Check for known ARM64 limitations
        if [[ "$ENV_TYPE" == "$ENV_WSL" ]]; then
            log_info "ARM64 on WSL: Some x86 tools may use emulation and run slower"
        fi
        return 0
        ;;
    i386 | i686)
        log_warning "32-bit x86 architecture detected"
        log_info "Some development tools may not be available for 32-bit systems"
        log_info "Consider upgrading to a 64-bit operating system if possible"
        return 1
        ;;
    *)
        log_warning "Unusual CPU architecture: $arch"
        log_info "Development tools may have limited support"
        log_info "Compatibility will be determined on a per-tool basis"
        return 1
        ;;
    esac
}

# Main function to run all checks
main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Show requirements if requested
    if [[ "$SHOW_REQUIREMENTS" == "true" ]]; then
        show_detailed_requirements
        exit 0
    fi

    # Execute all prerequisite checks
    execute_prerequisite_check "root_check" "Checking user privileges" check_root_user "false"
    execute_prerequisite_check "sudo_privileges" "Checking sudo privileges" check_sudo_privileges
    execute_prerequisite_check "internet_connectivity" "Checking internet connectivity" check_internet_connectivity
    execute_prerequisite_check "ubuntu_version" "Checking Ubuntu version" check_ubuntu_version
    execute_prerequisite_check "disk_space" "Checking available disk space" check_disk_space
    execute_prerequisite_check "essential_commands" "Checking essential commands" check_essential_commands
    execute_prerequisite_check "apt_functionality" "Testing apt update" check_apt_functionality
    execute_prerequisite_check "environment_detection" "Environment detection" check_environment "false"
    execute_prerequisite_check "memory_check" "Checking available memory" check_memory "false"
    execute_prerequisite_check "cpu_architecture" "Checking CPU architecture" check_cpu_architecture "false"

    # Generate final summary
    generate_final_summary

    # Determine exit status
    if [[ "$PREREQUISITES_MET" == "true" ]] || [[ "$FORCE_CONTINUE" == "true" ]]; then
        finish_logging
        exit 0
    else
        finish_logging
        exit 1
    fi
}

# Execute main function
main "$@"
