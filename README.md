# Ubuntu Development Environment Setup

[![CI/CD Status](https://github.com/your-org/ubuntu-dev-setup/workflows/Ubuntu%20Dev%20Environment%20CI%2FCD/badge.svg)](https://github.com/your-org/ubuntu-dev-setup/actions)
[![Compliance](https://img.shields.io/badge/Compliance-85%25-green)](./docs/compliance-report.md)
[![Security](https://img.shields.io/badge/Security-Validated-green)](./docs/security-report.md)
[![Version](https://img.shields.io/badge/Version-2.0.0-blue)](./CHANGELOG.md)
[![License](https://img.shields.io/badge/License-MIT-blue)](./LICENSE)

🚀 **Production-ready, enterprise-grade Ubuntu development environment setup** with intelligent automation, comprehensive testing, and security-first design.

## 🚀 Features

- **Environment Detection**: Automatically detects WSL2, Ubuntu Desktop, or headless environments
- **Container Development**: Installs containerd (v2.1.1), BuildKit (v0.24.0), and nerdctl (v2.1.2)
- **Modern Development Tools**: Current Node.js/npm, latest Python 3.12, .NET SDKs, PowerShell
- **Code Editors**: VS Code and VS Code Insiders with extensions and optimized settings
- **WSL2 Optimization**: Enhanced WSL2 configuration for better performance
- **Desktop Environment**: Complete desktop setup with productivity and development applications
- **Modular Design**: Individual scripts for specific components, run separately or together
- **Robust Error Handling**: Proper error handling with comprehensive logging and recovery options
- **Safe Script Sourcing**: Scripts can be safely sourced multiple times without variable conflicts

## 📋 Prerequisites

- Ubuntu 20.04 LTS or newer (Desktop or WSL2)
- Internet connection for downloading packages
- Sudo privileges

## 🎯 Quick Start

### Clone and Setup

## 📦 Available Components

| Component | Description | Flag |
|-----------|-------------|------|
| All Components | Complete development environment | `--all` |
| Desktop | Desktop environment setup | `--desktop` |
| Node & Python | Node.js and Python with version managers | `--node-python` |
| Dev Tools | CLI dev tools, linters, shells, etc. | `--devtools` |
| Dev Containers | Docker Desktop or containerd/devcontainers | `--devcontainers` |
| .NET & AI | .NET, PowerShell, AI/ML tools | `--dotnet-ai` |
| Language SDKs | Java, Rust, Haskell | `--lang-sdks` |
| Terminal | Terminal enhancements | `--terminal` |
| NPM Packages | Global and local NPM packages | `--npm` |

## 🧰 Utility Modules

| Module | Description |
|--------|-------------|
| `util-env.sh` | Environment detection and system info |
| `util-log.sh` | Logging and error handling |
| `util-packages.sh` | Package management utilities |
| `util-versions.sh` | Version comparison and management |
| `util-wsl.sh` | WSL-specific utilities |
| `util-containers.sh` | Container runtime utilities |

## 🔧 Usage Examples

### Full Installation

```bash
# Install everything with a single command
./install-new.sh --all
```

### Installing Specific Components

```bash
# Install only developer tools and VS Code
./install-new.sh --devtools

# Install Node.js, Python, and container development tools
./install-new.sh --node-python --devcontainers
```

### Maintenance & Updates

```bash
# Update the development environment
./update-environment.sh

# Check installed versions
./validate-installation.sh
```

```bash
# Install modern CLI tools and shell enhancements
# Note: VS Code installation needs to be added
./setup-devtools.sh
```

### Node.js and Python

```bash
# Install Node.js LTS/Current and Python 3.12
./setup-node-python.sh
```

## 🖥️ Environment-Specific Behavior

### Ubuntu Desktop

- Installs GUI applications (LibreOffice, multimedia tools)
- Sets up desktop environment optimizations  
- Configures fonts and themes
- VS Code Insiders set as default git editor

> **Note**: For WSL2 users, install VS Code and VS Code Insiders on Windows, not inside WSL2. The Windows installations will connect to WSL2 automatically.

### Ubuntu on WSL2

- Skips GUI applications (install VS Code on Windows instead)
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
- **.NET**: SDKs 8.0, 9.0, 10.0
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

- **Git**: Enhanced with GitLens, advanced configuration
- **Modern CLI**: bat, ripgrep, exa, fd, fzf, zoxide
- **Shell**: Zsh with Oh My Zsh, Starship prompt
- **Terminal**: tmux with plugin manager

> **Note**: VS Code should be installed on Windows for WSL2 users, or locally for Desktop users.

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

> **Important**: For WSL2 users, install VS Code and VS Code Insiders on Windows. The scripts will configure Git integration to use the Windows installations.

### Recommended Extensions

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

> **WSL2 Setup**: The scripts automatically configure Git to use Windows VS Code Insiders as the editor. VS Code extensions and settings are managed on the Windows side.

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
./setup-devtools.sh    # Modern CLI tools and shell setup
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

## ⚙️ Technical Implementation

### Variable Management

To avoid readonly variable redeclaration errors when scripts are sourced multiple times, the codebase follows these patterns:

1. **Guard Variables**: Each utility script has a guard variable like `UTIL_LOG_LOADED` to prevent multiple sourcing
2. **Conditional Declarations**: Global variables are only declared if they don't already exist
3. **Export Management**: Variables intended for global use are properly exported
4. **Script-Scoped Variables**: Each utility has its own version and metadata variables
5. **Avoiding Conflicts**: `SCRIPT_DIR` handling is coordinated across scripts

### Testing

The repository includes a comprehensive test script (`ubuntu-dev-test.sh`) that verifies:

- Proper utility loading without variable conflicts
- Dependency resolution working correctly
- Script compatibility with different environments
