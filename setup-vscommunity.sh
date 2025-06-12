#!/usr/bin/env bash
set -euo pipefail

# Source utility modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-log.sh"
source "$SCRIPT_DIR/util-env.sh"
source "$SCRIPT_DIR/util-install.sh"

# Initialize logging
init_logging
log_info "Visual Studio Community setup started"

# Detect environment
ENV_TYPE=$(detect_environment)
log_info "Environment detected: $ENV_TYPE"

# --- Check if in WSL ---
log_info "Checking if running in WSL environment..."
if [[ "$ENV_TYPE" == "$ENV_WSL" ]]; then
    log_success "Running in WSL environment (Windows Subsystem for Linux)"
else
    log_warning "Not in WSL. Visual Studio Community is only supported in Windows."
    log_info "Skipping Visual Studio Community installation as it's not applicable in this environment."
    finish_logging
    exit 0
fi

# --- Check if winget is installed ---
log_info "Checking for winget package manager..."
start_spinner "Checking for winget"
if ! powershell.exe -Command "Get-Command winget -ErrorAction SilentlyContinue" >/dev/null 2>&1; then
    stop_spinner "Checking for winget"
    log_error "winget is not available in your Windows environment."
    log_info "Please install App Installer from the Microsoft Store:"
    log_info "1. Open Microsoft Store in Windows"
    log_info "2. Search for 'App Installer'"
    log_info "3. Install the App Installer package"
    log_info "4. Run this script again"
    
    # Create a Windows shortcut to Microsoft Store App Installer page
    powershell.exe -Command "Start-Process 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1'" >/dev/null 2>&1 || true
    
    finish_logging
    exit 1
fi
stop_spinner "Checking for winget"

# --- Check if Visual Studio Community is already installed ---
log_info "Checking for existing installation of Visual Studio Community..."
start_spinner "Checking for existing installation"
if powershell.exe -Command "winget list --id Microsoft.VisualStudio.2022.Community 2>$null | Select-String 'Visual Studio'" >/dev/null 2>&1; then
    stop_spinner "Checking for existing installation"
    log_success "Visual Studio Community 2022 is already installed. Skipping installation."
    
    # Check if Visual Studio needs updates
    log_info "Checking for Visual Studio updates..."
    if powershell.exe -Command "winget upgrade --id Microsoft.VisualStudio.2022.Community" | grep -q "No applicable update found"; then
        log_info "Visual Studio Community is up to date."
    else
        log_info "Updates available for Visual Studio Community."
        log_info "To update, run: 'powershell.exe -Command \"winget upgrade --id Microsoft.VisualStudio.2022.Community\"'"
    fi
    
    finish_logging
    exit 0
fi
stop_spinner "Checking for existing installation"

# --- Install Visual Studio Community 2022 via winget ---
log_info "Installing Visual Studio Community 2022 using winget..."
start_spinner "Installing Visual Studio Community 2022"

# Using PowerShell to run winget with better error handling
powershell_install_cmd=$(cat <<'EOF'
try {
    $process = Start-Process -FilePath "winget" -ArgumentList "install", "--exact", "--id", "Microsoft.VisualStudio.2022.Community", "--silent", "--accept-package-agreements", "--accept-source-agreements" -NoNewWindow -PassThru -Wait
    if ($process.ExitCode -eq 0) {
        Write-Output "Installation completed successfully."
        exit 0
    } else {
        Write-Error "Installation failed with exit code: $($process.ExitCode)"
        exit $process.ExitCode
    }
} catch {
    Write-Error "Error: $_"
    exit 1
}
EOF
)

if powershell.exe -Command "$powershell_install_cmd"; then
    stop_spinner "Installing Visual Studio Community 2022"
    log_success "Visual Studio Community installation completed via winget."
    
    # Create a desktop shortcut with additional help
    cat > ~/vs-community-setup-help.txt <<'EOF'
Visual Studio Community 2022 Installation Guide

1. Visual Studio has been installed via winget but may require additional setup.

2. To customize components, launch the Visual Studio Installer:
   - Search for "Visual Studio Installer" in the Windows Start menu
   - Or run it from: C:\Program Files (x86)\Microsoft Visual Studio\Installer\vs_installer.exe

3. Recommended workloads for development:
   - .NET Desktop Development
   - ASP.NET and Web Development
   - Universal Windows Platform Development
   - C++ Desktop Development

4. For WSL integration, ensure you have:
   - Windows Terminal installed
   - "Remote - WSL" extension in VS Code
   - Configured VS Code as your default editor in WSL

For issues, visit: https://learn.microsoft.com/en-us/visualstudio/install/troubleshooting-installation-issues
EOF
    
    log_info "Created help guide at: ~/vs-community-setup-help.txt"
else
    stop_spinner "Installing Visual Studio Community 2022"
    log_error "Visual Studio Community installation failed."
    log_info "Try running the installer manually from Windows:"
    log_info "1. Open PowerShell in Windows"
    log_info "2. Run: winget install --id Microsoft.VisualStudio.2022.Community"
    finish_logging
    exit 1
fi

log_success "Visual Studio Community setup completed successfully!"
finish_logging
