#!/usr/bin/env bash
# fix-devtools-hang.sh - Fix the devtools hanging issue
# Version: 1.0.0
# Last updated: 2025-06-13
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

echo "Starting diagnostic and fix process..."

# 1. Create a backup of setup-devtools.sh
echo "Creating backup of setup-devtools.sh..."
cp "$SCRIPT_DIR/setup-devtools.sh" "$SCRIPT_DIR/setup-devtools.sh.bak"

# 2. Create a simplified version of setup-devtools.sh that doesn't use spinners
echo "Creating simplified setup-devtools.sh..."
cat >"$SCRIPT_DIR/setup-devtools.sh" <<'EOL'
#!/usr/bin/env bash
# setup-devtools.sh - Dev tools setup using util-install (SIMPLIFIED VERSION)
# Version: 1.0.0
# Last updated: 2025-06-13
set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# Source utility module
source "$SCRIPT_DIR/util-install.sh" || {
  echo "FATAL: Failed to source util-install.sh" >&2
  exit 1
}

# Simple direct logging function
log_msg() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_msg "Starting DevTools setup..."

# Update package index
log_msg "Updating package index..."
sudo apt-get update -y || log_msg "Warning: Package index update had issues, continuing anyway"

# Install system monitoring tools
log_msg "Installing system monitoring tools..."
monitoring_packages=(htop btop glances ncdu iftop)
for pkg in "${monitoring_packages[@]}"; do
  log_msg "Installing $pkg..."
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" || log_msg "Warning: Failed to install $pkg"
done

# Install CLI utilities
log_msg "Installing CLI utilities..."
cli_packages=(bat fzf ripgrep git wget curl)
for pkg in "${cli_packages[@]}"; do
  log_msg "Installing $pkg..."
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" || log_msg "Warning: Failed to install $pkg"
done

# Try alternative package names for failed installs
command -v bat &>/dev/null || {
  log_msg "Installing batcat (bat alternative)..."
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y batcat && 
    echo 'alias bat=batcat' >>"$HOME/.bashrc"
}

# Install eza from GitHub
log_msg "Installing eza..."
if ! command -v eza &>/dev/null; then
  if ! sudo DEBIAN_FRONTEND=noninteractive apt-get install -y eza; then
    log_msg "eza not available via apt, trying binary download..."
    temp_dir="/tmp/eza_install_$$"
    mkdir -p "$temp_dir"
    
    if wget -q -O "$temp_dir/eza.tar.gz" "https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-gnu.tar.gz"; then
      log_msg "Downloaded eza binary, installing..."
      (cd "$temp_dir" && tar -xzf eza.tar.gz && sudo install -m 755 eza /usr/local/bin/eza) || log_msg "Warning: Failed to install eza binary"
      rm -rf "$temp_dir"
    else
      log_msg "Warning: Failed to download eza binary. Creating alias to ls instead."
      touch "$HOME/.bashrc"
      if ! grep -q 'alias eza=' "$HOME/.bashrc"; then
        echo 'alias eza="ls --color=auto"' >>"$HOME/.bashrc"
      fi
    fi
  fi
fi

# Install Zsh & Oh-My-Zsh
log_msg "Installing Zsh..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y zsh || log_msg "Warning: Failed to install zsh"

if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  log_msg "Installing Oh-My-Zsh..."
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(wget --timeout=30 -qO- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || 
    log_msg "Warning: Failed to install Oh-My-Zsh"
else
  log_msg "Oh-My-Zsh is already installed"
fi

# Verify critical tools
critical_missing=()
command -v wget >/dev/null || critical_missing+=("wget")
command -v curl >/dev/null || critical_missing+=("curl")
command -v git >/dev/null || critical_missing+=("git")

if [ ${#critical_missing[@]} -gt 0 ]; then
  log_msg "ERROR: Critical tools missing: ${critical_missing[*]}"
  log_msg "DevTools setup failed - essential tools not available"
  exit 1
fi

log_msg "DevTools setup completed successfully!"
exit 0
EOL

# Make the script executable
chmod +x "$SCRIPT_DIR/setup-devtools.sh"

# 3. Also, check if there are any stuck processes that need to be killed
echo "Checking for any stuck processes..."
ps aux | grep -E 'install.*spinner|setup-devtools|DEBIAN_FRONTEND' | grep -v grep

echo "Do you want to kill any stuck processes? (y/n)"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    ps aux | grep -E 'install.*spinner|setup-devtools|DEBIAN_FRONTEND' | grep -v grep | awk '{print $2}' | xargs -r kill -9
    echo "Processes killed."
fi

# 4. Clear the state file to allow reinstalling devtools
if [[ -f "$HOME/.ubuntu-devtools.state" ]]; then
    echo "Removing devtools from state file to allow reinstallation..."
    grep -v "^devtools$" "$HOME/.ubuntu-devtools.state" >"$HOME/.ubuntu-devtools.state.tmp" || touch "$HOME/.ubuntu-devtools.state.tmp"
    mv "$HOME/.ubuntu-devtools.state.tmp" "$HOME/.ubuntu-devtools.state"
fi

# 5. Fix the install_component function in util-install.sh if needed
echo "Checking install_component function in util-install.sh..."
if grep -q "start_spinner.*Installing \$description" "$SCRIPT_DIR/util-install.sh"; then
    echo "Found spinner calls in install_component that should be disabled. Fixing..."
    sed -i 's/start_spinner "Installing \$description"/# start_spinner "Installing \$description"  # Disabled: component scripts have their own progress/g' "$SCRIPT_DIR/util-install.sh"
    sed -i 's/stop_spinner "Installing \$description"/# stop_spinner "Installing \$description"  # Disabled: no spinner to stop/g' "$SCRIPT_DIR/util-install.sh"
fi

echo "Fix complete. Now you can run install-new.sh again with your desired options."
echo "Example: ./install-new.sh --devtools"
