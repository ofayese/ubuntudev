# Ubuntu Development Environment Setup - Installation Guide

🚀 **Version 1.0.1** - Comprehensive development environment installer for Ubuntu 22.04/24.04 LTS and WSL2

## Quick Start

```bash
# Clone and run installer
git clone <your-repo-url> ~/ubuntudev
cd ~/ubuntudev/src
./install-new-refactored.sh --all
```

## Prerequisites

- Ubuntu 22.04/24.04 LTS (native or WSL2)
- Internet connection
- `sudo` privileges
- At least 5GB free disk space

## Installation Options

### 🎯 **Recommended: Complete Setup**

Install everything for a full development environment:

```bash
./install-new-refactored.sh --all
```

### 🔧 **Custom Component Installation**

Choose specific components based on your needs:

```bash
# Essential development tools
./install-new-refactored.sh --devtools

# Modern terminal tools + essential dev tools
./install-new-refactored.sh --devtools --terminal-enhancements

# Web development stack
./install-new-refactored.sh --devtools --node-python --npm

# Full development environment with containers
./install-new-refactored.sh --devtools --terminal-enhancements --devcontainers --lang-sdks

# .NET and AI/ML development
./install-new-refactored.sh --devtools --dotnet-ai --lang-sdks
```

## Available Components

| Component | Description | Dependencies |
|-----------|-------------|--------------|
| `--devtools` | Essential development tools (git, vim, curl, build tools) | None |
| `--terminal-enhancements` | Modern CLI tools (bat, ripgrep, fzf, eza, zoxide) | devtools |
| `--desktop` | Desktop environment enhancements (Ubuntu Desktop only) | devtools |
| `--devcontainers` | Development containers setup (Docker/Podman) | devtools |
| `--dotnet-ai` | .NET SDKs, PowerShell, AI/ML tools (Python, PyTorch, TensorFlow) | devtools |
| `--lang-sdks` | Language SDKs (Rust, Java/SDKMAN, Haskell/GHCup) | devtools |
| `--node-python` | Node.js (via NVM) and Python (via pyenv) | devtools |
| `--npm` | Global NPM packages for development | node-python |
| `--vscommunity` | Visual Studio Community 2022 (WSL2 only) | devtools |
| `--update-env` | Environment updates and optimizations | None |

## Command Line Options

### Installation Modes

```bash
# Install specific components
./install-new-refactored.sh --devtools --terminal-enhancements

# Install everything
./install-new-refactored.sh --all

# Resume from previous failed installation
./install-new-refactored.sh --resume

# Preview what would be installed (no changes made)
./install-new-refactored.sh --all --dry-run
```

### Utility Options

```bash
# Generate dependency graph
./install-new-refactored.sh --graph

# Run validation checks only
./install-new-refactored.sh --validate

# Skip prerequisite checks (advanced users)
./install-new-refactored.sh --skip-prereqs --devtools

# Enable debug mode for troubleshooting
./install-new-refactored.sh --debug --devtools
```

## Environment Variables

Set these before running the installer for advanced control:

```bash
# Enable dry-run mode
export DRY_RUN=true
./install-new-refactored.sh --devtools

# Enable debug output
export DEBUG_MODE=true
./install-new-refactored.sh --devtools

# Skip prerequisite checks
export SKIP_PREREQS=true
./install-new-refactored.sh --devtools
```

## Usage Examples

### 🎯 **Common Scenarios**

#### New Developer Setup

```bash
# Complete development environment
./install-new-refactored.sh --all
```

#### Web Developer

```bash
# Node.js, Python, modern tools
./install-new-refactored.sh --devtools --terminal-enhancements --node-python --npm
```

#### Systems Developer

```bash
# Rust, C/C++, containers
./install-new-refactored.sh --devtools --terminal-enhancements --lang-sdks --devcontainers
```

#### Data Scientist / AI Developer

```bash
# Python, .NET, AI tools
./install-new-refactored.sh --devtools --dotnet-ai --node-python
```

#### Enterprise Developer (WSL2)

```bash
# Full stack including Visual Studio
./install-new-refactored.sh --all --vscommunity
```

### 🔍 **Testing and Validation**

