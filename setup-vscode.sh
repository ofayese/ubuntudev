#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/ubuntu-dev-tools.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== [setup-vscode.sh] Started at $(date) ==="

# --- Detect Desktop vs Headless ---
IS_HEADLESS=1
if command -v gnome-shell >/dev/null 2>&1 && echo "${XDG_SESSION_TYPE:-}" | grep -qE 'x11|wayland'; then
  IS_HEADLESS=0
  echo "🖥️ Desktop environment detected."
else
  echo "📱 Headless or WSL2 environment detected."
fi

# --- Detect WSL environment ---
IS_WSL=0
if grep -qi microsoft /proc/version 2>/dev/null; then
  IS_WSL=1
  echo "🐧 WSL environment detected."
fi

# --- Install/Uninstall VS Code and Insiders ---
if [ "$IS_WSL" -eq 1 ]; then
    echo "📋 WSL detected: Using Windows VS Code with Remote-WSL extension instead of installing VS Code in WSL."
    echo "   The Remote-WSL extension in Windows VS Code handles the connection automatically."
    
    # Check if VS Code is already installed in WSL and uninstall if found
    if command -v code >/dev/null 2>&1 || command -v code-insiders >/dev/null 2>&1; then
        echo "🔍 VS Code installation detected in WSL. Removing redundant installation..."
        
        if command -v code >/dev/null 2>&1; then
            echo "🗑️ Removing VS Code from WSL..."
            sudo DEBIAN_FRONTEND=noninteractive apt remove -y code
        fi
        
        if command -v code-insiders >/dev/null 2>&1; then
            echo "🗑️ Removing VS Code Insiders from WSL..."
            sudo DEBIAN_FRONTEND=noninteractive apt remove -y code-insiders
        fi
        
        # Clean up any leftover dependencies
        sudo DEBIAN_FRONTEND=noninteractive apt autoremove -y
        
        echo "✅ Removed redundant VS Code installation from WSL."
    fi
    
    # Create the necessary directories for Remote-WSL
    mkdir -p ~/.vscode-server/data/Machine
    mkdir -p ~/.vscode-server-insiders/data/Machine
    SKIP_VSCODE_INSTALL=1
else
    echo "📦 Installing Visual Studio Code..."
    SKIP_VSCODE_INSTALL=0
fi

if [ "${SKIP_VSCODE_INSTALL:-0}" -eq 0 ]; then
    # Set environment to non-interactive
    export DEBIAN_FRONTEND=noninteractive
    
    # Pre-configure debconf responses and add Microsoft repository manually
    echo "🔧 Setting up Microsoft repository for VS Code..."
    
    # Pre-configure debconf responses
    echo 'code code/add-microsoft-repo boolean true' | sudo debconf-set-selections
    
    # Add Microsoft GPG key and repository manually to avoid interactive prompts
    if ! command -v code >/dev/null && ! command -v code-insiders >/dev/null; then
        # Add Microsoft GPG key
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo dd of=/usr/share/keyrings/packages.microsoft.gpg
        
        # Add VS Code repository
        echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
        
        # Update package cache
        sudo apt update -y
    fi
fi

# Function to safely install VS Code from repository
install_vscode_from_repo() {
    echo "📦 Installing VS Code from Microsoft repository..."
    
    # Install VS Code stable
    if sudo DEBIAN_FRONTEND=noninteractive apt install -y code; then
        echo "✅ VS Code stable installed successfully"
    else
        echo "⚠️ Failed to install VS Code stable from repository"
    fi
    
    # Try to install VS Code Insiders (may not be available in repository)
    if sudo DEBIAN_FRONTEND=noninteractive apt install -y code-insiders 2>/dev/null; then
        echo "✅ VS Code Insiders installed successfully"
    else
        echo "📦 Installing VS Code Insiders from direct download..."
        install_vscode_variant "insiders" "https://update.code.visualstudio.com/latest/linux-deb-x64/insider"
    fi
}

# Function to safely download and install VS Code (fallback)
install_vscode_variant() {
    local variant="$1"
    local url="$2"
    local temp_file="/tmp/vscode-${variant}.deb"
    
    echo "📦 Installing VS Code $variant..."
    if wget -q -O "$temp_file" "$url"; then
        if sudo DEBIAN_FRONTEND=noninteractive apt install -y "$temp_file" 2>/dev/null; then
            echo "✅ VS Code $variant installed successfully"
            rm -f "$temp_file"
            return 0
        else
            echo "⚠️ Failed to install VS Code $variant"
            sudo DEBIAN_FRONTEND=noninteractive apt --fix-broken install -y 2>/dev/null || true
            rm -f "$temp_file"
            return 1
        fi
    else
        echo "⚠️ Failed to download VS Code $variant"
        rm -f "$temp_file"
        return 1
    fi
}

# Install VS Code (if not skipped for WSL)
if [ "${SKIP_VSCODE_INSTALL:-0}" -eq 0 ]; then
    install_vscode_from_repo
fi

# --- Set VS Code Insiders as Git editor ---
if [ "$IS_WSL" -eq 0 ]; then
    echo "🔧 Configuring Git to use code-insiders as editor..."
    git config --global core.editor "code-insiders --wait"
else
    echo "🔧 Configuring Git to use Windows VS Code with Remote-WSL..."
    git config --global core.editor "code-insiders --wait --remote wsl"
fi

