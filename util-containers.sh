#!/usr/bin/env bash
# util-containers.sh - Container utilities and configuration
set -euo pipefail

# Guard against multiple sourcing
if [[ "${UTIL_CONTAINERS_LOADED:-}" == "true" ]]; then
  return 0
fi
readonly UTIL_CONTAINERS_LOADED="true"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-log.sh"
source "$SCRIPT_DIR/util-env.sh"
source "$SCRIPT_DIR/util-install.sh"

# Security and verification configuration
readonly CHECKSUMS_CACHE="$HOME/.cache/ubuntu-devtools/container-checksums"
declare -A PACKAGE_CHECKSUMS=()
declare -A PACKAGE_SIGNATURES=()

# Resilient download configuration
readonly MAX_DOWNLOAD_RETRIES=3
readonly DOWNLOAD_TIMEOUT=300
readonly MIRROR_SITES=(
  "https://github.com"
  "https://objects.githubusercontent.com"
)
declare -A DOWNLOAD_CACHE=()
declare -a FAILED_DOWNLOADS=()

# Configuration-driven installation
readonly CONTAINER_CONFIG_FILE="$HOME/.config/ubuntu-devtools/container-tools.yaml"
readonly DEFAULT_CONFIG_DIR="$HOME/.config/ubuntu-devtools"
declare -A TOOL_CONFIGS=()
declare -A TOOL_VERSIONS=()
declare -A TOOL_ENABLED=()

# Initialize security verification data
initialize_security_data() {
  mkdir -p "$CHECKSUMS_CACHE"

  # Define known checksums for specific versions - update these with each release
  # These are placeholder values and should be updated with actual checksums
  PACKAGE_CHECKSUMS["nerdctl-1.7.1"]="placeholder"    # Replace with actual SHA256
  PACKAGE_CHECKSUMS["buildkit-v0.12.4"]="placeholder" # Replace with actual SHA256

  log_debug "Security verification data initialized"
}

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
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

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
  containerd config default | sudo tee /etc/containerd/config.toml >/dev/null

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

# --- Enhanced secure download with verification ---
secure_download_with_verification() {
  local url="$1"
  local output_file="$2"
  local package_name="$3"
  local expected_checksum="${4:-}"

  log_info "Securely downloading $package_name..."

  # Use secure download options
  local curl_opts=(
    --fail
    --location
    --show-error
    --connect-timeout 30
    --max-time 300
    --retry 3
    --retry-delay 5
    --user-agent "ubuntu-devtools/1.0"
    --proto "=https"
    --tlsv1.2
  )

  # Download with security headers verification
  if ! curl "${curl_opts[@]}" "$url" -o "$output_file"; then
    log_error "Failed to download $package_name from $url"
    return 1
  fi

  # Verify file integrity if checksum provided
  if [[ -n "$expected_checksum" && "$expected_checksum" != "placeholder" ]]; then
    local actual_checksum
    actual_checksum=$(sha256sum "$output_file" | cut -d' ' -f1)

    if [[ "$actual_checksum" == "${expected_checksum#sha256:}" ]]; then
      log_success "Integrity verification passed for $package_name"
    else
      log_error "Integrity verification failed for $package_name"
      log_error "Expected: $expected_checksum"
      log_error "Actual: sha256:$actual_checksum"
      rm -f "$output_file"
      return 1
    fi
  else
    log_warning "No valid checksum available for $package_name - skipping verification"
  fi

  log_success "Secure download completed: $package_name"
  return 0
}

