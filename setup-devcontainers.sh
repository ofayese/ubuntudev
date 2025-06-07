#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/ubuntu-dev-tools.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== [setup-devcontainers.sh] Started at $(date) ==="

#!/bin/bash
# WSL2 Installation script for containerd, buildkit, CNI plugins, and nerdctl
# Equivalent to containerd-buildx-cni-install.ps1 for Ubuntu/Debian-based WSL2 distros

set -euo pipefail

# Define colors for better output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Define installation paths
INSTALL_ROOT="/usr/local"
CONTAINERD_DIR="${INSTALL_ROOT}/containerd"
BUILDKIT_DIR="${INSTALL_ROOT}/buildkit"
CNI_BIN_DIR="${INSTALL_ROOT}/containerd/cni/bin"
CNI_CONF_DIR="${INSTALL_ROOT}/containerd/cni/conf"
SYSTEMD_DIR="/etc/systemd/system"

# Define versions (matching the PowerShell script)
CONTAINERD_VERSION="2.1.0"
BUILDKIT_VERSION="v0.21.1"
CNI_VERSION="0.3.1"
NERDCTL_VERSION="2.1.1"
ARCH="amd64"

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}This script must be run as root${NC}"
    echo "Please run with sudo: sudo $0"
    exit 1
fi

# Function to check and install prerequisites
check_prerequisites() {
    echo -e "\n${GREEN}=== STEP 1: Checking prerequisites ===${NC}"
    
    # Create a list of required packages
    REQUIRED_PKGS="curl wget tar unzip jq net-tools"
    
    # Check for missing packages
    MISSING_PKGS=""
    for pkg in $REQUIRED_PKGS; do
        if ! command -v $pkg &> /dev/null; then
            MISSING_PKGS="$MISSING_PKGS $pkg"
        fi
    done
    
    # Install missing packages if any
    if [ ! -z "$MISSING_PKGS" ]; then
        echo "Installing missing packages:$MISSING_PKGS"
        apt-get update
        apt-get install -y $MISSING_PKGS
    else
        echo "All required packages are already installed."
    fi
}

