# Ubuntu Development Environment Setup

This repository contains a collection of scripts to set up a comprehensive development environment on Ubuntu Desktop or Ubuntu on WSL2.

## Improvements

- **Node.js**: Installs both current and LTS versions using NVM (Node Version Manager)
- **Python**: Installs the latest Python 3 version using pyenv
- **WSL2 Configuration**: Optimized wsl.conf with proper systemd support and network settings
- **VS Code Integration**: Enhanced setup for VS Code and VS Code Insiders with extensions and configurations
- **Modular Design**: Split functionality into logical modules for easier maintenance and customization

## Quick Start

### On Ubuntu Desktop:

```bash
# Clone this repository
git clone https://github.com/yourusername/ubuntu-dev-setup.git
cd ubuntu-dev-setup

# Make scripts executable
chmod +x *.sh

# Run the full installation
./install.sh all
```

### On Ubuntu WSL2:

```bash
# Clone this repository
git clone https://github.com/yourusername/ubuntu-dev-setup.git
cd ubuntu-dev-setup

# Make scripts executable
chmod +x *.sh

# Run the full installation
./install.sh all
```

## Scripts Overview

- **install.sh**: Main entry point script that coordinates other scripts
- **setup-desktop.sh**: Sets up desktop environment components (skipped on headless/WSL)
- **setup-devcontainers.sh**: Installs Docker, containerd, buildkit for container development
- **setup-devtools.sh**: Installs development tools like git, zsh, tmux, etc.
- **setup-dotnet-ai.sh**: Sets up .NET SDK and AI/ML tools
- **setup-npm.sh**: Installs Node.js development packages
- **setup-node-python.sh**: NEW! Installs Node.js (with NVM) and Python (with pyenv)
- **setup-wsl.sh**: NEW! Configures optimal WSL2 settings (runs only on WSL)
- **setup-vscode.sh**: NEW! Sets up VS Code and VS Code Insiders with extensions

## Installation Options

You can install specific components by providing them as arguments to the install.sh script:

```bash
./install.sh devcontainers desktop devtools dotnet-ai npm node-python wsl vscode
```

Or install everything with:

```bash
./install.sh all
```

## WSL-Specific Improvements

For WSL2 environments, the following optimizations are applied:

```
[boot]
systemd=true

[automount]
enabled = false
root = /
options=metadata,uid=1000,gid=1000,umask=022,fmask=111
mountFsTab = true

[interop]
enabled=true
appendWindowsPath=false

[network]
hostname = hpdevcore
generateHosts = true
generateResolvConf = true
```

These settings improve file system performance, enable systemd, and optimize networking in WSL2.

## For Windows Users

If you're preparing these scripts on Windows to deploy to Linux:

1. Use the included `fix-line-endings.ps1` script to ensure proper Linux line endings:
   ```powershell
   powershell -ExecutionPolicy Bypass -File fix-line-endings.ps1
   ```

2. After copying to Linux, make the scripts executable:
   ```bash
   chmod +x *.sh
   ```

## Notes

- The setup detects headless environments and skips GUI components automatically
- WSL-specific components are only applied when running in a WSL environment
- Node.js setup includes both current and LTS versions with NVM for easy switching
- Python setup includes the latest Python 3 release with virtual environment tools
