#!/usr/bin/env bash
# util-containers.sh - Container utilities and configuration
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-log.sh"
source "$SCRIPT_DIR/util-env.sh"
source "$SCRIPT_DIR/util-install.sh"

# --- Detect Docker Desktop or Docker Engine ---
detect_docker() {
  if command -v docker >/dev/null 2>&1; then
    if docker info 2>/dev/null | grep -q "Docker Desktop"; then
      echo "docker-desktop"
    elif docker info 2>/dev/null | grep -q "Server Version"; then
      echo "docker-engine"
    else
      echo "docker-cli-only"
    fi
  else
    echo "none"
  fi
}

# --- Check container availability ---
check_docker() {
  init_logging
  
  log_info "Checking Docker availability..."
  
  if ! command -v docker >/dev/null 2>&1; then
    log_error "Docker CLI not found."
    finish_logging
    return 1
  fi
  
  if ! docker info >/dev/null 2>&1; then
    log_error "Docker daemon not accessible. Is Docker Desktop running?"
    finish_logging
    return 1
  fi
  
  log_success "Docker is installed and accessible."
  finish_logging
  return 0
}

# --- Install Docker Desktop on native Linux ---
install_docker_desktop_linux() {
  init_logging
  
  # Check if we're in WSL
  if grep -qi microsoft /proc/version; then
    log_warning "Running in WSL. You should use Docker Desktop for Windows instead."
    finish_logging
    return 1
  fi
  
  log_info "Installing Docker Desktop for Linux..."
  
  # Install prerequisites
  log_info "Installing prerequisites..."
  sudo apt-get update -q
  safe_apt_install ca-certificates curl gnupg lsb-release apt-transport-https
  
  # Remove conflicting packages
  log_info "Removing any conflicting Docker packages..."
  sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
  
  # Download latest Docker Desktop .deb
  log_info "Fetching Docker Desktop download URL..."
  DESKTOP_URL=$(curl -s https://api.github.com/repos/docker/desktop/releases/latest |
    grep browser_download_url | grep 'docker-desktop-.*-amd64.deb' | head -1 | cut -d '"' -f 4)
  
  if [ -z "$DESKTOP_URL" ]; then
    log_error "Failed to get Docker Desktop download URL"
    finish_logging
    return 1
  fi
  
  log_info "Downloading Docker Desktop from $DESKTOP_URL..."
  if wget -q -O /tmp/docker-desktop.deb "$DESKTOP_URL"; then
    log_success "Download complete"
    
    log_info "Installing Docker Desktop..."
    if sudo apt install -y /tmp/docker-desktop.deb; then
      log_success "Docker Desktop installed successfully"
      rm -f /tmp/docker-desktop.deb
    else
      log_error "Failed to install Docker Desktop"
      rm -f /tmp/docker-desktop.deb
      finish_logging
      return 1
    fi
  else
    log_error "Failed to download Docker Desktop"
    finish_logging
    return 1
  fi
  
  finish_logging
  return 0
}

# --- Install containerd ---
install_containerd() {
  init_logging
  
  log_info "Installing containerd..."
  
  # Set up the Docker repository
  log_info "Setting up Docker/containerd repository..."
  sudo apt-get update -q
  safe_apt_install ca-certificates curl gnupg lsb-release apt-transport-https
  
  # Add Docker's official GPG key
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  
  # Set up the repository
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  
  # Install containerd
  log_info "Installing containerd.io..."
  sudo apt-get update -q
  if ! safe_apt_install containerd.io; then
    log_error "Failed to install containerd.io"
    finish_logging
    return 1
  fi
  
  # Configure containerd
  log_info "Configuring containerd..."
  sudo mkdir -p /etc/containerd
  containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
  
  # Use systemd cgroup driver
  sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
  
  # Restart containerd
  log_info "Restarting containerd service..."
  sudo systemctl restart containerd
  sudo systemctl enable containerd
  
  log_success "containerd installed and configured"
  finish_logging
  return 0
}

# --- Install nerdctl ---
install_nerdctl() {
  init_logging
  
  log_info "Installing nerdctl (Docker-compatible CLI for containerd)..."
  
  # Download latest nerdctl release
  log_info "Fetching latest nerdctl release..."
  NERDCTL_URL=$(curl -s https://api.github.com/repos/containerd/nerdctl/releases/latest |
    grep browser_download_url | grep 'nerdctl-.*-linux-amd64.tar.gz' | head -1 | cut -d '"' -f 4)
  
  if [ -z "$NERDCTL_URL" ]; then
    log_error "Failed to get nerdctl download URL"
    finish_logging
    return 1
  fi
  
  log_info "Downloading nerdctl from $NERDCTL_URL..."
  if wget -q -O /tmp/nerdctl.tar.gz "$NERDCTL_URL"; then
    log_success "Download complete"
    
    log_info "Installing nerdctl..."
    sudo tar -C /usr/local/bin -xzf /tmp/nerdctl.tar.gz nerdctl
    sudo chmod +x /usr/local/bin/nerdctl
    rm -f /tmp/nerdctl.tar.gz
    
    log_success "nerdctl installed successfully"
  else
    log_error "Failed to download nerdctl"
    finish_logging
    return 1
  fi
  
  finish_logging
  return 0
}