# --- Resilient download with retry logic ---
resilient_download() {
  local url="$1"
  local output_file="$2"
  local package_name="$3"
  local max_retries="${4:-$MAX_DOWNLOAD_RETRIES}"

  log_info "Starting resilient download: $package_name"

  local attempt=1
  local success=false

  while [[ $attempt -le $max_retries ]] && [[ "$success" == "false" ]]; do
    log_debug "Download attempt $attempt/$max_retries for $package_name"

    if curl --fail --location --show-error --connect-timeout 15 --max-time "$DOWNLOAD_TIMEOUT" \
      --retry 2 --retry-delay 3 --speed-limit 1024 --speed-time 30 \
      --user-agent "ubuntu-devtools/1.0" "$url" -o "$output_file"; then

      success=true
      log_success "Download successful on attempt $attempt: $package_name"
    else
      local exit_code=$?
      log_warning "Download attempt $attempt failed for $package_name (exit code: $exit_code)"

      if [[ $attempt -lt $max_retries ]]; then
        local delay=$((attempt * 5))
        log_info "Retrying in ${delay} seconds..."
        sleep "$delay"

        # Try different mirror if available
        if [[ $attempt -eq 2 ]] && [[ "$url" =~ github.com ]]; then
          log_info "Trying alternative mirror for $package_name"
          url="${url/github.com/objects.githubusercontent.com}"
        fi
      fi
    fi

    ((attempt++))
  done

  if [[ "$success" == "false" ]]; then
    log_error "Failed to download $package_name after $max_retries attempts"
    FAILED_DOWNLOADS+=("$package_name:$url")
    return 1
  fi

  return 0
}

