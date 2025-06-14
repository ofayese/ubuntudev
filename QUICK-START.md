# Ubuntu Dev Tools - Quick Reference

## 🚀 Essential Commands

### Complete Installation

```bash
./install-new-refactored.sh --all
```

### Common Development Setups

**Web Developer:**

```bash
./install-new-refactored.sh --devtools --terminal-enhancements --node-python --npm
```

**Systems Developer:**

```bash
./install-new-refactored.sh --devtools --terminal-enhancements --lang-sdks --devcontainers
```

**AI/ML Developer:**

```bash
./install-new-refactored.sh --devtools --dotnet-ai --node-python
```

### Preview Mode (Safe Testing)

```bash
./install-new-refactored.sh --dry-run --all
```

## 🔧 Component Reference

| Flag | What It Installs |
|------|------------------|
| `--devtools` | git, vim, curl, build-essential |
| `--terminal-enhancements` | bat, ripgrep, fzf, eza, zoxide |
| `--node-python` | Node.js (NVM), Python (pyenv) |
| `--npm` | Global NPM development packages |
| `--lang-sdks` | Rust, Java, Haskell toolchains |
| `--dotnet-ai` | .NET SDKs, PowerShell, AI tools |
| `--devcontainers` | Docker/Podman, dev containers |
| `--vscommunity` | Visual Studio 2022 (WSL2 only) |

## 🛠️ Utility Commands

```bash
# Resume interrupted installation
./install-new-refactored.sh --resume

# Generate dependency graph
./install-new-refactored.sh --graph

# Validate system compatibility
./install-new-refactored.sh --validate

# Debug mode for troubleshooting
./install-new-refactored.sh --debug --devtools
```

## 📁 Important Locations

- **Logs**: `~/.local/share/ubuntu-dev-tools/logs/`
- **State**: `~/.ubuntu-devtools.state`
- **Scripts**: `~/ubuntudev/src/`

## ⚡ After Installation

```bash
# Restart shell to activate new tools
exec $SHELL

# Verify installation
which git node python3 cargo rustc java
```

---
**Quick Start**: `cd ~/ubuntudev/src && ./install-new-refactored.sh --all`
