#!/usr/bin/env bash
set -euo pipefail

# Source utility modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-log.sh"
source "$SCRIPT_DIR/util-env.sh"
source "$SCRIPT_DIR/util-install.sh"

# Initialize logging
init_logging
log_info "Dotnet AI/ML setup started"

# Detect environment
ENV_TYPE=$(detect_environment)
log_info "Environment detected: $ENV_TYPE"

# --- DOTNET SDKs ---
log_info "Installing .NET SDKs 8.0, 9.0..."
start_spinner "Setting up Microsoft package repository"

# Get Ubuntu version and add Microsoft package repo
UBUNTU_VERSION=$(lsb_release -rs)
if wget -q "https://packages.microsoft.com/config/ubuntu/$UBUNTU_VERSION/packages-microsoft-prod.deb" -O /tmp/packages-microsoft-prod.deb; then
    if sudo dpkg -i /tmp/packages-microsoft-prod.deb; then
        rm /tmp/packages-microsoft-prod.deb
        sudo apt-get update -q
        log_success "Microsoft package repository configured"
    else
        log_error "Failed to install Microsoft package repository"
        finish_logging
        exit 1
    fi
else
    log_error "Failed to download Microsoft package repository"
    finish_logging
    exit 1
fi
stop_spinner "Setting up Microsoft package repository"

# Install .NET SDKs with error handling
start_spinner "Installing .NET SDKs"
log_info "Installing .NET 8.0 SDK"
if safe_apt_install dotnet-sdk-8.0; then
    log_success ".NET 8.0 SDK installed"
else
    log_warning "Failed to install .NET 8.0 SDK"
fi

log_info "Installing .NET 9.0 SDK"
if safe_apt_install dotnet-sdk-9.0; then
    log_success ".NET 9.0 SDK installed"
else
    log_warning "Failed to install .NET 9.0 SDK"
fi

# .NET 10.0 might not be available yet (preview/RC)
log_info "Checking for .NET 10.0 SDK (may be in preview)"
if sudo apt-get install -y dotnet-sdk-10.0 2>/dev/null; then
    log_success ".NET 10.0 SDK installed"
else
    log_warning ".NET 10.0 SDK not available (may be in preview)"
fi
stop_spinner "Installing .NET SDKs"

# --- PowerShell ---
log_info "Installing PowerShell..."
start_spinner "Installing PowerShell"
safe_apt_install apt-transport-https software-properties-common
if safe_apt_install powershell; then
    log_success "PowerShell installed successfully"
else
    log_warning "Failed to install PowerShell"
fi
stop_spinner "Installing PowerShell"

# --- Miniconda Setup ---
log_info "Installing Miniconda for Python AI/ML stack..."
start_spinner "Installing Python prerequisites"
safe_apt_install python3 python3-pip python3-venv curl
stop_spinner "Installing Python prerequisites"

start_spinner "Installing Miniconda"
# Check if Miniconda is already installed
if [ -d "$HOME/miniconda" ]; then
    log_info "Miniconda is already installed, skipping installation"
else
    cd /tmp || {
        log_error "Failed to change to /tmp directory"
        finish_logging
        exit 1
    }
    if curl -s -o miniconda.sh https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh; then
        if bash miniconda.sh -b -p "$HOME/miniconda"; then
            export PATH="$HOME/miniconda/bin:$PATH"
            # Check if PATH is already set in .bashrc
            if ! grep -q 'export PATH="$HOME/miniconda/bin:$PATH"' ~/.bashrc; then
                echo 'export PATH="$HOME/miniconda/bin:$PATH"' >>~/.bashrc
            fi
            log_success "Miniconda installed successfully"
        else
            log_error "Failed to install Miniconda"
            finish_logging
            exit 1
        fi
        rm -f miniconda.sh
    else
        log_error "Failed to download Miniconda installer"
        finish_logging
        exit 1
    fi
fi
stop_spinner "Installing Miniconda"

# --- Python Packages for Data Science + AI ---
log_info "Installing Python packages for ML and data science..."
start_spinner "Installing Python data science packages"

# Function to safely install pip packages
install_pip_package() {
    local package
    package=$1
    local pip_command
    pip_command=${2:-pip3}
    local extra_args
    extra_args=${3:-}

    log_info "Installing $package"
    if $pip_command install $package $extra_args; then
        log_success "Installed $package"
        return 0
    else
        log_warning "Failed to install $package"
        return 1
    fi
}

# Upgrade pip
pip3 install --upgrade pip

# Install data science packages
packages=("numpy" "scipy" "pandas" "matplotlib" "seaborn" "scikit-learn" "tqdm" "jupyterlab" "jupyter" "notebook")
for package in "${packages[@]}"; do
    install_pip_package "$package"
done

# Install PyTorch (CPU version for compatibility)
log_info "Installing PyTorch (CPU version)"
pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu || log_warning "Failed to install PyTorch"

# Try to find a suitable Python version for TensorFlow
python_versions=("python3.11" "python3.10" "python3.9" "python3.8" "python3")
for py_version in "${python_versions[@]}"; do
    if command -v $py_version &>/dev/null; then
        log_info "Using $py_version for TensorFlow installation"
        $py_version -m pip install --upgrade pip
        $py_version -m pip install tensorflow keras opencv-python || log_warning "TensorFlow installation failed with $py_version"
        break
    fi
done

# Install HuggingFace + Transformers
log_info "Installing HuggingFace Transformers and related packages"
packages=("transformers" "datasets" "ipywidgets")
for package in "${packages[@]}"; do
    install_pip_package "$package"
done

# Install optional AI API clients
optional_packages=("openai" "anthropic")
for package in "${optional_packages[@]}"; do
    install_pip_package "$package" || log_warning "Failed to install optional package: $package"
done

stop_spinner "Installing Python data science packages"

log_success ".NET SDKs, PowerShell, and AI/ML toolchains installed!"
finish_logging