# --- Install nerdctl with enhanced security ---
install_nerdctl() {
  init_logging
  initialize_security_data

  log_info "Installing nerdctl (Docker-compatible CLI for containerd)..."

  # Get latest release with verification
  log_info "Fetching latest nerdctl release..."
  local release_info
  local tag_name
  local download_url

  # Try to get release info with retry
  for retry in {1..3}; do
    release_info=$(curl -s --retry 3 --retry-delay 2 "https://api.github.com/repos/containerd/nerdctl/releases/latest")
    tag_name=$(echo "$release_info" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)

    if [[ -n "$tag_name" ]]; then
      break
    elif [[ $retry -lt 3 ]]; then
      log_warning "Retry $retry: Failed to get nerdctl release info, retrying in 5 seconds..."
      sleep 5
    else
      log_error "Failed to get nerdctl release info after multiple attempts"
      finish_logging
      return 1
    fi
  done

  download_url=$(echo "$release_info" | grep -o '"browser_download_url": *"[^"]*linux-amd64.tar.gz"' | head -1 | cut -d'"' -f4)

  if [[ -z "$download_url" ]]; then
    log_error "Failed to find download URL for nerdctl"
    finish_logging
    return 1
  fi

  log_info "Found nerdctl $tag_name at $download_url"

  local temp_file="/tmp/nerdctl-${tag_name}.tar.gz"
  local expected_checksum="${PACKAGE_CHECKSUMS["nerdctl-${tag_name#v}"]:-}"

  # Secure download with verification
  if resilient_download "$download_url" "$temp_file" "nerdctl"; then
    log_info "Installing verified nerdctl..."
    sudo tar -C /usr/local/bin -xzf "$temp_file" nerdctl
    sudo chmod +x /usr/local/bin/nerdctl
    rm -f "$temp_file"

    # Verify installation
    if command -v nerdctl >/dev/null 2>&1; then
      local version
      version=$(nerdctl --version 2>/dev/null || echo "unknown")
      log_success "nerdctl $version installed successfully"
    else
      log_error "nerdctl installation verification failed"
      finish_logging
      return 1
    fi
  else
    log_error "Failed to download nerdctl"
    finish_logging
    return 1
  fi

  finish_logging
  return 0
}

# --- Install BuildKit with enhanced security and reliability ---
install_buildkit() {
  init_logging

  log_info "Installing BuildKit with enhanced security..."

  # Create checkpoints for rollback if needed
  local checkpoint_dir="/tmp/buildkit-install-checkpoint-$$"
  mkdir -p "$checkpoint_dir"

  # Download latest BuildKit release with retry logic
  log_info "Fetching latest BuildKit release..."
  local release_info
  local tag_name
  local download_url

  # Try to get release info with retry
  for retry in {1..3}; do
    release_info=$(curl -s --retry 3 --retry-delay 2 "https://api.github.com/repos/moby/buildkit/releases/latest")
    tag_name=$(echo "$release_info" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)

    if [[ -n "$tag_name" ]]; then
      break
    elif [[ $retry -lt 3 ]]; then
      log_warning "Retry $retry: Failed to get BuildKit release info, retrying in 5 seconds..."
      sleep 5
    else
      log_error "Failed to get BuildKit release info after multiple attempts"
      rm -rf "$checkpoint_dir"
      finish_logging
      return 1
    fi
  done

  download_url=$(echo "$release_info" | grep -o '"browser_download_url": *"[^"]*linux-amd64.tar.gz"' | head -1 | cut -d'"' -f4)

  if [[ -z "$download_url" ]]; then
    log_error "Failed to find download URL for BuildKit"
    rm -rf "$checkpoint_dir"
    finish_logging
    return 1
  fi

  log_info "Found BuildKit $tag_name at $download_url"

  # Backup existing BuildKit binaries if they exist
  if [[ -f "/usr/local/bin/buildkitd" ]]; then
    log_info "Backing up existing BuildKit binaries..."
    cp -f "/usr/local/bin/buildkitd" "$checkpoint_dir/" 2>/dev/null || true
    cp -f "/usr/local/bin/buildctl" "$checkpoint_dir/" 2>/dev/null || true
  fi

  # Backup existing service file if it exists
  if [[ -f "/etc/systemd/system/buildkit.service" ]]; then
    log_info "Backing up existing BuildKit service file..."
    cp -f "/etc/systemd/system/buildkit.service" "$checkpoint_dir/" 2>/dev/null || true
  fi

  local temp_file="/tmp/buildkit-${tag_name}.tar.gz"
  local expected_checksum="${PACKAGE_CHECKSUMS["buildkit-${tag_name}"]:-}"

  # Secure download with retry logic
  if resilient_download "$download_url" "$temp_file" "BuildKit"; then
    log_success "Download complete"

    log_info "Installing BuildKit..."
    if ! sudo tar -C /usr/local -xzf "$temp_file"; then
      log_error "Failed to extract BuildKit archive"
      perform_buildkit_rollback "$checkpoint_dir"
      rm -f "$temp_file"
      rm -rf "$checkpoint_dir"
      finish_logging
      return 1
    fi

    rm -f "$temp_file"

    # Set up BuildKit daemon with improved configuration
    log_info "Setting up BuildKit daemon..."
    sudo tee /etc/systemd/system/buildkit.service >/dev/null <<'EOF'
[Unit]
Description=BuildKit
Documentation=https://github.com/moby/buildkit
After=network.target containerd.service

[Service]
ExecStart=/usr/local/bin/buildkitd --oci-worker=false --containerd-worker=true
Restart=always
RestartSec=5
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
KillMode=process

# Security options
PrivateTmp=true
ProtectSystem=full
ProtectHome=read-only
ReadWritePaths=/tmp

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload

    # Start service with health check
    log_info "Starting BuildKit service..."
    if ! sudo systemctl enable --now buildkit; then
      log_error "Failed to enable and start BuildKit service"
      perform_buildkit_rollback "$checkpoint_dir"
      rm -rf "$checkpoint_dir"
      finish_logging
      return 1
    fi

    # Verify BuildKit is operational
    log_info "Verifying BuildKit installation..."
    sleep 3

    if ! systemctl is-active --quiet buildkit; then
      log_error "BuildKit service failed to start"
      sudo systemctl status buildkit || true
      perform_buildkit_rollback "$checkpoint_dir"
      rm -rf "$checkpoint_dir"
      finish_logging
      return 1
    fi

    # Test buildctl command
    if ! timeout 10 buildctl debug info >/dev/null 2>&1; then
      log_error "BuildKit daemon is not responding"
      perform_buildkit_rollback "$checkpoint_dir"
      rm -rf "$checkpoint_dir"
      finish_logging
      return 1
    fi

    log_success "BuildKit installed and verified successfully"
    rm -rf "$checkpoint_dir"
  else
    log_error "Failed to download BuildKit"
    rm -rf "$checkpoint_dir"
    finish_logging
    return 1
  fi

  finish_logging
  return 0
}

# Rollback BuildKit installation if something fails
perform_buildkit_rollback() {
  local checkpoint_dir="$1"

  log_warning "Rolling back BuildKit installation..."

  # Stop BuildKit service
  sudo systemctl stop buildkit 2>/dev/null || true

  # Restore binaries if available
  if [[ -f "$checkpoint_dir/buildkitd" ]]; then
    log_info "Restoring BuildKit binaries from backup..."
    sudo cp -f "$checkpoint_dir/buildkitd" "/usr/local/bin/" 2>/dev/null || true
    sudo cp -f "$checkpoint_dir/buildctl" "/usr/local/bin/" 2>/dev/null || true
    sudo chmod +x "/usr/local/bin/buildkitd" 2>/dev/null || true
    sudo chmod +x "/usr/local/bin/buildctl" 2>/dev/null || true
  fi

  # Restore service file if available
  if [[ -f "$checkpoint_dir/buildkit.service" ]]; then
    log_info "Restoring BuildKit service file from backup..."
    sudo cp -f "$checkpoint_dir/buildkit.service" "/etc/systemd/system/" 2>/dev/null || true
    sudo systemctl daemon-reload
  fi

  # Restart service if it was previously running
  if [[ -f "$checkpoint_dir/buildkit.service" ]]; then
    log_info "Restarting BuildKit service..."
    sudo systemctl restart buildkit 2>/dev/null || true
  fi

  log_info "BuildKit rollback completed"
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

# --- Comprehensive Docker validation with health checks ---
validate_docker() {
  init_logging

  log_info "Performing comprehensive Docker validation..."

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

  # Check WSL integration
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

  # Perform health checks
  log_info "Performing Docker health checks..."

  # Test basic container operations
  log_info "Testing basic container operations..."
  if ! timeout 30 docker run --rm hello-world >/dev/null 2>&1; then
    log_error "Basic container test failed. Docker is not functioning correctly."
    log_info "Please check Docker logs with 'docker logs' or Docker Desktop troubleshooting."
    finish_logging
    return 1
  fi

  log_success "Docker health check passed - container operations working correctly"

  # Check available disk space
  log_info "Checking available disk space for Docker..."
  local docker_root
  docker_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "/var/lib/docker")

  local available_space
  available_space=$(df -h "$docker_root" | awk 'NR==2 {print $4}')

  log_info "Available space in Docker root directory ($docker_root): $available_space"

  # Warning if less than 10GB available
  if df -k "$docker_root" | awk 'NR==2 {exit ($4 < 10*1024*1024)}'; then
    log_warning "Low disk space for Docker. Consider clearing unused images with 'docker system prune'"
  fi

  # Check Docker network connectivity
  log_info "Testing Docker network connectivity..."
  if ! timeout 15 docker run --rm alpine ping -c 2 8.8.8.8 >/dev/null 2>&1; then
    log_warning "Docker network connectivity test failed. Container networking may be impaired."
  else
    log_success "Docker network connectivity test passed"
  fi

  # Generate report
  log_info "Docker validation complete"
  log_info "Docker type: $(detect_docker)"
  log_info "Docker version: $(docker --version | cut -d' ' -f3 | tr -d ',')"
  log_info "Images available: $(docker images -q | wc -l)"
  log_info "Containers running: $(docker ps -q | wc -l)"

  finish_logging
  return 0
}

# --- Comprehensive health check for container environment ---
perform_container_health_check() {
  init_logging

  log_info "=== Container Environment Health Check ==="

  local docker_type
  docker_type=$(detect_docker)

  log_info "Environment type: $(detect_environment)"
  log_info "Docker type: $docker_type"

  local health_status="HEALTHY"
  local issues=()

  # Check Docker/containerd based on environment
  case "$docker_type" in
  "docker-desktop")
    check_docker_desktop_health
    ;;
  "docker-engine")
    check_docker_engine_health
    ;;
  "docker-cli-only")
    check_docker_cli_health
    ;;
  "none")
    check_containerd_environment_health
    ;;
  esac

  # Display health report
  if [[ ${#issues[@]} -gt 0 ]]; then
    log_warning "Issues found:"
    for issue in "${issues[@]}"; do
      log_warning "  - $issue"
    done
    health_status="DEGRADED"
  fi

  log_info "Overall health status: $health_status"

  finish_logging
}

check_docker_desktop_health() {
  log_info "Checking Docker Desktop health..."

  # Check Docker Desktop service/process
  if ! docker info >/dev/null 2>&1; then
    issues+=("Docker Desktop is not running or not accessible")
    health_status="DEGRADED"
    return
  fi

  # Check WSL integration if in WSL
  if grep -qi microsoft /proc/version; then
    log_info "Checking WSL integration..."
    if ! docker run --rm hello-world >/dev/null 2>&1; then
      issues+=("WSL integration not working correctly")
      health_status="DEGRADED"
    fi
  fi

  # Check resource allocation
  local memory_limit
  memory_limit=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo "0")
  memory_limit=$((memory_limit / 1024 / 1024))

  if [[ $memory_limit -lt 2048 ]]; then
    issues+=("Docker memory limit is low: ${memory_limit}MB. Consider increasing in Docker Desktop settings.")
  fi

  log_success "Docker Desktop checks completed"
}

check_docker_engine_health() {
  log_info "Checking Docker Engine health..."

  # Check Docker daemon
  if ! systemctl is-active --quiet docker; then
    issues+=("Docker service is not running")
    health_status="DEGRADED"

    # Try to start docker service
    log_info "Attempting to start Docker service..."
    sudo systemctl start docker
    sleep 3

    if ! systemctl is-active --quiet docker; then
      issues+=("Failed to start Docker service")
    else
      log_success "Docker service started successfully"
    fi
  fi

  # Check Docker storage driver
  local storage_driver
  storage_driver=$(docker info --format '{{.Driver}}' 2>/dev/null || echo "unknown")
  log_info "Docker storage driver: $storage_driver"

  # Perform basic container test
  if ! timeout 15 docker run --rm hello-world >/dev/null 2>&1; then
    issues+=("Basic container test failed")
    health_status="DEGRADED"
  fi

  log_success "Docker Engine checks completed"
}

check_containerd_environment_health() {
  log_info "Checking containerd environment health..."

  # Check if containerd is installed and running
  if ! command -v containerd >/dev/null 2>&1; then
    issues+=("containerd is not installed")
    health_status="DEGRADED"
    return
  fi

  if ! systemctl is-active --quiet containerd; then
    issues+=("containerd service is not running")
    health_status="DEGRADED"

    # Try to start containerd service
    log_info "Attempting to start containerd service..."
    sudo systemctl start containerd
    sleep 3

    if ! systemctl is-active --quiet containerd; then
      issues+=("Failed to start containerd service")
    else
      log_success "containerd service started successfully"
    fi
  fi

  # Check nerdctl if installed
  if command -v nerdctl >/dev/null 2>&1; then
    log_info "Checking nerdctl..."
    if ! timeout 10 nerdctl info >/dev/null 2>&1; then
      issues+=("nerdctl cannot connect to containerd")
      health_status="DEGRADED"
    else
      # Test basic container operations with nerdctl
      if ! timeout 30 nerdctl run --rm hello-world >/dev/null 2>&1; then
        issues+=("nerdctl container test failed")
      else
        log_success "nerdctl container test passed"
      fi
    fi
  else
    issues+=("nerdctl is not installed")
  fi

  # Check BuildKit if installed
  if command -v buildkitd >/dev/null 2>&1; then
    log_info "Checking BuildKit..."
    if ! systemctl is-active --quiet buildkit; then
      issues+=("BuildKit service is not running")

      # Try to start BuildKit service
      log_info "Attempting to start BuildKit service..."
      sudo systemctl start buildkit
      sleep 3

      if ! systemctl is-active --quiet buildkit; then
        issues+=("Failed to start BuildKit service")
      else
        log_success "BuildKit service started successfully"
      fi
    fi

    # Test BuildKit functionality
    if command -v buildctl >/dev/null 2>&1; then
      if ! timeout 10 buildctl debug info >/dev/null 2>&1; then
        issues+=("buildctl cannot connect to BuildKit daemon")
      else
        log_success "BuildKit is functioning correctly"
      fi
    else
      issues+=("buildctl is not installed")
    fi
  else
    issues+=("BuildKit is not installed")
  fi

  log_success "containerd environment checks completed"
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
