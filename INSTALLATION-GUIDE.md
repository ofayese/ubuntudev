# 🚀 Current Installation Setup

## ✅ **Main Installer: `install-new.sh`**

This is now the **single, correct installation file** after our cleanup.

### 📋 **Usage Examples**

```bash
# Show help and available options
./install-new.sh --help

# Install everything (recommended for new setups)
./install-new.sh --all

# Install specific components only
./install-new.sh --devtools --terminal --vscommunity

# Just run validation (check what's installed)
./install-new.sh --validate

# Show dependency graph
./install-new.sh --graph

# Resume interrupted installation
./install-new.sh --resume

# Debug mode (verbose output)
./install-new.sh --debug --devtools
```

### 🎯 **Available Components**

| Component | Flag | Description |
|-----------|------|-------------|
| **devtools** | `--devtools` | Essential development tools (git, vim, curl, build tools) |
| **terminal** | `--terminal` | Modern CLI tools (bat, ripgrep, fzf, eza, etc.) |
| **desktop** | `--desktop` | Desktop environment enhancements |
| **devcontainers** | `--devcontainers` | Development containers setup |
| **dotnet-ai** | `--dotnet-ai` | .NET and AI development tools |
| **lang-sdks** | `--lang-sdks` | Language SDKs (Node.js, Python, Java, Rust, Go) |
| **vscommunity** | `--vscommunity` | Visual Studio Code and extensions |
| **update-env** | `--update-env` | Environment updates and optimizations |

### 🔍 **Key Features**

✅ **Dependency Resolution** - Automatically installs required components  
✅ **Resume Support** - Can resume from interrupted installations  
✅ **Bulletproof Sourcing** - No module loading conflicts  
✅ **Comprehensive Logging** - Detailed logs in `~/.local/share/ubuntu-dev-tools/logs/`  
✅ **State Management** - Tracks installation progress  
✅ **Validation Mode** - Check what's installed without installing  

### 📁 **Important Files**

```
install-new.sh           # Main installer (THIS IS THE ONE TO USE)
dependencies.yaml        # Component dependency definitions
validate-installation.sh # Validation and health checks
util-*.sh               # Bulletproof utility modules
setup-*.sh              # Individual component installers
```

### 🧪 **Testing Your Setup**

```bash
# Test modular sourcing (should show no errors)
./test-bulletproof-sourcing.sh

# Validate current installation
./install-new.sh --validate

# Check what would be installed
./install-new.sh --graph
```

---

## 🎯 **Quick Start**

For a **new Ubuntu development environment**:

```bash
# Make it executable (if needed)
chmod +x install-new.sh

# Install everything
./install-new.sh --all

# Or step by step
./install-new.sh --devtools --terminal
./install-new.sh --lang-sdks --vscommunity
./install-new.sh --validate  # Check everything works
```

---

✅ **This is your clean, production-ready installation framework!**
