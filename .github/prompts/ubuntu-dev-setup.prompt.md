# Ubuntu Development Environment Setup

Generate or enhance shell scripts for Ubuntu development environment setup. Focus on:

## Environment Detection & Compatibility

- Detect WSL2 vs native Ubuntu vs headless environments
- Handle systemd availability and service management
- Support both Ubuntu Desktop and Ubuntu Server configurations
- Ensure compatibility across Ubuntu LTS versions (20.04, 22.04, 24.04)

## Package Management Strategy

```bash
# Multi-package manager approach
install_package() {
  local package="$1"
  local snap_name="${2:-$package}"
  
  # Try snap first for applications
  if command -v snap >/dev/null 2>&1; then
    if snap info "$snap_name" >/dev/null 2>&1; then
      sudo snap install "$snap_name" --classic 2>/dev/null || sudo snap install "$snap_name"
      return $?
    fi
  fi
  
  # Fall back to apt
  if command -v apt >/dev/null 2>&1; then
    sudo apt update && sudo apt install -y "$package"
    return $?
  fi
  
  echo "Error: No suitable package manager found" >&2
  return 1
}
```

## Development Tool Categories

- **Language SDKs**: Node.js, Python, .NET, Java, Go, Rust
- **Development Tools**: Git, Docker, VS Code, build tools
- **System Utilities**: curl, wget, jq, tree, htop, neofetch
- **Container Tools**: Docker Desktop, kubectl, helm
- **Terminal Enhancements**: zsh, oh-my-zsh, powerline, fonts

## WSL2-Specific Considerations

- Configure wsl.conf for systemd and optimal mount options
- Set up Windows integration (VS Code, Git credentials, clipboard)
- Handle Windows PATH integration safely
- Configure X11 forwarding for GUI applications when needed

## Security & Best Practices

- Minimize sudo usage where possible
- Validate all downloads with checksums
- Use official repositories and trusted PPAs
- Implement proper cleanup and error handling
- Support dry-run mode for testing

## Installation Patterns

```bash
# Idempotent installation pattern
install_if_missing() {
  local command_name="$1"
  local install_function="$2"
  
  if command -v "$command_name" >/dev/null 2>&1; then
    echo "✅ $command_name already installed"
    return 0
  fi
  
  echo "📦 Installing $command_name..."
  if "$install_function"; then
    echo "✅ $command_name installed successfully"
  else
    echo "❌ Failed to install $command_name" >&2
    return 1
  fi
}
```

## Output Requirements

- Generate modular, well-documented installation scripts
- Include comprehensive error handling and logging
- Support both interactive and automated execution
- Provide clear progress indicators and success/failure reporting
- Include validation steps to verify successful installation

Focus on creating production-ready scripts that can be used for consistent development environment setup across different Ubuntu configurations.
