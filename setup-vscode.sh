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

# --- Install VS Code and Insiders ---
echo "📦 Installing Visual Studio Code..."

# Function to safely download and install VS Code
install_vscode_variant() {
    local variant="$1"
    local url="$2"
    local temp_file="/tmp/vscode-${variant}.deb"
    
    echo "📦 Installing VS Code $variant..."
    if wget -q -O "$temp_file" "$url"; then
        if sudo apt install -y "$temp_file" 2>/dev/null; then
            echo "✅ VS Code $variant installed successfully"
            rm -f "$temp_file"
            return 0
        else
            echo "⚠️ Failed to install VS Code $variant"
            sudo apt --fix-broken install -y 2>/dev/null || true
            rm -f "$temp_file"
            return 1
        fi
    else
        echo "⚠️ Failed to download VS Code $variant"
        rm -f "$temp_file"
        return 1
    fi
}

install_vscode_variant "stable" "https://update.code.visualstudio.com/latest/linux-deb-x64/stable"
install_vscode_variant "insiders" "https://update.code.visualstudio.com/latest/linux-deb-x64/insider"

# --- Set VS Code Insiders as Git editor ---
echo "🔧 Configuring Git to use code-insiders as editor..."
git config --global core.editor "code-insiders --wait"

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
if [ "$IS_HEADLESS" -eq 0 ]; then
  install_extensions "code"
  install_extensions "code-insiders"
else
  echo "📱 Headless environment — skipping local extension install."
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

mkdir -p ~/.config/Code/User/
echo "$SETTINGS" > ~/.config/Code/User/settings.json

mkdir -p ~/.config/Code-Insiders/User/
echo "$SETTINGS" > ~/.config/Code-Insiders/User/settings.json

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

# --- System Utils for VS Code ---
sudo apt install -y xdg-utils

echo "✅ VS Code (and Insiders) fully installed and configured."
echo "=== [setup-vscode.sh] Finished at $(date) ==="