# --- Extension Installer ---
install_extensions() {
  local CODE_BIN=$1
  echo "🔌 Installing extensions via $CODE_BIN..."
  
  local extensions=(
    "ms-python.python"
    "ms-azuretools.vscode-docker"
    "GitHub.copilot"
    "golang.Go"
    "redhat.vscode-yaml"
    "dbaeumer.vscode-eslint"
    "esbenp.prettier-vscode"
    "PKief.material-icon-theme"
    "eamodio.gitlens"
    "ms-vscode-remote.remote-containers"
    "ms-toolsai.jupyter"
    "ritwickdey.LiveServer"
  )
  
  for ext in "${extensions[@]}"; do
    if $CODE_BIN --install-extension "$ext" 2>/dev/null; then
      echo "✅ Installed extension: $ext"
    else
      echo "⚠️ Failed to install extension: $ext"
    fi
  done
}

# --- Install extensions (desktop only and non-WSL) ---
if [ "$IS_HEADLESS" -eq 0 ] && [ "$IS_WSL" -eq 0 ]; then
  install_extensions "code"
  install_extensions "code-insiders"
else
  echo "📱 Headless or WSL environment — skipping local extension install."
  echo "Extensions will be synced when VS Code connects remotely."
fi

# --- VS Code Settings ---
echo "⚙️ Configuring VS Code user settings..."

SETTINGS='{
  "editor.fontFamily": "JetBrains Mono, Fira Code, Consolas, monospace",
  "editor.fontSize": 14,
  "editor.fontLigatures": true,
  "editor.formatOnSave": true,
  "editor.formatOnPaste": true,
  "editor.suggestSelection": "first",
  "editor.minimap.enabled": true,
  "editor.wordWrap": "on",
  "editor.cursorBlinking": "smooth",
  "editor.cursorSmoothCaretAnimation": "on",
  "editor.bracketPairColorization.enabled": true,
  "editor.guides.bracketPairs": "active",
  "files.autoSave": "afterDelay",
  "files.autoSaveDelay": 1000,
  "workbench.iconTheme": "material-icon-theme",
  "workbench.colorTheme": "Default Dark Modern",
  "workbench.editor.enablePreview": false,
  "terminal.integrated.defaultProfile.linux": "zsh",
  "terminal.integrated.fontFamily": "JetBrains Mono, Fira Code, monospace",
  "git.autofetch": true,
  "git.confirmSync": false,
  "github.copilot.enable": {
    "*": true,
    "plaintext": true,
    "markdown": true,
    "yaml": true
  },
  "explorer.confirmDelete": false,
  "explorer.confirmDragAndDrop": false,
  "telemetry.telemetryLevel": "error",
  "update.mode": "start",
  "extensions.autoUpdate": true,
  "terminal.integrated.persistentSessionReviveProcess": "never",
  "diffEditor.ignoreTrimWhitespace": false,
  "python.formatting.provider": "black",
  "python.linting.enabled": true,
  "python.linting.pylintEnabled": true,
  "javascript.updateImportsOnFileMove.enabled": "always",
  "typescript.updateImportsOnFileMove.enabled": "always",
  "eslint.format.enable": true,
  "window.zoomLevel": 0
}'

# Only create local settings if VS Code is installed
if [ "${SKIP_VSCODE_INSTALL:-0}" -eq 0 ]; then
    mkdir -p ~/.config/Code/User/
    echo "$SETTINGS" > ~/.config/Code/User/settings.json
    
    mkdir -p ~/.config/Code-Insiders/User/
    echo "$SETTINGS" > ~/.config/Code-Insiders/User/settings.json
    
    echo "✅ VS Code settings configured in local installation."
else
    echo "ℹ️ Skipping local VS Code settings as we're using Windows VS Code with Remote-WSL."
fi

# --- WSL Remote Name ---
IS_WSL=0
if grep -qi microsoft /proc/version 2>/dev/null; then
  IS_WSL=1
fi

if [ "$IS_WSL" -eq 1 ]; then
  # Get WSL hostname
  if command -v cmd.exe >/dev/null; then
    WSL_REMOTE_NAME=$(cmd.exe /c "hostname" | tr -d '\r')
  else
    WSL_REMOTE_NAME="wsl-devbox"
  fi

  # Create symlinks for more user-friendly folder names
  for variant in ".vscode-server" ".vscode-server-insiders"; do
    SERVER_DIR="$HOME/$variant/data/Machine"
    mkdir -p "$SERVER_DIR"

    HASHED=$(find "$SERVER_DIR" -maxdepth 1 -type d | grep -Ev "/Machine$" | head -n 1)
    if [ -n "$HASHED" ]; then
      LINK_NAME="${SERVER_DIR}/${WSL_REMOTE_NAME}"
      if [ ! -L "$LINK_NAME" ]; then
        ln -s "$HASHED" "$LINK_NAME"
        echo "🔗 Symlink created: $LINK_NAME → $HASHED"
      fi
    fi
  done
fi

# --- System Utils for VS Code if needed ---
if [ "${SKIP_VSCODE_INSTALL:-0}" -eq 0 ]; then
    sudo apt install -y xdg-utils
fi

if [ "$IS_WSL" -eq 1 ]; then
    echo "✅ VS Code integration with WSL configured successfully."
    echo "   Any redundant VS Code installations in WSL have been removed."
    echo "   To use VS Code with WSL:"
    echo "   1. Install the 'Remote - WSL' extension in your Windows VS Code"
    echo "   2. Use 'code .' in WSL terminal to open current folder in Windows VS Code"
    echo "   3. Or connect by clicking the green remote button in Windows VS Code"
else
    echo "✅ VS Code (and Insiders) fully installed and configured."
fi
echo "=== [setup-vscode.sh] Finished at $(date) ==="
