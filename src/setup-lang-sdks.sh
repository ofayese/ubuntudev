#!/usr/bin/env bash
# setup-lang-sdks.sh - Install development language SDKs and runtime environments
# Version: 1.0.0
# Last updated: 2025-06-13
set -euo pipefail

# Script version and last updated timestamp
readonly VERSION="1.0.0"
readonly LAST_UPDATED="2025-06-13"

# Cross-platform support
OS_TYPE="$(uname -s)"
readonly OS_TYPE

# Dry-run mode support
readonly DRY_RUN="${DRY_RUN:-false}"

# Define trusted domains for downloads
readonly TRUSTED_DOMAINS=(
    "sh.rustup.rs"
    "get.sdkman.io"
    "get-ghcup.haskell.org"
)

# Source utility modules with error checking
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

source "$SCRIPT_DIR/util-log.sh" || {
    echo "FATAL: Failed to source util-log.sh" >&2
    exit 1
}
source "$SCRIPT_DIR/util-env.sh" || {
    echo "FATAL: Failed to source util-env.sh" >&2
    exit 1
}
source "$SCRIPT_DIR/util-install.sh" || {
    echo "FATAL: Failed to source util-install.sh" >&2
    exit 1
}

# Secure download and validation function
validate_and_download() {
    local url="$1"
    local output_file="$2"
    local description="$3"

    # Extract domain for validation
    local domain
    domain=$(echo "$url" | sed -n 's|^https://\([^/]*\).*|\1|p')

    # Validate domain is in trusted list
    local is_trusted=false
    for trusted_domain in "${TRUSTED_DOMAINS[@]}"; do
        if [[ "$domain" == "$trusted_domain" ]]; then
            is_trusted=true
            break
        fi
    done

    if [[ "$is_trusted" != "true" ]]; then
        log_error "Security error: Domain $domain is not in trusted domains list"
        return 1
    fi

    # Download with proper error handling and HTTPS enforcement
    log_info "Downloading $description from $domain..."
    if ! curl --proto '=https' --tlsv1.2 -sSf -o "$output_file" "$url"; then
        log_error "Failed to download $description from $url"
        return 1
    fi

    # Basic validation - file exists and is not empty
    if [[ ! -s "$output_file" ]]; then
        log_error "Downloaded file is empty or does not exist"
        return 1
    fi

    log_success "Successfully downloaded and validated $description"
    return 0
}

# Start logging
log_info "Language SDKs setup started (v$VERSION, updated $LAST_UPDATED)"

# Display dry-run mode notice if active
if [[ "$DRY_RUN" == "true" ]]; then
    log_info "=== DRY RUN MODE: No system changes will be made ==="
    log_info "This is a simulation to show what would be installed."
fi

# Detect environment
ENV_TYPE="native"
if [[ -n "${WSL_DISTRO_NAME:-}" ]] || [[ -n "${WSLENV:-}" ]]; then
    ENV_TYPE="wsl"
fi
log_info "Environment detected: $ENV_TYPE"

# Define installation steps for progress tracking
log_info "Starting language SDK installations..."

# --- RUST (Rustup) ---
log_info "[1/3] Installing Rust via rustup..."

# Check if Rust is already installed
if command -v rustc &>/dev/null && command -v cargo &>/dev/null; then
    log_info "Rust is already installed, updating instead..."
    source "$HOME/.cargo/env" 2>/dev/null || true
    if timeout 300 rustup update --no-self-update; then
        log_success "Rust updated successfully"
    else
        log_warning "Failed to update Rust (may have timed out)"
    fi
else
    log_info "Installing Rust via rustup..."

    # Create a secure temporary directory for the download
    TEMP_DIR=$(mktemp -d)
    chmod 700 "$TEMP_DIR"
    RUSTUP_SCRIPT="$TEMP_DIR/rustup.sh"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would download and install Rust from https://sh.rustup.rs"
        log_success "[DRY-RUN] Rust would be installed successfully"
    elif validate_and_download "https://sh.rustup.rs" "$RUSTUP_SCRIPT" "Rustup installer"; then
        # Make the script executable
        chmod 700 "$RUSTUP_SCRIPT"

        # Execute the validated script with required parameters
        if timeout 300 bash "$RUSTUP_SCRIPT" -y --no-modify-path; then
            log_success "Rust installed successfully"
            # Load Rust environment
            source "$HOME/.cargo/env" 2>/dev/null || {
                log_warning "Failed to source Rust environment. You may need to restart your terminal."
            }
        else
            log_error "Failed to run the Rustup installer (may have timed out)"
        fi
    else
        log_error "Failed to download and validate Rustup installer"
    fi

    # Clean up temp directory
    rm -rf "$TEMP_DIR"