```bash
# Preview what would be installed
./install-new-refactored.sh --dry-run --devtools --terminal-enhancements

# Check system compatibility
./install-new-refactored.sh --validate

# View dependency relationships
./install-new-refactored.sh --graph
```

### 🛠️ **Troubleshooting**

```bash
# Resume interrupted installation
./install-new-refactored.sh --resume

# Debug mode for detailed output
./install-new-refactored.sh --debug --devtools

# Force reinstall specific component
rm ~/.ubuntu-devtools.state
./install-new-refactored.sh --devtools
```

## Post-Installation

### 🔄 **Environment Activation**

After installation, restart your shell or source your profile:

```bash
# Restart shell (recommended)
exec $SHELL

# Or source profile manually
source ~/.bashrc
# source ~/.zshrc  # if using zsh
```

### ✅ **Verification**

Verify your installation:

```bash
# Check installed tools
which git node python3 cargo rustc java

# Check versions
./validate-installation.sh

# Test modern CLI tools (if terminal-enhancements installed)
bat --version
rg --version
fzf --version
eza --version
```

### 🔧 **Configuration**

Key configuration files created:

- `~/.bashrc` - Shell configuration
- `~/.gitconfig` - Git configuration  
- `~/.cargo/env` - Rust environment
- `~/.sdkman/` - Java SDK management
- `~/.pyenv/` - Python version management
- `~/.nvm/` - Node.js version management

## File Locations

| Type | Location | Description |
|------|----------|-------------|
| **Logs** | `~/.local/share/ubuntu-dev-tools/logs/` | Installation logs |
| **State** | `~/.ubuntu-devtools.state` | Installation state tracking |
| **Config** | `dependencies.yaml` | Component dependencies |
| **Scripts** | `~/ubuntudev/src/` | Setup scripts |

## Environment Detection

The installer automatically detects:

- ✅ **Ubuntu Version**: 22.04/24.04 LTS
- ✅ **WSL2**: Windows Subsystem for Linux
- ✅ **Desktop Environment**: GNOME, KDE, etc.
- ✅ **System Architecture**: x86_64, ARM64
- ✅ **Package Manager**: apt, snap availability
- ✅ **Existing Tools**: Prevents conflicts

## Safety Features

- 🛡️ **Dry-run mode**: Preview changes before applying
- 🔄 **Resume capability**: Continue from interruptions
- 📝 **Comprehensive logging**: Detailed operation logs
- ✅ **Dependency validation**: Ensures correct installation order
- 🎯 **Idempotent**: Safe to run multiple times
- 🚫 **Conflict detection**: Avoids overwriting existing configurations

## Error Handling

If installation fails:

1. **Check logs**: `~/.local/share/ubuntu-dev-tools/logs/`
2. **Resume installation**: `./install-new-refactored.sh --resume`
3. **Debug mode**: `./install-new-refactored.sh --debug --<component>`
4. **Reset state**: `rm ~/.ubuntu-devtools.state` and retry

## System Requirements

### Minimum

- Ubuntu 22.04 LTS or later
- 4GB RAM
- 5GB free disk space
- Internet connection

### Recommended

- Ubuntu 24.04 LTS
- 8GB+ RAM
- 20GB+ free disk space
- Fast internet connection

## Platform Support

| Platform | Support Level | Notes |
|----------|---------------|-------|
| **Ubuntu 24.04 LTS** | ✅ Full | Recommended platform |
| **Ubuntu 22.04 LTS** | ✅ Full | Fully supported |
| **WSL2 Ubuntu** | ✅ Full | Windows integration |
| **Ubuntu 20.04 LTS** | ⚠️ Limited | Some packages may be outdated |
| **Other Debian** | ⚠️ Untested | May work but not guaranteed |

## Support

- 📖 **Documentation**: See `docs/` directory
- 🐛 **Issues**: Check installation logs first
- 🔧 **Debugging**: Use `--debug` and `--validate` flags
- 📊 **Dependencies**: Use `--graph` to visualize

---

**Last Updated**: June 14, 2025  
**Version**: 1.0.1  
**Compatibility**: Ubuntu 22.04/24.04 LTS, WSL2
