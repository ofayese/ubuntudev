# Ubuntu Development Environment Setup

A comprehensive collection of scripts to set up a modern development environment on Ubuntu Desktop or Ubuntu on WSL2. These scripts provide automated installation and configuration of development tools, container runtimes, programming languages, and desktop applications.

## 🚀 Features

- **Environment Detection**: Automatically detects WSL2, Ubuntu Desktop, or headless environments
- **Container Development**: Installs containerd (v2.1.1), BuildKit (v0.24.0), and nerdctl (v2.1.2)
- **Modern Development Tools**: Current Node.js/npm, latest Python 3.12, .NET SDKs, PowerShell
- **Code Editors**: VS Code and VS Code Insiders with extensions and optimized settings
- **WSL2 Optimization**: Enhanced WSL2 configuration for better performance
- **Desktop Environment**: Complete desktop setup with productivity and development applications
- **Modular Design**: Individual scripts for specific components, run separately or together

## 📋 Prerequisites

- Ubuntu 20.04 LTS or newer (Desktop or WSL2)
- Internet connection for downloading packages
- Sudo privileges

## 🎯 Quick Start

### Clone and Setup

```bash
# Clone this repository
git clone <repository-url>
cd ubuntudev

# Make scripts executable
chmod +x *.sh

# Fix line endings if coming from Windows
powershell -ExecutionPolicy Bypass -File fix-line-endings.ps1
```

### Install Everything

```bash
# Install all components (recommended)
./install.sh all

# Or install specific components
./install.sh devtools vscode node-python
```

## 📦 Available Components

| Component | Description | Script |
|-----------|-------------|--------|
| `devcontainers` | containerd, BuildKit, nerdctl for container development | `setup-devcontainers.sh` |
| `desktop` | Desktop applications, security, multimedia tools | `setup-desktop.sh` |
| `devtools` | Modern CLI tools, zsh, tmux, git configuration | `setup-devtools.sh` |
| `dotnet-ai` | .NET SDKs (8.0, 9.0, 10.0 if available), PowerShell, Miniconda | `setup-dotnet-ai.sh` |
| `node-python` | Node.js (LTS + Current), Python 3.12, version managers | `setup-node-python.sh` |
| `npm` | Global npm packages for development | `setup-npm.sh` |
| `vscode` | VS Code + VS Code Insiders with extensions | `setup-vscode.sh` |
| `wsl` | WSL-specific optimizations and configuration | `setup-wsl.sh` |

## 🔧 Individual Script Usage

### Container Development

```bash
# Install container tools (requires sudo)
sudo ./setup-devcontainers.sh
```

### Development Tools Install

```bash
# Install modern CLI tools and shell enhancements
./setup-devtools.sh
```

### VS Code Setup

```bash
# Install VS Code/Insiders (Desktop only) + extensions
./setup-vscode.sh
```

### Node.js and Python

```bash
# Install Node.js LTS/Current and Python 3.12
./setup-node-python.sh
```

## 🖥️ Environment-Specific Behavior

### Ubuntu Desktop

- Installs GUI applications (VS Code, LibreOffice, multimedia tools)
- Sets up desktop environment optimizations
- Configures fonts and themes
- VS Code Insiders set as default git editor

### Ubuntu on WSL2

- Skips GUI applications
- Applies WSL2-specific optimizations
- Creates optimized `/etc/wsl.conf`
- Configures Windows-WSL integration
- Sets git editor to use Windows VS Code Insiders

### Headless Ubuntu

- Installs only CLI tools and services
- Skips desktop-specific configurations
- Focuses on server/container workloads

## 📁 What Gets Installed

### Development Languages & Runtimes

- **Node.js**: LTS (v20.x) and Current via NodeSource + NVM
- **Python**: Latest 3.12.x via deadsnakes PPA + pyenv
- **.NET**: SDKs 8.0, 9.0 (10.0 if available)
- **Go**: Latest version
- **PowerShell**: Cross-platform PowerShell 7+

### Container & Orchestration

- **containerd**: v2.1.1 container runtime
- **BuildKit**: v0.24.0 for advanced builds
- **nerdctl**: v2.1.2 Docker-compatible CLI
- **Podman**: Alternative container runtime
- **Kind**: Kubernetes in Docker
- **Minikube**: Local Kubernetes

### Development Tools

- **VS Code**: Stable + Insiders with curated extensions
- **Git**: Enhanced with GitLens, advanced configuration
- **Modern CLI**: bat, ripgrep, exa, fd, fzf, zoxide
- **Shell**: Zsh with Oh My Zsh, Starship prompt
- **Terminal**: tmux with plugin manager

### Desktop Applications (Ubuntu Desktop only)

- **Productivity**: LibreOffice, Obsidian, Foliate
- **Development**: GitHub CLI, Dive (Docker explorer)
- **Multimedia**: VLC, GIMP, Audacity
- **System**: Timeshift, UFW firewall, TLP power management

## ⚙️ WSL2 Configuration

The script creates an optimized `/etc/wsl.conf`:

```ini
[boot]
systemd=true

[automount]
enabled = false
root = /
options = metadata,uid=1000,gid=1000,umask=022,fmask=111
mountFsTab = true

[interop]
enabled = true
appendWindowsPath = false

[network]
hostname = hpdevcore
generateHosts = true
generateResolvConf = true
```

## 🎨 VS Code Configuration

### Installed Extensions

- **Language Support**: Python, Go, C/C++, Rust, C#
- **Containers**: Remote-Containers, Docker, SSH, WSL
- **AI/Productivity**: GitHub Copilot, GitLens
- **Code Quality**: Prettier, ESLint, Pylint
- **Themes**: Material Theme, Material Icons

### Optimized Settings

- JetBrains Mono font with ligatures
- Format on save enabled
- Auto-save configured
- Python/Node.js defaults
- Dark theme with high contrast

## 🛠️ Version Management

### Node.js

- **NVM**: Manage multiple Node.js versions
- **Default**: LTS version set as default
- **Global packages**: Essential development tools

### Python

- **pyenv**: Install and switch between Python versions
- **pipx**: Isolated tool installations
- **Tools**: poetry, black, ruff, mypy, pre-commit

## 📊 Logging and Monitoring

- **Main log**: `/var/log/ubuntu-dev-tools.log`
- **Summary**: `/var/log/ubuntu-dev-setup-summary.txt`
- All script outputs are logged with timestamps
- Installation status tracked per component

## 🔍 Troubleshooting

### Common Issues

1. **Permission errors**: Ensure sudo access for system packages
2. **WSL2 changes**: Restart WSL2 after configuration changes
3. **PATH not updated**: Restart terminal or re-login
4. **Container tools**: May require logout/login for group changes

### Manual Fixes

```bash
# Restart WSL2 (from PowerShell)
wsl --shutdown

# Reload shell configuration
source ~/.bashrc

# Check container tools
nerdctl version
```

## 🔄 Updates and Maintenance

The scripts are designed to be idempotent - you can run them multiple times safely. To update:

```bash
# Update individual components
./setup-vscode.sh      # Update VS Code extensions
./setup-npm.sh --force # Force reinstall npm packages

# Update container tools
sudo ./setup-devcontainers.sh
```

## 🤝 Contributing

1. Test scripts in clean Ubuntu environment
2. Follow existing code style and error handling
3. Update README for new features
4. Ensure WSL2 and Desktop compatibility

## 📄 License

This project is open source. See individual tool licenses for their respective terms.

---

**Note**: After installation, especially on WSL2, restart your terminal or WSL instance for all changes to take effect. Some tools may require a full logout/login cycle.