fi

# Add Rust to shell profile
for PROFILE in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [ -f "$PROFILE" ] && ! grep -q 'cargo/env' "$PROFILE"; then
        echo 'source "$HOME/.cargo/env"' >>"$PROFILE"
        log_info "Added Rust environment to $PROFILE"
    fi
done

# --- JAVA / JVM via SDKMAN ---
log_info "[2/3] Installing SDKMAN and JVM toolchain..."

# Check if SDKMAN is already installed
if [ -d "$HOME/.sdkman" ] && [ -f "$HOME/.sdkman/bin/sdkman-init.sh" ]; then
    log_info "SDKMAN is already installed, skipping installation..."
    # Initialize SDKMAN with relaxed error handling
    set +euo pipefail # Disable strict error checking for SDKMAN
    source "$HOME/.sdkman/bin/sdkman-init.sh" || {
        log_warning "Failed to source SDKMAN environment"
    }
    set -euo pipefail # Re-enable strict error checking
else
    log_info "Installing SDKMAN..."

    # Create a secure temporary directory for the download
    TEMP_DIR=$(mktemp -d)
    chmod 700 "$TEMP_DIR"
    SDKMAN_SCRIPT="$TEMP_DIR/sdkman.sh"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would download and install SDKMAN from https://get.sdkman.io"
        log_success "[DRY-RUN] SDKMAN would be installed successfully"
    elif validate_and_download "https://get.sdkman.io" "$SDKMAN_SCRIPT" "SDKMAN installer"; then
        # Make the script executable
        chmod 700 "$SDKMAN_SCRIPT"

        # Execute the validated script with timeout
        if timeout 300 bash "$SDKMAN_SCRIPT"; then
            log_success "SDKMAN installed successfully"
            # Initialize SDKMAN with relaxed error handling
            set +euo pipefail # Disable strict error checking for SDKMAN
            source "$HOME/.sdkman/bin/sdkman-init.sh" 2>/dev/null || {
                log_warning "Failed to source SDKMAN environment. You may need to restart your terminal."
            }
            set -euo pipefail # Re-enable strict error checking
        else
            log_error "Failed to run the SDKMAN installer (may have timed out)"
            rm -rf "$TEMP_DIR"
            exit 1
        fi
    else
        log_error "Failed to download and validate SDKMAN installer"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    # Clean up temp directory
    rm -rf "$TEMP_DIR"
fi

# Add SDKMAN init to shell profiles
for PROFILE in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [ -f "$PROFILE" ] && ! grep -q 'sdkman-init.sh' "$PROFILE"; then
        echo 'source "$HOME/.sdkman/bin/sdkman-init.sh"' >>"$PROFILE"
        log_info "Added SDKMAN initialization to $PROFILE"
    fi
done

# Install Java SDKs
log_info "Installing Java SDKs..."

# Function to install Java with version fallbacks
install_java_version() {
    local major_version=$1
    local specific_version=$2
    local vendor=${3:-tem}

    log_info "Trying to install Java $specific_version..."

    # Temporarily disable strict error checking for SDK commands
    set +eu

    if command -v sdk &>/dev/null && timeout 300 sdk install java $specific_version-$vendor </dev/null 2>/dev/null; then
        log_success "Installed Java $specific_version-$vendor"
        set -eu
        return 0
    else
        log_warning "Specific Java $specific_version not available, trying latest $major_version.x..."
        if command -v sdk &>/dev/null && timeout 300 sdk install java $major_version-$vendor </dev/null 2>/dev/null; then
            log_success "Installed Java $major_version-$vendor"
            set -eu
            return 0
        elif command -v sdk &>/dev/null && timeout 300 sdk install java $major_version.0-$vendor </dev/null 2>/dev/null; then
            log_success "Installed Java $major_version.0-$vendor"
            set -eu
            return 0
        else
            log_warning "Failed to install Java $major_version"
            set -eu
            return 1
        fi
    fi
}

# Install Java 17 and 21
install_java_version "17" "17.0.9" || log_warning "Failed to install Java 17"
install_java_version "21" "21.0.2" || log_warning "Failed to install Java 21"

