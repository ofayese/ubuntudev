#!/usr/bin/env bash
# util-versions.sh - Language version managers utility functions
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-log.sh"
source "$SCRIPT_DIR/util-env.sh"

# --- NVM (Node Version Manager) ---

setup_nvm() {
  init_logging
  local install_latest=${1:-true}
  local install_lts=${2:-true}
  
  # Create NVM directory if it doesn't exist
  export NVM_DIR="$HOME/.nvm"
  mkdir -p "$NVM_DIR"
  
  # Get latest NVM version
  log_info "Fetching latest NVM version..."
  local NVM_VERSION
  NVM_VERSION=$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest | 
                grep "tag_name" | cut -d '"' -f 4 || echo "v0.39.7")
  
  log_info "Installing NVM $NVM_VERSION..."
  curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
  
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
      } >> "$PROFILE"
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
  
  # Install pyenv dependencies
  log_info "Installing pyenv dependencies..."
  sudo apt-get update -q
  sudo apt-get install -y build-essential libssl-dev zlib1g-dev libbz2-dev \
    libreadline-dev libsqlite3-dev wget curl llvm libncurses5-dev libncursesw5-dev \
    xz-utils tk-dev libffi-dev liblzma-dev python3-openssl git
  
  # Install pyenv
  log_info "Installing pyenv..."
  if [ ! -d "$HOME/.pyenv" ]; then
    curl https://pyenv.run | bash
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
      } >> "$PROFILE"
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
  
  # Install SDKMAN if not already installed
  if [ ! -d "$HOME/.sdkman" ]; then
    log_info "Installing SDKMAN..."
    curl -s "https://get.sdkman.io" | bash
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
      } >> "$PROFILE"
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
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    
    # Source rustup
    # shellcheck disable=SC1091
    source "$HOME/.cargo/env"
    
    # Add rustup to shell profiles
    for PROFILE in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
      if [ -f "$PROFILE" ] && ! grep -q 'cargo/env' "$PROFILE"; then
        echo "source \"\$HOME/.cargo/env\"" >> "$PROFILE"
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
    curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | BOOTSTRAP_HASKELL_NONINTERACTIVE=1 bash
    
    # Add GHCup to shell profiles
    for PROFILE in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
      if [ -f "$PROFILE" ] && ! grep -q '.ghcup/env' "$PROFILE"; then
        echo "source \"\$HOME/.ghcup/env\"" >> "$PROFILE"
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
      } >> "$PROFILE"
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

# Main function for demonstration
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Version manager utilities loaded. Use by sourcing this file."
  exit 0
fi
