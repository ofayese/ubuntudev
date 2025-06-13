#!/usr/bin/env bash
# util-robust.sh - Robust installation utilities
# Version: 2.0.0
# Last updated: 2025-06-13
set -euo pipefail

# Enhanced network operations with retry logic
safe_network_operation() {
    local operation="$1"
    local url="$2"
    local output_file="${3:-}"
    local max_retries="${4:-3}"
    local timeout="${5:-30}"

    local attempt=1
    local backoff=2

    while [[ $attempt -le $max_retries ]]; do
        log_debug "Network operation attempt $attempt/$max_retries: $operation"

        case "$operation" in
        "download")
            if timeout "$timeout" curl -fsSL --connect-timeout 10 --max-time "$timeout" \
                --retry 2 --retry-delay 1 -o "$output_file" "$url"; then
                return 0
            fi
            ;;
        "test")
            if timeout "$timeout" curl -fsSL --connect-timeout 5 --max-time 10 \
                --head "$url" >/dev/null 2>&1; then
                return 0
            fi
            ;;
        *)
            log_error "Unknown network operation: $operation"
            return 1
            ;;
        esac

        local wait_time=$((backoff ** attempt))
        log_warning "Network operation failed (attempt $attempt/$max_retries), retrying in ${wait_time}s..."
        sleep "$wait_time"
        ((attempt++))
    done

    log_error "Network operation failed after $max_retries attempts: $operation $url"
    return 1
}

# Safe package installation with comprehensive error handling
safe_package_install() {
    local packages=("$@")
    local failed_packages=()
    local installed_packages=()

    # Validate package names
    for pkg in "${packages[@]}"; do
        if [[ ! "$pkg" =~ ^[a-zA-Z0-9._+-]+$ ]]; then
            log_warning "Invalid package name: $pkg (skipping)"
            failed_packages+=("$pkg")
            continue
        fi
    done

    # Update package index with retry
    update_package_index || {
        log_error "Failed to update package index"
        return 1
    }

    # Install packages individually for better error handling
    for pkg in "${packages[@]}"; do
        [[ " ${failed_packages[*]} " =~ " $pkg " ]] && continue

        log_info "Installing package: $pkg"

        if install_single_package "$pkg"; then
            installed_packages+=("$pkg")
            log_success "Successfully installed: $pkg"
        else
            failed_packages+=("$pkg")
            log_warning "Failed to install: $pkg"
        fi
    done

    # Report results
    if [[ ${#installed_packages[@]} -gt 0 ]]; then
        log_info "Successfully installed ${#installed_packages[@]} packages"
    fi

    if [[ ${#failed_packages[@]} -gt 0 ]]; then
        log_warning "Failed to install ${#failed_packages[@]} packages: ${failed_packages[*]}"
        return 1
    fi

    return 0
}

# Install single package with retry logic
install_single_package() {
    local pkg="$1"
    local max_attempts=3
    local attempt=1

    # Check if already installed
    if is_package_installed "$pkg"; then
        log_debug "Package already installed: $pkg"
        return 0
    fi

    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Installing $pkg (attempt $attempt/$max_attempts)"

        if timeout 300 sudo -E env DEBIAN_FRONTEND=noninteractive \
            apt-get install -y \
            -o DPkg::Lock::Timeout=30 \
            -o APT::Get::AllowUnauthenticated=false \
            -o APT::Install-Recommends=false \
            "$pkg" >/dev/null 2>&1; then
            return 0
        else
            local exit_code=$?
            log_debug "Installation attempt $attempt failed for $pkg (exit code: $exit_code)"

            if [[ $attempt -lt $max_attempts ]]; then
                # Try to fix common issues before retry
                case $exit_code in
                100)
                    log_debug "Fixing broken packages before retry"
                    sudo apt-get install -f -y >/dev/null 2>&1 || true
                    ;;
                2)
                    log_debug "Updating package index before retry"
                    sudo apt-get update >/dev/null 2>&1 || true
                    ;;
                esac

                sleep $((attempt * 2))
            fi

            ((attempt++))
        fi
    done

    log_debug "Failed to install $pkg after $max_attempts attempts"
    return 1
}

# Check if package is installed
is_package_installed() {
    local pkg="$1"
    dpkg -l "$pkg" 2>/dev/null | grep -q "^ii " 2>/dev/null
}

# Update package index with retry
update_package_index() {
    local max_attempts=3
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Updating package index (attempt $attempt/$max_attempts)"

        if timeout 120 sudo apt-get update >/dev/null 2>&1; then
            log_debug "Package index updated successfully"
            return 0
        else
            log_warning "Package index update attempt $attempt failed"

            if [[ $attempt -lt $max_attempts ]]; then
                sleep $((attempt * 5))
            fi

            ((attempt++))
        fi
    done

    log_error "Failed to update package index after $max_attempts attempts"
    return 1
}

# Resource validation
check_system_resources() {
    local min_disk_gb="${1:-2}"
    local min_memory_gb="${2:-1}"

    local issues=()

    # Check disk space
    local available_gb
    available_gb=$(df -BG / | awk 'NR==2 {gsub("G","",$4); print $4}')
    if [[ ${available_gb:-0} -lt $min_disk_gb ]]; then
        issues+=("Insufficient disk space: ${available_gb}GB (need ${min_disk_gb}GB+)")
    fi

    # Check memory
    local memory_gb
    memory_gb=$(free -g | awk '/^Mem:/ {print $2}')
    if [[ ${memory_gb:-0} -lt $min_memory_gb ]]; then
        issues+=("Low memory: ${memory_gb}GB (${min_memory_gb}GB+ recommended)")
    fi

    # Check load average
    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    local cpu_cores
    cpu_cores=$(nproc)

    if (($(echo "$load_avg > ($cpu_cores * 2)" | bc -l 2>/dev/null || echo 0))); then
        issues+=("High system load: $load_avg (${cpu_cores} cores)")
    fi

    # Report issues
    if [[ ${#issues[@]} -gt 0 ]]; then
        log_warning "System resource concerns:"
        for issue in "${issues[@]}"; do
            log_warning "  - $issue"
        done
        return 1
    fi

    return 0
}

# Enhanced error categorization
categorize_error() {
    local exit_code="$1"
    local error_output="${2:-}"

    case $exit_code in
    124) echo "timeout" ;;
    1 | 2)
        if [[ "$error_output" =~ "network"||"connection"||"timeout" ]]; then
            echo "network"
        elif [[ "$error_output" =~ "space"||"disk" ]]; then
            echo "disk_space"
        elif [[ "$error_output" =~ "lock"||"dpkg" ]]; then
            echo "package_lock"
        else
            echo "general"
        fi
        ;;
    126) echo "permission" ;;
    127) echo "command_not_found" ;;
    *) echo "unknown" ;;
    esac
}

# Provide error-specific recovery suggestions
suggest_error_recovery() {
    local error_category="$1"

    case "$error_category" in
    "network")
        log_info "Network error recovery suggestions:"
        log_info "  1. Check internet connectivity: ping -c 3 8.8.8.8"
        log_info "  2. Check DNS resolution: nslookup google.com"
        log_info "  3. Try different network or disable VPN"
        log_info "  4. Configure proxy if in corporate environment"
        ;;
    "disk_space")
        log_info "Disk space error recovery suggestions:"
        log_info "  1. Clean package cache: sudo apt clean"
        log_info "  2. Remove old packages: sudo apt autoremove"
        log_info "  3. Clean logs: sudo journalctl --vacuum-time=7d"
        log_info "  4. Check disk usage: df -h && du -sh /* 2>/dev/null | sort -hr"
        ;;
    "package_lock")
        log_info "Package lock error recovery suggestions:"
        log_info "  1. Wait for other package operations to complete"
        log_info "  2. Kill apt processes: sudo killall apt apt-get"
        log_info "  3. Remove lock files: sudo rm /var/lib/dpkg/lock*"
        log_info "  4. Fix broken packages: sudo dpkg --configure -a"
        ;;
    "permission")
        log_info "Permission error recovery suggestions:"
        log_info "  1. Check sudo access: sudo -v"
        log_info "  2. Verify user groups: groups \$USER"
        log_info "  3. Check file ownership: ls -la"
        ;;
    "timeout")
        log_info "Timeout error recovery suggestions:"
        log_info "  1. Check system load: top"
        log_info "  2. Check network speed: speedtest-cli"
        log_info "  3. Try again during off-peak hours"
        log_info "  4. Increase timeout values"
        ;;
    *)
        log_info "General recovery suggestions:"
        log_info "  1. Check system logs: journalctl -xe"
        log_info "  2. Verify system integrity: sudo apt-get check"
        log_info "  3. Update package lists: sudo apt-get update"
        log_info "  4. Try manual installation of failed components"
        ;;
    esac
}