# Function to install containerd
install_containerd() {
    echo -e "\n${GREEN}=== STEP 2: Install containerd ===${NC}"
    
    # Create directories if they don't exist
    mkdir -p "${CONTAINERD_DIR}"
    
    # Download containerd
    echo "Downloading containerd v${CONTAINERD_VERSION}..."
    CONTAINERD_URL="https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-${ARCH}.tar.gz"
    curl -L -o /tmp/containerd.tar.gz "${CONTAINERD_URL}"
    
    # Extract containerd
    echo "Extracting containerd..."
    tar -xzf /tmp/containerd.tar.gz -C /tmp
    
    # Copy binaries to destination
    cp -f /tmp/bin/* "${CONTAINERD_DIR}/"
    
    # Add to PATH if not already there
    if ! grep -q "${CONTAINERD_DIR}" /etc/environment; then
        echo "Adding containerd to PATH..."
        echo "PATH=\"\$PATH:${CONTAINERD_DIR}\"" >> /etc/environment
        export PATH="$PATH:${CONTAINERD_DIR}"
    fi
    
    # Create containerd configuration
    echo "Configuring containerd..."
    mkdir -p /etc/containerd
    "${CONTAINERD_DIR}/containerd" config default > /etc/containerd/config.toml
    
    # Create systemd service
    echo "Creating containerd systemd service..."
    cat > "${SYSTEMD_DIR}/containerd.service" << EOF
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target local-fs.target

[Service]
ExecStartPre=-/sbin/modprobe overlay
ExecStart=${CONTAINERD_DIR}/containerd
Restart=always
RestartSec=5
KillMode=process
Delegate=yes
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF

    # Enable and start service
    systemctl daemon-reload
    systemctl enable containerd
    systemctl start containerd
    
    echo "Containerd installed and started."
}

# Function to install BuildKit
install_buildkit() {
    echo -e "\n${GREEN}=== STEP 3: Install BuildKit ===${NC}"
    
    # Create directories if they don't exist
    mkdir -p "${BUILDKIT_DIR}"
    
    # Download BuildKit
    echo "Downloading BuildKit ${BUILDKIT_VERSION}..."
    BUILDKIT_URL="https://github.com/moby/buildkit/releases/download/${BUILDKIT_VERSION}/buildkit-${BUILDKIT_VERSION}.linux-${ARCH}.tar.gz"
    curl -L -o /tmp/buildkit.tar.gz "${BUILDKIT_URL}"
    
    # Extract BuildKit
    echo "Extracting BuildKit..."
    tar -xzf /tmp/buildkit.tar.gz -C /tmp
    
    # Copy binaries to destination
    cp -f /tmp/bin/* "${BUILDKIT_DIR}/"
    
    # Add to PATH if not already there
    if ! grep -q "${BUILDKIT_DIR}" /etc/environment; then
        echo "Adding buildkit to PATH..."
        echo "PATH=\"\$PATH:${BUILDKIT_DIR}\"" >> /etc/environment
        export PATH="$PATH:${BUILDKIT_DIR}"
    fi
    
    # Create symlinks to common bin directory
    ln -sf "${BUILDKIT_DIR}/"* /usr/local/bin/
    
    echo "BuildKit installed."
}

# Function to setup CNI
setup_cni() {
    echo -e "\n${GREEN}=== STEP 4: Setup CNI ===${NC}"
    
    # Create directories if they don't exist
    mkdir -p "${CNI_BIN_DIR}"
    mkdir -p "${CNI_CONF_DIR}"
    
    # For Linux, we'll use the standard CNI plugins
    echo "Downloading CNI plugins..."
    CNI_URL="https://github.com/containernetworking/plugins/releases/download/v1.1.1/cni-plugins-linux-${ARCH}-v1.1.1.tgz"
    curl -L -o /tmp/cni.tgz "${CNI_URL}"
    
    # Extract CNI plugins
    echo "Extracting CNI plugins..."
    tar -xzf /tmp/cni.tgz -C "${CNI_BIN_DIR}"
    
    # Create CNI configuration
    echo "Creating CNI configuration..."
    cat > "${CNI_CONF_DIR}/10-containerd-net.conflist" << EOF
{
  "cniVersion": "1.0.0",
  "name": "containerd-net",
  "plugins": [
    {
      "type": "bridge",
      "bridge": "cni0",
      "isGateway": true,
      "ipMasq": true,
      "promiscMode": true,
      "ipam": {
        "type": "host-local",
        "ranges": [
          [{
            "subnet": "10.88.0.0/16"
          }]
        ],
        "routes": [
          { "dst": "0.0.0.0/0" }
        ]
      }
    },
    {
      "type": "portmap",
      "capabilities": {"portMappings": true}
    }
  ]
}
EOF

    echo "CNI setup complete."
}

# Function to register BuildKit service
register_buildkit_service() {
    echo -e "\n${GREEN}=== STEP 5: Register BuildKit Service ===${NC}"
    
    # Create BuildKit systemd service
    echo "Creating BuildKit systemd service..."
    cat > "${SYSTEMD_DIR}/buildkit.service" << EOF
[Unit]
Description=BuildKit
Documentation=https://github.com/moby/buildkit
After=network.target containerd.service

[Service]
ExecStart=${BUILDKIT_DIR}/buildkitd --containerd-worker=true --containerd-cni-config-path=${CNI_CONF_DIR}/10-containerd-net.conflist --containerd-cni-binary-dir=${CNI_BIN_DIR} --debug
Restart=always
RestartSec=5
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF

    # Enable and start service
    systemctl daemon-reload
    systemctl enable buildkit
    systemctl start buildkit
    
    echo "BuildKit service registered and started."
}

# Function to install nerdctl
install_nerdctl() {
    echo -e "\n${GREEN}=== STEP 6: Install nerdctl ===${NC}"
    
    # Download nerdctl
    echo "Downloading nerdctl v${NERDCTL_VERSION}..."
    NERDCTL_URL="https://github.com/containerd/nerdctl/releases/download/v${NERDCTL_VERSION}/nerdctl-${NERDCTL_VERSION}-linux-${ARCH}.tar.gz"
    curl -L -o /tmp/nerdctl.tar.gz "${NERDCTL_URL}"
    
    # Extract nerdctl
    echo "Extracting nerdctl..."
    mkdir -p "${BUILDKIT_DIR}/nerdctl"
    tar -xzf /tmp/nerdctl.tar.gz -C "${BUILDKIT_DIR}/nerdctl"
    
    # Link to bin directory
    ln -sf "${BUILDKIT_DIR}/nerdctl/nerdctl" /usr/local/bin/nerdctl
    
    echo "nerdctl installed."
}

# Function to enable non-admin access
enable_non_admin_access() {
    echo -e "\n${GREEN}=== STEP 7: Enable Non-Admin Access ===${NC}"
    
    # Create buildkit group if it doesn't exist
    if ! getent group buildkit-users > /dev/null; then
        echo "Creating buildkit-users group..."
        groupadd buildkit-users
    fi
    
    # Add current user to buildkit-users group
    echo "Adding current user to buildkit-users group..."
    USERNAME=$(logname || echo "${SUDO_USER:-$USER}")
    usermod -aG buildkit-users "${USERNAME}"
    
    echo "Non-admin access configured. You may need to log out and back in for group changes to take effect."
}

# Function to clean up
cleanup() {
    echo -e "\n${GREEN}=== STEP 8: Cleanup ===${NC}"
    
    # Remove temporary files
    rm -f /tmp/containerd.tar.gz /tmp/buildkit.tar.gz /tmp/cni.tgz /tmp/nerdctl.tar.gz
    rm -rf /tmp/bin
    
    echo "Cleanup complete."
}

# Function to test the installation
test_installation() {
    echo -e "\n${GREEN}=== STEP 9: Test Installations ===${NC}"
    
    # Test containerd
    if command -v containerd &> /dev/null; then
        echo -e "${GREEN}✓ containerd is installed:${NC}"
        containerd --version
    else
        echo -e "${RED}✗ containerd is not available in PATH${NC}"
    fi
    
    # Test buildctl
    if command -v buildctl &> /dev/null; then
        echo -e "${GREEN}✓ buildctl is installed:${NC}"
        buildctl --version
    else
        echo -e "${RED}✗ buildctl is not available in PATH${NC}"
    fi
    
    # Test nerdctl
    if command -v nerdctl &> /dev/null; then
        echo -e "${GREEN}✓ nerdctl is installed:${NC}"
        nerdctl --version
    else
        echo -e "${RED}✗ nerdctl is not available in PATH${NC}"
    fi
    
    # Test buildkit daemon
    if systemctl is-active --quiet buildkit; then
        echo -e "${GREEN}✓ buildkit service is running${NC}"
        buildctl debug info
    else
        echo -e "${RED}✗ buildkit service is not running${NC}"
    fi
}

# Main execution
echo -e "${GREEN}====================================${NC}"
echo -e "${GREEN}  Containerd, BuildKit, nerdctl    ${NC}"
echo -e "${GREEN}  WSL2 Installation Script         ${NC}"
echo -e "${GREEN}====================================${NC}"

# Run all functions in sequence
check_prerequisites
install_containerd
install_buildkit
setup_cni
register_buildkit_service
install_nerdctl
enable_non_admin_access
cleanup
test_installation

echo -e "\n${GREEN}Installation complete!${NC}"
echo -e "${YELLOW}Note: Some tools might require a logout/login or WSL restart to be fully functional.${NC}"

