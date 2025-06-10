#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/ubuntu-dev-tools.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== [setup-vscode.sh] Started at $(date) ==="

# --- Detect Environment Types ---
IS_HEADLESS=1
IS_WSL=0

# Check if running in WSL
if grep -qi microsoft /proc/version 2>/dev/null; then
  IS_WSL=1
  echo "🖥️ WSL2 environment detected."
elif command -v gnome-shell >/dev/null 2>&1 && echo "${XDG_SESSION_TYPE:-}" | grep -qE 'x11|wayland'; then
  IS_HEADLESS=0
  echo "🖥️ Desktop environment detected."
else
  echo "📱 Headless environment detected."
fi

# --- Check for existing VS Code installations in WSL2 ---
if [ "$IS_WSL" -eq 1 ]; then
    echo "📋 WSL detected: Using Windows VS Code with Remote-WSL extension instead of installing VS Code in WSL."
    echo "   The Remote-WSL extension in Windows VS Code handles the connection automatically."
    
    # Check if VS Code is already installed in WSL and uninstall if found
    if command -v code >/dev/null 2>&1 || command -v code-insiders >/dev/null 2>&1; then
        echo "� VS Code installation detected in WSL. Removing redundant installation..."
        
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
else
  # --- Install VS Code and Insiders (only on Desktop/Headless, not WSL2) ---
  echo "📦 Installing Visual Studio Code..."

# Use shared utility functions for package installation
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-log.sh"
source "$SCRIPT_DIR/util-packages.sh"
source "$SCRIPT_DIR/util-env.sh"

  install_vscode_variant "stable" "https://update.code.visualstudio.com/latest/linux-deb-x64/stable"
  install_vscode_variant "insiders" "https://update.code.visualstudio.com/latest/linux-deb-x64/insider"

  # --- Set VS Code Insiders as Git editor ---
  echo "🔧 Configuring Git to use code-insiders as editor..."
  git config --global core.editor "code-insiders --wait"
fi

# Configure Git editor appropriately for WSL2
if [ "$IS_WSL" -eq 1 ]; then
  echo "🔧 Configuring Git for WSL2 environment..."
  git config --global core.editor "code-insiders --wait --remote wsl+$(grep -oP "(?<=^NAME=\").*(?=\")" /etc/os-release | tr ' ' '-' | tr '[:upper:]' '[:lower:]')"

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

# --- Install extensions (desktop only) ---
if [ "$IS_HEADLESS" -eq 0 ] && [ "$IS_WSL" -eq 0 ]; then
  install_extensions "code"
  install_extensions "code-insiders"
else
  echo "📱 Headless or WSL2 environment — skipping local extension install."
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

# Only create settings files if not in WSL2
if [ "$IS_WSL" -eq 0 ]; then
  mkdir -p ~/.config/Code/User/
  echo "$SETTINGS" > ~/.config/Code/User/settings.json

  mkdir -p ~/.config/Code-Insiders/User/
  echo "$SETTINGS" > ~/.config/Code-Insiders/User/settings.json
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

# --- System Utils for VS Code (if not WSL2) ---
if [ "$IS_WSL" -eq 0 ]; then
  sudo apt install -y xdg-utils
fi

echo "✅ VS Code (and Insiders) fully installed and configured."
echo "=== [setup-vscode.sh] Finished at $(date) ==="