# Simple progress indicator
show_progress() {
    local current="$1"
    local total="$2"
    local title="${3:-Progress}"

    if [[ -t 1 ]]; then # Only show in interactive terminal
        local percentage=$((current * 100 / total))
        local width=50
        local completed=$((width * current / total))
        local remaining=$((width - completed))

        printf "\r%s: [%s%s] %d%% (%d/%d)" \
            "$title" \
            "$(printf "%${completed}s" | tr ' ' '#')" \
            "$(printf "%${remaining}s")" \
            "$percentage" \
            "$current" \
            "$total"

        # Add newline when complete
        [[ $current -eq $total ]] && echo
    fi
}

# Cleanup function for temporary resources
cleanup_temp_resources() {
    # Clean up temporary files
    local temp_patterns=("/tmp/ubuntu-devtools-*" "/tmp/install-*" "/tmp/setup-*")
    for pattern in "${temp_patterns[@]}"; do
        # shellcheck disable=SC2086
        rm -f $pattern 2>/dev/null || true
    done

    # Kill any background jobs we might have started
    local bg_jobs
    bg_jobs=$(jobs -p 2>/dev/null || true)
    if [[ -n "$bg_jobs" ]]; then
        # shellcheck disable=SC2086
        kill $bg_jobs 2>/dev/null || true
    fi
}

# Export functions for use by other scripts
export -f safe_network_operation
export -f safe_package_install
export -f install_single_package
export -f is_package_installed
export -f update_package_index
export -f check_system_resources
export -f categorize_error
export -f suggest_error_recovery
export -f show_progress
export -f cleanup_temp_resources
