#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/ubuntu-dev-tools.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== [setup-node-python.sh] Started at $(date) ==="

# Check if running in WSL
IS_WSL=0
if grep -qi microsoft /proc/version 2>/dev/null || grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
  IS_WSL=1
  echo "🐧 WSL environment detected."
fi

# --- Node.js via NVM ---
echo "📦 Setting up Node.js (Current and LTS versions)..."

# Install NVM
echo "Installing NVM (Node Version Manager)..."
export NVM_DIR="$HOME/.nvm"
mkdir -p "$NVM_DIR"

# Get the latest NVM version
NVM_VERSION=$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep "tag_name" | cut -d '"' -f 4)
if [ -z "$NVM_VERSION" ]; then
  NVM_VERSION="v0.39.5" # Fallback to a known version if GitHub API fails
fi

curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash

# Load NVM immediately
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm

# Add NVM to shell profiles if not already present
for PROFILE in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
  if [ -f "$PROFILE" ]; then
    if ! grep -q "NVM_DIR" "$PROFILE"; then
      echo '# NVM Configuration' >> "$PROFILE"
      echo 'export NVM_DIR="$HOME/.nvm"' >> "$PROFILE"
      echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm' >> "$PROFILE"
      echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion' >> "$PROFILE"
    fi
  fi
done

# Install latest LTS version of Node.js
echo "Installing Node.js LTS version..."
nvm install --lts
nvm use --lts

# Install current version of Node.js
echo "Installing Node.js Current version..."
nvm install node

# Set default to LTS
echo "Setting Node.js LTS as default..."
nvm alias default lts/*

# Install essential global packages
echo "Installing essential global npm packages..."
npm install -g npm@latest
npm install -g yarn pnpm nx @angular/cli typescript ts-node eslint prettier

# Display installed versions
echo "Installed Node.js versions:"
nvm ls
echo "Current Node.js version: $(node -v)"
echo "Current npm version: $(npm -v)"

# --- Python Latest Setup ---
echo "🐍 Setting up Python latest version..."

# Install Python core packages
sudo apt update
sudo apt install -y python3 python3-pip python3-dev python3-venv python3-setuptools python3-wheel

# Install pyenv for Python version management
echo "Installing pyenv for Python version management..."
curl https://pyenv.run | bash

# Add pyenv to shell profiles if not already present
for PROFILE in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
  if [ -f "$PROFILE" ]; then
    if ! grep -q "pyenv" "$PROFILE"; then
      echo '# pyenv Configuration' >> "$PROFILE"
      echo 'export PYENV_ROOT="$HOME/.pyenv"' >> "$PROFILE"
      echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"' >> "$PROFILE"
      echo 'eval "$(pyenv init -)"' >> "$PROFILE"
    fi
  fi
done

# Load pyenv immediately
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# Install Python build dependencies
sudo apt install -y build-essential libssl-dev zlib1g-dev libbz2-dev \
  libreadline-dev libsqlite3-dev curl libncursesw5-dev xz-utils \
  tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev

# Install the latest Python version
LATEST_PYTHON=$(pyenv install --list | grep -v "a\|b\|rc" | grep -E "^  3\.[0-9]+\.[0-9]+$" | tail -1 | xargs)
echo "Installing latest Python version: $LATEST_PYTHON"
pyenv install -s "$LATEST_PYTHON"
pyenv global "$LATEST_PYTHON"

# Upgrade pip to latest version
python -m pip install --upgrade pip

# Install essential Python packages
python -m pip install --user pipx
python -m pipx ensurepath
python -m pip install --user pipenv virtualenv poetry

# Display installed Python versions
echo "Python version: $(python --version)"
echo "Pip version: $(pip --version)"

echo "✅ Node.js and Python setup completed!"
