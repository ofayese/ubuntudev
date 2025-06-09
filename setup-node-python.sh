#!/bin/bash
set -euo pipefail

# Set non-interactive environment for apt
export DEBIAN_FRONTEND=noninteractive

LOGFILE="/var/log/ubuntu-dev-tools.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== [setup-node-python.sh] Started at $(date) ==="

# --- Detect if running in WSL ---
IS_WSL=0
if grep -qi microsoft /proc/version 2>/dev/null || grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
  IS_WSL=1
  echo "🐧 WSL environment detected."
fi

# === Node.js Setup via NVM ===
echo "📦 Setting up Node.js (LTS and Current)..."

export NVM_DIR="$HOME/.nvm"
mkdir -p "$NVM_DIR"

# Get latest NVM version from GitHub API
NVM_VERSION=$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep "tag_name" | cut -d '"' -f 4)
NVM_VERSION="${NVM_VERSION:-v0.39.7}"  # fallback if API fails

curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash

# Load NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

# Add NVM to shell profiles
for PROFILE in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
  if [ -f "$PROFILE" ] && ! grep -q "NVM_DIR" "$PROFILE"; then
    {
      echo ''
      echo '# NVM Configuration'
      echo 'export NVM_DIR="$HOME/.nvm"'
      echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'
      echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'
    } >> "$PROFILE"
  fi
done

# Install Node.js LTS and Current versions
echo "🔧 Installing Node.js LTS and Current versions..."
if ! nvm install --lts; then
    echo "⚠️ Failed to install LTS, trying specific version..."
    nvm install 20
fi

if ! nvm install node; then
    echo "⚠️ Failed to install current, trying specific version..."
    nvm install 22
fi

# Set LTS as default
nvm alias default --lts
nvm use --lts

# Install global npm packages
npm install -g npm@latest
npm install -g yarn pnpm nx @angular/cli typescript ts-node eslint prettier

echo "📦 Installed Node.js versions:"
nvm ls
echo "👉 Current Node.js version: $(node -v)"
echo "👉 Current npm version: $(npm -v)"

# === Python Setup via pyenv ===
echo "🐍 Setting up Python (3.12)..."

# Core dependencies
sudo apt update
sudo apt install -y python3 python3-pip python3-dev python3-venv python3-setuptools python3-wheel

# Install pyenv
curl https://pyenv.run | bash

# Add pyenv to shell profiles
for PROFILE in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
  if [ -f "$PROFILE" ] && ! grep -q "pyenv" "$PROFILE"; then
    {
      echo ''
      echo '# pyenv Configuration'
      echo 'export PYENV_ROOT="$HOME/.pyenv"'
      echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"'
      echo 'eval "$(pyenv init -)"'
    } >> "$PROFILE"
  fi
done

# Load pyenv
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# Install Python build dependencies
sudo apt install -y build-essential libssl-dev zlib1g-dev libbz2-dev \
  libreadline-dev libsqlite3-dev libncursesw5-dev xz-utils tk-dev \
  libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev curl

# Install specific Python versions (use stable releases)
echo "🔧 Installing Python versions..."

# Get available Python versions and install latest stable 3.12 and 3.11
if pyenv install --list | grep -E "^\s*3\.12\.[0-9]+$" | tail -1 | xargs pyenv install -s; then
    echo "✅ Latest Python 3.12.x installed"
else
    echo "⚠️ Failed to install Python 3.12.x, trying 3.11.x..."
    if pyenv install --list | grep -E "^\s*3\.11\.[0-9]+$" | tail -1 | xargs pyenv install -s; then
        echo "✅ Latest Python 3.11.x installed"
    else
        echo "❌ Failed to install any Python version"
        exit 1
    fi
fi

# Set the installed version as global default
INSTALLED_VERSION=$(pyenv versions --bare | grep -E "^3\.(12|11)\." | head -1)
if [ -n "$INSTALLED_VERSION" ]; then
    pyenv global "$INSTALLED_VERSION"
    echo "✅ Set Python $INSTALLED_VERSION as global default"
else
    echo "❌ No suitable Python version found"
    exit 1
fi

# Upgrade pip and install tools
python -m pip install --upgrade pip
python -m pip install --user pipx
python -m pipx ensurepath
python -m pip install --user pipenv virtualenv poetry

# Show results
echo "🐍 Python version: $(python --version)"
echo "📦 Pip version: $(pip --version)"

echo "✅ Node.js and Python environments are fully set up!"
