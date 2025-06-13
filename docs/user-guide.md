# Ubuntu Development Environment Setup - User Guide

![Ubuntu Dev Setup](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-orange?logo=ubuntu)
![WSL2 Compatible](https://img.shields.io/badge/WSL2-Compatible-blue?logo=windows)
![Version](https://img.shields.io/badge/Version-2.0.0-green)
![License](https://img.shields.io/badge/License-MIT-blue)

## Table of Contents

- [Quick Start](#quick-start)
- [Installation Methods](#installation-methods)
- [Environment Types](#environment-types)
- [Core Components](#core-components)
- [Advanced Configuration](#advanced-configuration)
- [Troubleshooting](#troubleshooting)
- [Performance Optimization](#performance-optimization)
- [Security Considerations](#security-considerations)
- [Maintenance](#maintenance)

## Quick Start

### 1. Prerequisites Check

Before installation, verify your system meets the requirements:

```bash
./check-prerequisites.sh
```

**Minimum Requirements:**

- Ubuntu 20.04+ (or compatible distribution)
- 4GB RAM (8GB recommended)
- 20GB free disk space
- Internet connection
- Sudo access (for package installation)

### 2. One-Command Installation

For a complete development environment:

```bash
./install-new.sh --all
```

For a customized installation:

```bash
./install-new.sh --interactive
```

### 3. Validation

Verify your installation:

```bash
./validate-installation.sh
```

## Installation Methods

### Interactive Installation (Recommended)

The interactive installer guides you through component selection:

```bash
./install-new.sh --interactive
```

**Features:**

- Component selection wizard
- Environment-specific recommendations
- Real-time validation
- Rollback on failure

### Silent/Automated Installation

For CI/CD or automated deployments:

```bash
# Complete installation
./install-new.sh --all --silent

# Specific components
./install-new.sh --components="nodejs,python,docker" --silent

# With configuration file
./install-new.sh --config=./custom-config.yaml --silent
```

### Dry-Run Mode

Test your installation without making changes:

```bash
./install-new.sh --all --dry-run
```

## Environment Types

### WSL2 Environment

**Automatic Detection:** The installer automatically detects WSL2 and optimizes accordingly.

**WSL2-Specific Features:**

- Windows integration for VS Code
- File system optimization
- Memory management tuning
- Docker Desktop integration

**Manual WSL2 Setup:**

```bash
export FORCE_ENVIRONMENT="wsl"
./install-new.sh --wsl-optimized
```

### Desktop Environment

**Automatic Detection:** Identifies GNOME, KDE, XFCE, and other desktop environments.

**Desktop-Specific Features:**

- GUI application installation
- Desktop shortcuts
- System tray integrations
- Clipboard sharing

**Manual Desktop Setup:**

```bash
export FORCE_ENVIRONMENT="desktop"
./install-new.sh --desktop
```

### Headless/Server Environment

**Automatic Detection:** Identifies headless servers and containers.

**Headless-Specific Features:**

- CLI-only tools
- Service configuration
- Resource optimization
- Remote access setup

**Manual Headless Setup:**

```bash
export FORCE_ENVIRONMENT="headless"
./install-new.sh --headless
```

## Core Components

### Development Languages

#### Node.js & npm

```bash
./setup-node-python.sh --nodejs-only
```

**Installed Components:**

- Node.js (LTS version)
- npm package manager
- yarn (optional)
- Global development tools

**Configuration:**

- Automatic version management
- Global package optimization
- WSL2 path integration

#### Python Development

```bash
./setup-node-python.sh --python-only
```

**Installed Components:**

- Python 3.9+
- pip package manager
- Virtual environment tools
- Development libraries

**Configuration:**

- Multiple Python versions
- Virtual environment automation
- IDE integration

#### Additional Languages

```bash
./setup-lang-sdks.sh
```

**Supported Languages:**

- Go
- Rust
- Java (OpenJDK)
- .NET Core
- PHP

### Development Tools

#### Git & Version Control

```bash
./setup-devtools.sh --git-only
```

**Configuration:**

- Global Git settings
- SSH key generation
- GPG signing setup
- Git aliases and hooks

#### Docker & Containers

```bash
./setup-devtools.sh --docker-only
```

**Components:**

- Docker Engine
- Docker Compose
- Development containers
- Registry configuration

#### Code Editors

##### VS Code

```bash
./setup-devtools.sh --vscode
```

**Features:**

- Extensions marketplace
- Settings synchronization
- GitHub Copilot integration
- Remote development support

##### VS Code Insiders

```bash
./setup-devtools.sh --vscode-insiders
```

##### Visual Studio Community (Windows-compatible)

```bash
./setup-vscommunity.sh
```

### Terminal Enhancements

```bash
./setup-terminal-enhancements.sh
```

**Components:**

- Zsh with Oh My Zsh
- Powerful aliases
- Syntax highlighting
- Auto-completion
- Theme customization

## Advanced Configuration

### Configuration Files

#### Main Configuration

Create `config/environment.conf`:

```bash
# Environment Configuration
INSTALL_NODEJS=true
INSTALL_PYTHON=true
INSTALL_DOCKER=true
INSTALL_VSCODE=true

# Version Preferences
NODEJS_VERSION="lts"
PYTHON_VERSION="3.11"

# Environment Settings
ENVIRONMENT_TYPE="auto"  # auto, wsl, desktop, headless
PERFORMANCE_MODE="balanced"  # minimal, balanced, maximum

# Feature Flags
ENABLE_COPILOT=true
ENABLE_CONTAINERS=true
ENABLE_MONITORING=false
```

#### Component-Specific Configuration

**Docker Configuration (`config/docker.conf`):**

```bash
# Docker Configuration
DOCKER_EDITION="ce"
DOCKER_COMPOSE_VERSION="latest"
ENABLE_BUILDKIT=true
REGISTRY_MIRRORS=["https://mirror.gcr.io"]
```

**Development Configuration (`config/development.conf`):**

```bash
# Development Tools
DEFAULT_EDITOR="code"
GIT_DEFAULT_BRANCH="main"
SSH_KEY_TYPE="ed25519"
ENABLE_GIT_LFS=true
```

### Environment Variables

#### Performance Tuning

```bash
# Performance Settings
export MAX_PARALLEL_JOBS=4
export CACHE_ENABLED=true
export PERFORMANCE_MODE="balanced"

# Memory Management
export NODE_OPTIONS="--max-old-space-size=4096"
export PYTHONDONTWRITEBYTECODE=1
```

#### Development Settings

```bash
# Development Environment
export DEVELOPMENT_MODE=true
export DEBUG_ENABLED=false
export LOG_LEVEL="info"

# Editor Preferences
export EDITOR="code"
export VISUAL="code"
```

### Custom Installation Profiles

#### Profile: Minimal Developer

```bash
./install-new.sh --profile=minimal
```

**Components:**

- Git
- Node.js
- VS Code
- Basic terminal tools

#### Profile: Full Stack Developer

```bash
./install-new.sh --profile=fullstack
```

**Components:**

- Multiple languages (Node.js, Python, Go)
- Docker & containers
- Multiple editors
- Database tools
- Testing frameworks

#### Profile: DevOps Engineer

```bash
./install-new.sh --profile=devops
```

**Components:**

- Container orchestration
- Cloud CLI tools
- Infrastructure as Code
- Monitoring tools
- Security scanners

## Troubleshooting

### Common Issues

#### Installation Failures

**Issue:** Package installation fails

```bash
# Check prerequisites
./check-prerequisites.sh

# Update package lists
sudo apt update

# Retry with verbose logging
./install-new.sh --verbose --retry
```

**Issue:** Docker permission denied

```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Restart shell or logout/login
newgrp docker
```

**Issue:** VS Code integration problems

```bash
# Reset VS Code settings
./setup-devtools.sh --vscode --reset

# Check WSL integration
./validate-installation.sh --component=vscode
```

#### Environment Detection Issues

**Issue:** WSL2 not detected properly

```bash
# Force WSL2 mode
export FORCE_ENVIRONMENT="wsl"
./install-new.sh --reconfigure
```

**Issue:** Desktop environment not recognized

```bash
# Manual desktop setup
export XDG_CURRENT_DESKTOP="GNOME"  # or KDE, XFCE, etc.
./setup-desktop.sh --force
```

#### Performance Issues

**Issue:** Slow installation

```bash
# Enable parallel processing
export MAX_PARALLEL_JOBS=8

# Use local mirrors
./install-new.sh --use-local-mirrors

# Check system resources
./performance-optimizer.sh --analyze
```

**Issue:** High memory usage

```bash
# Enable memory optimization
./performance-optimizer.sh --optimize-memory

# Check for memory leaks
./validate-installation.sh --performance-check
```

### Debug Mode

Enable detailed logging:

```bash
# Full debug output
export DEBUG=true
./install-new.sh --verbose

# Component-specific debugging
export DEBUG_COMPONENTS="docker,nodejs"
./install-new.sh --debug-components
```

### Log Files

**Location:** `~/.local/share/ubuntu-dev-tools/logs/`

**Key Files:**

- `ubuntu-dev-tools.log` - Main installation log
- `performance.log` - Performance metrics
- `error.log` - Error details
- `debug.log` - Debug information

**Log Analysis:**

```bash
# View recent errors
tail -f ~/.local/share/ubuntu-dev-tools/logs/error.log

# Search for specific issues
grep -i "docker" ~/.local/share/ubuntu-dev-tools/logs/ubuntu-dev-tools.log

# Performance analysis
./performance-optimizer.sh --analyze-logs
```

### Recovery and Rollback

#### Automatic Rollback

Most scripts support automatic rollback on failure:

```bash
# Installation with automatic rollback
./install-new.sh --with-rollback

# Manual rollback to checkpoint
./install-new.sh --rollback-to="$(date -d '1 hour ago' +%s)"
```

#### Manual Recovery

```bash
# Reset to clean state
./cleanup-environment.sh --full-reset

# Repair broken installation
./validate-installation.sh --repair

# Reinstall specific components
./install-new.sh --components="docker" --force-reinstall
```

## Performance Optimization

### Caching

#### Enable Caching

```bash
# Enable global caching
export CACHE_ENABLED=true
./performance-optimizer.sh --setup-cache

# Cache-aware installation
./install-new.sh --with-cache
```

#### Cache Management

```bash
# View cache status
./performance-optimizer.sh --cache-status

# Clear cache
./performance-optimizer.sh --clear-cache

# Optimize cache
./performance-optimizer.sh --optimize-cache
```

### Resource Optimization

#### Memory Optimization

```bash
# Optimize for low-memory systems
./performance-optimizer.sh --memory-profile=low

# Monitor memory usage
./performance-optimizer.sh --monitor-memory
```

#### Disk Optimization

```bash
# Optimize disk usage
./performance-optimizer.sh --optimize-disk

# Clean unnecessary files
./performance-optimizer.sh --cleanup-disk
```

#### Network Optimization

```bash
# Use fastest mirrors
./performance-optimizer.sh --optimize-mirrors

# Enable download acceleration
export PARALLEL_DOWNLOADS=true
./install-new.sh --fast-download
```

### Performance Monitoring

#### Real-time Monitoring

```bash
# Enable performance monitoring
./performance-optimizer.sh --enable-monitoring

# View performance dashboard
./performance-optimizer.sh --dashboard
```

#### Performance Reports

```bash
# Generate performance report
./performance-optimizer.sh --report

# Benchmark system
./performance-optimizer.sh --benchmark

# Compare with baseline
./performance-optimizer.sh --compare-baseline
```

## Security Considerations

### Security Scanning

#### Pre-installation Security Check

```bash
# Security assessment
./check-prerequisites.sh --security-scan

# Vulnerability scanning
./security-scan.sh --full-scan
```

#### Post-installation Security Validation

```bash
# Validate security configuration
./validate-installation.sh --security-check

# Check for security updates
./update-environment.sh --security-only
```

### Secure Configuration

#### SSH Key Management

```bash
# Generate secure SSH keys
./setup-devtools.sh --generate-ssh-keys

# Configure SSH security
./setup-devtools.sh --secure-ssh
```

#### Container Security

```bash
# Secure Docker configuration
./setup-devtools.sh --secure-docker

# Scan container images
./validate-docker-images.sh --security-scan
```

#### File Permissions

```bash
# Secure file permissions
find ~/dev-tools -type f -exec chmod 644 {} \;
find ~/dev-tools -type d -exec chmod 755 {} \;

# Secure sensitive files
chmod 600 ~/.ssh/*
chmod 700 ~/.ssh
```

### Security Updates

#### Automatic Updates

```bash
# Enable automatic security updates
./update-environment.sh --enable-auto-security

# Configure update schedule
./update-environment.sh --schedule="0 2 * * *"  # Daily at 2 AM
```

#### Manual Updates

```bash
# Check for updates
./update-environment.sh --check-updates

# Apply security updates
./update-environment.sh --security-updates

# Full system update
./update-environment.sh --full-update
```

## Maintenance

### Regular Maintenance

#### Weekly Maintenance

```bash
# Run weekly maintenance script
./maintenance.sh --weekly

# Or run individual tasks:
./update-environment.sh --check-updates
./performance-optimizer.sh --optimize
./validate-installation.sh --health-check
```

#### Monthly Maintenance

```bash
# Run monthly maintenance
./maintenance.sh --monthly

# Deep cleaning and optimization
./performance-optimizer.sh --deep-clean
./update-environment.sh --major-updates
```

### Health Monitoring

#### System Health

```bash
# Quick health check
./validate-installation.sh --quick-check

# Comprehensive health assessment
./validate-installation.sh --comprehensive

# Generate health report
./validate-installation.sh --health-report
```

#### Performance Health

```bash
# Performance health check
./performance-optimizer.sh --health-check

# Performance trending
./performance-optimizer.sh --trend-analysis

# Performance recommendations
./performance-optimizer.sh --recommendations
```

### Backup and Restore

#### Configuration Backup

```bash
# Backup configuration
./backup-config.sh --full-backup

# Backup specific components
./backup-config.sh --components="vscode,git,terminal"
```

#### Restore Configuration

```bash
# Restore from backup
./restore-config.sh --from-backup="backup-20241213.tar.gz"

# Selective restore
./restore-config.sh --components="vscode" --from-backup="backup-20241213.tar.gz"
```

### Updates and Upgrades

#### Component Updates

```bash
# Update specific components
./update-environment.sh --components="nodejs,python"

# Major version upgrades
./update-environment.sh --major-upgrades

# Preview available updates
./update-environment.sh --preview-updates
```

#### Environment Migration

```bash
# Migrate to new Ubuntu version
./migrate-environment.sh --to-version="24.04"

# Export environment for migration
./export-environment.sh --full-export

# Import environment on new system
./import-environment.sh --from-export="environment-export.tar.gz"
```

## Support and Community

### Getting Help

#### Documentation

- [GitHub Repository](https://github.com/your-org/ubuntu-dev-setup)
- [Wiki](https://github.com/your-org/ubuntu-dev-setup/wiki)
- [FAQ](https://github.com/your-org/ubuntu-dev-setup/wiki/FAQ)

#### Community Support

- [Discord Community](https://discord.gg/ubuntu-dev)
- [GitHub Discussions](https://github.com/your-org/ubuntu-dev-setup/discussions)
- [Stack Overflow Tag](https://stackoverflow.com/questions/tagged/ubuntu-dev-setup)

#### Professional Support

- [Enterprise Support](mailto:enterprise@ubuntu-dev-setup.com)
- [Consulting Services](https://ubuntu-dev-setup.com/consulting)

### Contributing

#### Bug Reports

1. Check existing issues
2. Use the issue template
3. Provide reproduction steps
4. Include system information

#### Feature Requests

1. Discuss in GitHub Discussions first
2. Create detailed feature request
3. Consider implementation complexity
4. Offer to help with development

#### Pull Requests

1. Fork the repository
2. Create feature branch
3. Follow coding standards
4. Add tests and documentation
5. Submit pull request

---

## Appendix

### Environment Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `INSTALL_*` | `true` | Component installation flags |
| `*_VERSION` | `latest` | Version specifications |
| `ENVIRONMENT_TYPE` | `auto` | Environment detection |
| `PERFORMANCE_MODE` | `balanced` | Performance optimization level |
| `CACHE_ENABLED` | `true` | Enable caching |
| `MAX_PARALLEL_JOBS` | `4` | Parallel execution limit |
| `DEBUG` | `false` | Debug mode |
| `LOG_LEVEL` | `info` | Logging verbosity |

### Command Reference

| Command | Purpose | Example |
|---------|---------|---------|
| `install-new.sh` | Main installer | `./install-new.sh --all` |
| `check-prerequisites.sh` | System validation | `./check-prerequisites.sh` |
| `validate-installation.sh` | Installation validation | `./validate-installation.sh` |
| `performance-optimizer.sh` | Performance management | `./performance-optimizer.sh --optimize` |
| `update-environment.sh` | Updates and maintenance | `./update-environment.sh --check-updates` |

### Troubleshooting Flowchart

```
Installation Issue
       ↓
Check Prerequisites
       ↓
Review Logs
       ↓
Common Issue? → Yes → Apply Known Fix
       ↓ No
Enable Debug Mode
       ↓
Retry Installation
       ↓
Still Failing? → Yes → Contact Support
       ↓ No
Success!
```

---

*Last updated: 2025-06-13*
*Version: 2.0.0*