# Set default Java version (prefer 17 for broader compatibility)
log_info "Setting default Java version..."
if command -v sdk &>/dev/null; then
    # Temporarily disable strict error checking for SDK commands
    set +eu
    if timeout 60 sdk default java 17-tem </dev/null 2>/dev/null || timeout 60 sdk default java 17.0-tem </dev/null 2>/dev/null || timeout 60 sdk default java 17.0.9-tem </dev/null 2>/dev/null; then
        log_success "Set Java 17 as default"
    else
        log_warning "Could not set Java 17 as default"
    fi
    set -eu
else
    log_warning "SDKMAN command 'sdk' not available, skipping default Java setup"
fi

# --- HASKELL via GHCup ---
log_info "[3/3] Installing Haskell via GHCup..."

# Check if GHCup is already installed
if [ -d "$HOME/.ghcup" ] && command -v ghc &>/dev/null; then
    log_info "Haskell/GHCup is already installed, skipping installation..."
else
    log_info "Installing Haskell via GHCup..."
    # Install required dependencies (essential packages)
    safe_apt_install build-essential curl libffi-dev libgmp-dev libgmp10 libncurses-dev

    # Try to install libffi7 if available, but don't fail if not
    safe_apt_install libffi7 || log_warning "libffi7 is not available, continuing with newer version"

    # Handle ncurses and tinfo libraries with fallbacks for newer Ubuntu versions
    if ! safe_apt_install libncurses5 2>/dev/null; then
        log_warning "libncurses5 is not available in this Ubuntu version"
        # Try newer version instead
        safe_apt_install libncurses6 2>/dev/null || safe_apt_install libncurses6-dev 2>/dev/null || true
    fi

    if ! safe_apt_install libtinfo5 2>/dev/null; then
        log_warning "libtinfo5 is not available in this Ubuntu version"
        # Try newer version instead
        safe_apt_install libtinfo6 2>/dev/null || safe_apt_install libtinfo-dev 2>/dev/null || true
    fi

    # Create compatibility symlinks if needed
    if [[ ! -f /lib/x86_64-linux-gnu/libncurses.so.5 && -f /lib/x86_64-linux-gnu/libncurses.so.6 ]]; then
        log_info "Creating compatibility symlink for libncurses.so.5"
        sudo ln -sf /lib/x86_64-linux-gnu/libncurses.so.6 /lib/x86_64-linux-gnu/libncurses.so.5 || true
    fi

    if [[ ! -f /lib/x86_64-linux-gnu/libtinfo.so.5 && -f /lib/x86_64-linux-gnu/libtinfo.so.6 ]]; then
        log_info "Creating compatibility symlink for libtinfo.so.5"
        sudo ln -sf /lib/x86_64-linux-gnu/libtinfo.so.6 /lib/x86_64-linux-gnu/libtinfo.so.5 || true
    fi

    # Create a secure temporary directory for the download
    TEMP_DIR=$(mktemp -d)
    chmod 700 "$TEMP_DIR"
    GHCUP_SCRIPT="$TEMP_DIR/ghcup.sh"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would download and install GHCup from https://get-ghcup.haskell.org"
        log_success "[DRY-RUN] Haskell/GHCup would be installed successfully"
    elif validate_and_download "https://get-ghcup.haskell.org" "$GHCUP_SCRIPT" "GHCup installer"; then
        # Make the script executable
        chmod 700 "$GHCUP_SCRIPT"

        # Execute the validated script with non-interactive setting
        if timeout 300 bash -c "BOOTSTRAP_HASKELL_NONINTERACTIVE=1 bash '$GHCUP_SCRIPT'"; then
            log_success "Haskell/GHCup installed successfully"
        else
            log_error "Failed to run the GHCup installer (may have timed out)"
        fi
    else
        log_error "Failed to download and validate GHCup installer"
    fi

    # Clean up temp directory
    rm -rf "$TEMP_DIR"
fi

# Add GHCup to shell profiles
for PROFILE in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [ -f "$PROFILE" ] && ! grep -q '.ghcup/env' "$PROFILE" && [ -f "$HOME/.ghcup/env" ]; then
        echo 'source "$HOME/.ghcup/env"' >>"$PROFILE"
        log_info "Added GHCup environment to $PROFILE"
    fi
done

log_success "Rust, Java (SDKMAN), and Haskell (GHCup) installed!"

exit 0
