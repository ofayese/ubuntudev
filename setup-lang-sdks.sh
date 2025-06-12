#!/usr/bin/env bash
set -euo pipefail

# Source utility modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-log.sh"
source "$SCRIPT_DIR/util-env.sh"
source "$SCRIPT_DIR/util-install.sh"

# Initialize logging
init_logging
log_info "Language SDKs setup started"

# Detect environment
ENV_TYPE=$(detect_environment)
log_info "Environment detected: $ENV_TYPE"

# Define installation steps for progress tracking
declare -a SETUP_STEPS=(
  "rust_setup"
  "java_setup"
  "haskell_setup"
)

current_step=0
total_steps=${#SETUP_STEPS[@]}

# --- RUST (Rustup) ---
((current_step++))
log_info "[$current_step/$total_steps] Installing Rust via rustup..."
show_progress "$current_step" "$total_steps" "Language SDKs Setup"
start_spinner "Installing Rust"

# Check if Rust is already installed
if command -v rustc &> /dev/null && command -v cargo &> /dev/null; then
    log_info "Rust is already installed, updating instead..."
    source "$HOME/.cargo/env" 2>/dev/null || true
    if rustup update; then
        log_success "Rust updated successfully"
    else
        log_warning "Failed to update Rust"
    fi
else
    log_info "Installing Rust via rustup..."
    if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y; then
        log_success "Rust installed successfully"
        # Load Rust environment
        source "$HOME/.cargo/env" || {
            log_warning "Failed to source Rust environment. You may need to restart your terminal."
        }
    else
        log_error "Failed to install Rust"
    fi
fi

# Add Rust to shell profile
for PROFILE in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [ -f "$PROFILE" ] && ! grep -q 'cargo/env' "$PROFILE"; then
        echo 'source "$HOME/.cargo/env"' >> "$PROFILE"
        log_info "Added Rust environment to $PROFILE"
    fi
done

stop_spinner "Installing Rust"

# --- JAVA / JVM via SDKMAN ---
((current_step++))
log_info "[$current_step/$total_steps] Installing SDKMAN and JVM toolchain..."
show_progress "$current_step" "$total_steps" "Language SDKs Setup"
start_spinner "Installing SDKMAN"

# Check if SDKMAN is already installed
if [ -d "$HOME/.sdkman" ] && [ -f "$HOME/.sdkman/bin/sdkman-init.sh" ]; then
    log_info "SDKMAN is already installed, skipping installation..."
    source "$HOME/.sdkman/bin/sdkman-init.sh" || {
        log_warning "Failed to source SDKMAN environment"
    }
else
    log_info "Installing SDKMAN..."
    if curl -s "https://get.sdkman.io" | bash; then
        log_success "SDKMAN installed successfully"
        # Initialize SDKMAN
        source "$HOME/.sdkman/bin/sdkman-init.sh" || {
            log_warning "Failed to source SDKMAN environment. You may need to restart your terminal."
        }
    else
        log_error "Failed to install SDKMAN"
        stop_spinner "Installing SDKMAN"
        finish_logging
        exit 1
    fi
fi

# Add SDKMAN init to shell profiles
for PROFILE in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [ -f "$PROFILE" ] && ! grep -q 'sdkman-init.sh' "$PROFILE"; then
        echo 'source "$HOME/.sdkman/bin/sdkman-init.sh"' >> "$PROFILE"
        log_info "Added SDKMAN initialization to $PROFILE"
    fi
done

stop_spinner "Installing SDKMAN"

# Install Java SDKs
start_spinner "Installing Java SDKs"
log_info "Installing Java SDKs..."

# Function to install Java with version fallbacks
install_java_version() {
    local major_version=$1
    local specific_version=$2
    local vendor=${3:-tem}
    
    log_info "Trying to install Java $specific_version..."
    if command -v sdk &> /dev/null && sdk install java $specific_version-$vendor 2>/dev/null; then
        log_success "Installed Java $specific_version-$vendor"
        return 0
    else
        log_warning "Specific Java $specific_version not available, trying latest $major_version.x..."
        if command -v sdk &> /dev/null && sdk install java $major_version-$vendor 2>/dev/null; then
            log_success "Installed Java $major_version-$vendor"
            return 0
        elif command -v sdk &> /dev/null && sdk install java $major_version.0-$vendor 2>/dev/null; then
            log_success "Installed Java $major_version.0-$vendor"
            return 0
        else
            log_warning "Failed to install Java $major_version"
            return 1
        fi
    fi
}

# Install Java 17 and 21
install_java_version "17" "17.0.9"
install_java_version "21" "21.0.2"

# Set default Java version (prefer 17 for broader compatibility)
log_info "Setting default Java version..."
if command -v sdk &> /dev/null; then
    if sdk default java 17-tem 2>/dev/null || sdk default java 17.0-tem 2>/dev/null || sdk default java 17.0.9-tem 2>/dev/null; then
        log_success "Set Java 17 as default"
    else
        log_warning "Could not set Java 17 as default"
    fi
else
    log_warning "SDKMAN command 'sdk' not available, skipping default Java setup"
fi

stop_spinner "Installing Java SDKs"

# --- HASKELL via GHCup ---
((current_step++))
log_info "[$current_step/$total_steps] Installing Haskell via GHCup..."
show_progress "$current_step" "$total_steps" "Language SDKs Setup"
start_spinner "Installing Haskell"

# Check if GHCup is already installed
if [ -d "$HOME/.ghcup" ] && command -v ghc &> /dev/null; then
    log_info "Haskell/GHCup is already installed, skipping installation..."
else
    log_info "Installing Haskell via GHCup..."
    # Install required dependencies
    safe_apt_install build-essential curl libffi-dev libffi7 libgmp-dev libgmp10 libncurses-dev libncurses5 libtinfo5
    
    if curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | BOOTSTRAP_HASKELL_NONINTERACTIVE=1 bash; then
        log_success "Haskell/GHCup installed successfully"
    else
        log_warning "Failed to install Haskell/GHCup"
    fi
fi

# Add GHCup to shell profiles
for PROFILE in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [ -f "$PROFILE" ] && ! grep -q '.ghcup/env' "$PROFILE" && [ -f "$HOME/.ghcup/env" ]; then
        echo 'source "$HOME/.ghcup/env"' >> "$PROFILE"
        log_info "Added GHCup environment to $PROFILE"
    fi
done

stop_spinner "Installing Haskell"

log_success "Rust, Java (SDKMAN), and Haskell (GHCup) installed!"
finish_logging