# --- Install BuildKit ---
install_buildkit() {
  init_logging
  
  log_info "Installing BuildKit..."
  
  # Download latest BuildKit release
  log_info "Fetching latest BuildKit release..."
  BUILDKIT_URL=$(curl -s https://api.github.com/repos/moby/buildkit/releases/latest |
    grep browser_download_url | grep 'buildkit-v.*\.linux-amd64.tar.gz' | head -1 | cut -d '"' -f 4)
  
  if [ -z "$BUILDKIT_URL" ]; then
    log_error "Failed to get BuildKit download URL"
    finish_logging
    return 1
  fi
  
  log_info "Downloading BuildKit from $BUILDKIT_URL..."
  if wget -q -O /tmp/buildkit.tar.gz "$BUILDKIT_URL"; then
    log_success "Download complete"
    
    log_info "Installing BuildKit..."
    sudo tar -C /usr/local -xzf /tmp/buildkit.tar.gz
    rm -f /tmp/buildkit.tar.gz
    
    # Set up BuildKit daemon
    log_info "Setting up BuildKit daemon..."
    sudo tee /etc/systemd/system/buildkit.service > /dev/null << 'EOF'
[Unit]
Description=BuildKit
Documentation=https://github.com/moby/buildkit

[Service]
ExecStart=/usr/local/bin/buildkitd --oci-worker=false --containerd-worker=true
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now buildkit
    
    log_success "BuildKit installed successfully"
  else
    log_error "Failed to download BuildKit"
    finish_logging
    return 1
  fi
  
  finish_logging
  return 0
}

# --- Add current user to docker group ---
setup_docker_user() {
  init_logging
  
  log_info "Adding current user to docker group..."
  
  # Get current username
  USERNAME=$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")
  
  # Create docker group if not exists and add user
  sudo groupadd -f docker
  sudo usermod -aG docker "$USERNAME"
  
  log_success "Added $USERNAME to docker group"
  log_warning "You may need to log out and back in for group changes to take effect"
  
  finish_logging
  return 0
}

# --- Validate Docker installation ---
validate_docker() {
  init_logging
  
  log_info "Validating Docker installation..."
  
  # Check Docker CLI
  if ! command -v docker >/dev/null 2>&1; then
    log_error "Docker CLI is not installed"
    finish_logging
    return 1
  fi
  
  # Check Docker daemon
  if ! docker info >/dev/null 2>&1; then
    log_warning "Docker daemon is not running or not accessible"
    log_info "If using Docker Desktop, please start it and ensure WSL integration is enabled"
    finish_logging
    return 1
  fi
  
  log_success "Docker is properly installed and running"
  
  # Show Docker version info
  docker version
  
  # Check if running in WSL
  if grep -qi microsoft /proc/version; then
    log_info "Checking Docker context in WSL..."
    
    CONTEXT=$(docker context show)
    if [[ "$CONTEXT" != "default" && "$CONTEXT" != *"wsl"* ]]; then
      log_warning "Unexpected Docker context: $CONTEXT"
      log_info "Consider running 'docker context use default' to ensure proper WSL integration"
    else
      log_success "Docker context is correctly set to $CONTEXT"
    fi
  fi
  
  finish_logging
  return 0
}

# --- Setup complete container environment ---
setup_containers() {
  init_logging
  
  # Detect environment type
  ENV_TYPE=$(detect_environment)
  DOCKER_TYPE=$(detect_docker)
  
  log_info "Setting up container environment for $ENV_TYPE..."
  
  case "$ENV_TYPE" in
    "WSL2")
      log_info "WSL2 environment detected"
      
      if [[ "$DOCKER_TYPE" == "none" ]]; then
        log_info "Docker not detected. Please install Docker Desktop for Windows with WSL integration"
        log_info "Visit: https://docs.docker.com/desktop/install/windows-install/"
      else
        log_info "Docker detected: $DOCKER_TYPE"
        validate_docker
      fi
      ;;
      
    "DESKTOP")
      log_info "Desktop environment detected"
      
      if [[ "$DOCKER_TYPE" == "none" ]]; then
        log_info "Docker not detected. Installing Docker Desktop for Linux..."
        install_docker_desktop_linux
      else
        log_info "Docker detected: $DOCKER_TYPE"
        validate_docker
      fi
      ;;
      
    *)
      log_info "Headless environment detected"
      
      if [[ "$DOCKER_TYPE" == "none" ]]; then
        log_info "Docker not detected. Setting up containerd, BuildKit, and nerdctl..."
        install_containerd
        install_buildkit
        install_nerdctl
      else
        log_info "Docker detected: $DOCKER_TYPE"
        validate_docker
      fi
      ;;
  esac
  
  # Add current user to docker group
  setup_docker_user
  
  log_success "Container environment setup complete"
  finish_logging
}

# Main function for demonstration
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  setup_containers
fi
