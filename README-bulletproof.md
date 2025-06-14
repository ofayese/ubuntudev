# 🚀 Ubuntu Development Environment - Bulletproof Installation Framework

[![Shellcheck](https://img.shields.io/badge/shellcheck-passing-brightgreen)](https://www.shellcheck.net/)
[![Version](https://img.shields.io/badge/version-1.0.0-blue)](./install-new-bulletproof.sh)
[![License](https://img.shields.io/badge/license-MIT-green)](./LICENSE)

A production-grade, modular installation framework for Ubuntu development environments with bulletproof utility sourcing and comprehensive error handling.

## ✨ Features

- **🔒 Bulletproof Sourcing**: Multi-sourcing safe utility modules without readonly conflicts
- **🛡️ Error Resilience**: Comprehensive error handling and recovery mechanisms  
- **🔧 Modular Design**: Clean separation of concerns across utility modules
- **🧪 Test Framework**: Automated testing for sourcing safety and functionality
- **📊 Dry Run Support**: Preview installations without making changes
- **🎯 Component Selection**: Install specific components or everything at once
- **📝 Production Logging**: Structured logging with multiple severity levels

## 🏗️ Architecture

### Core Utility Modules

| Module | Purpose | Key Functions |
|--------|---------|---------------|
| `util-log.sh` | Logging and error handling | `log_info`, `log_error`, `log_debug` |
| `util-deps.sh` | Dependency resolution | `load_dependencies`, `resolve_selected` |
| `util-install.sh` | Package installation | `safe_apt_install`, `install_component` |
| `util-wsl.sh` | WSL-specific configuration | `setup_wsl_environment`, `detect_wsl` |
| `util-versions.sh` | Version management | `setup_nvm`, `setup_pyenv`, `setup_sdkman` |

### Installation Components

- **devtools**: Core development tools (git, curl, build-essential)
- **terminal-enhancements**: Modern terminal tools (zsh, oh-my-zsh, starship)
- **desktop**: Desktop environment enhancements
- **devcontainers**: Development container support
- **dotnet-ai**: .NET development and AI tooling
- **lang-sdks**: Language SDKs (Node.js, Python, Java, etc.)
- **vscommunity**: VS Code and community extensions
- **update-env**: Environment updates and optimizations
- **validate**: Installation validation and health checks

## 🚀 Quick Start

### 1. Clone and Setup

```bash
git clone <repository-url>
cd ubuntudev
chmod +x *.sh
```

### 2. Install Everything

```bash
# Preview what will be installed
./install-new-bulletproof.sh --dry-run --all

# Install all components
./install-new-bulletproof.sh --all
```

### 3. Install Specific Components

```bash
# Install just development tools
./install-new-bulletproof.sh --component devtools

# Install multiple components
./install-new-bulletproof.sh --component devtools --component terminal-enhancements
```

## 🧪 Testing

### Automated Testing

```bash
# Test utility sourcing safety
make test-sourcing

# Run shellcheck linting
make lint  

# Run all tests
make test
```

### Manual Testing

```bash
# Test sourcing safety manually
./test-source-all.sh

# Test installer in dry-run mode
./install-new-bulletproof.sh --dry-run --all
```

## 📋 Available Commands

### Makefile Targets

```bash
make help           # Show available commands
make test          # Run all tests (sourcing + lint)
make test-sourcing # Test utility module sourcing safety
make lint          # Run shellcheck on all scripts
make install       # Run robust installer (--all)
make install-dry   # Run installer in dry-run mode
make clean         # Clean temporary files
make all           # Run tests and install
```

### Installer Options

```bash
./install-new-bulletproof.sh [OPTIONS]

Options:
  --all                Install all available components
  --component NAME     Install specific component
  --dry-run           Show what would be done without executing
  --help, -h          Show help message
```

## 🔧 Development

### Adding New Utility Modules

Follow the bulletproof template pattern:

```bash
#!/usr/bin/env bash
# Utility: util-newmodule.sh
# Description: Description of the new module
# Last Updated: 2025-06-13
# Version: 1.0.0

set -euo pipefail

# Load guard to prevent multiple sourcing
if [[ -n "${UTIL_NEWMODULE_SH_LOADED:-}" ]]; then
  return 0
fi
readonly UTIL_NEWMODULE_SH_LOADED=1

# Global Variable Initialization (Safe conditional pattern)
if [[ -z "${SCRIPT_DIR:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  readonly SCRIPT_DIR
fi

# ... other global variables following the same pattern

# Dependencies: Load required utilities
if [[ -z "${UTIL_LOG_SH_LOADED:-}" && -f "${SCRIPT_DIR}/util-log.sh" ]]; then
  source "${SCRIPT_DIR}/util-log.sh" || {
    echo "[ERROR] Failed to source util-log.sh" >&2
    exit 1
  }
fi

# Module Functions
your_function() {
  log_info "Implementing new functionality"
}
```

### Adding New Installation Components

1. Add component name to `ALL_COMPONENTS` array in `install-new-bulletproof.sh`
2. Add case handler in `install_component()` function
3. Implement the installation function
4. Test with `--dry-run` mode

## 🛡️ Security Features

- **Input Validation**: All user inputs are validated and sanitized
- **Trusted Sources**: Downloads only from pre-approved domains
- **Safe Temp Files**: Secure temporary file creation with proper cleanup
- **Error Boundaries**: Comprehensive error handling prevents partial installs
- **Rollback Support**: Installation state tracking for rollback capabilities

## 🔍 Troubleshooting

### Common Issues

**Problem**: `readonly variable` errors when sourcing utilities
**Solution**: Use the new bulletproof utilities - they handle multi-sourcing safely

**Problem**: Installation fails partway through
**Solution**: Check logs and use component-specific installation:

```bash
./install-new-bulletproof.sh --component <failed-component>
```

**Problem**: Permission denied errors
**Solution**: Ensure script is executable:

```bash
chmod +x install-new-bulletproof.sh
```

### Debug Mode

Enable debug logging:

```bash
DEBUG=true ./install-new-bulletproof.sh --dry-run --all
```

### Log Files

Logs are written to:

- Console output (color-coded by severity)
- Log file: `~/.local/share/ubuntu-dev-tools/logs/ubuntu-dev-tools.log`

## 📊 Project Structure

```
ubuntudev/
├── install-new-bulletproof.sh    # Main installer
├── test-source-all.sh            # Sourcing safety tests
├── Makefile-new                  # Build automation
├── util-log.sh                   # Logging utilities
├── util-deps.sh                  # Dependency management
├── util-install.sh               # Installation utilities
├── util-wsl.sh                   # WSL-specific functions
├── util-versions.sh              # Version management
└── README-bulletproof.md         # This documentation
```

## 🎯 Requirements

- **OS**: Ubuntu 20.04+ (LTS recommended)
- **Shell**: Bash 4.0+
- **Dependencies**: curl, wget (auto-installed if missing)
- **Permissions**: sudo access for package installation

## 🚀 Production Deployment

The framework is designed for production use with:

- ✅ **CI/CD Ready**: Shellcheck compliant and automated testing
- ✅ **Idempotent**: Safe to run multiple times
- ✅ **Rollback Support**: State tracking for recovery
- ✅ **Resource Monitoring**: System resource validation
- ✅ **Error Recovery**: Comprehensive error categorization and suggestions

## 📈 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Follow the bulletproof utility template pattern
4. Test your changes: `make test`
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**🎉 Ready to bulletproof your Ubuntu development environment!**

Start with: `./install-new-bulletproof.sh --dry-run --all`
