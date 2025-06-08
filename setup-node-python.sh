#!/bin/bash
set -euo pipefail

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
echo "📦 Setting up Node.js (LTS: v22.16.0, Current: v24.1.0)..."

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
nvm install 22.16.0
nvm install 24.1.0

# Set default to LTS
nvm alias default 22.16.0
nvm use 22.16.0

# Install global npm packages
npm install -g npm@latest
npm install -g yarn pnpm nx @angular/cli typescript ts-node eslint prettier

echo "📦 Installed Node.js versions:"
nvm ls
echo "👉 Current Node.js version: $(node -v)"
echo "👉 Current npm version: $(npm -v)"

# === Python Setup via pyenv ===
echo "🐍 Setting up Python (3.12 & 3.13)..."

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

# Install specific versions
pyenv install -s 3.12.3
pyenv install -s 3.13.0b1
pyenv global 3.13.0b1  # Set latest as default

# Upgrade pip and install tools
python -m pip install --upgrade pip
python -m pip install --user pipx
python -m pipx ensurepath
python -m pip install --user pipenv virtualenv poetry

# Show results
echo "🐍 Python version: $(python --version)"
echo "📦 Pip version: $(pip --version)"

echo "✅ Node.js and Python environments are fully set up!"
