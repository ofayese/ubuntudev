#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/ubuntu-dev-tools.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== [setup-vscode.sh] Started at $(date) ==="

# Check if running in WSL
IS_WSL=0
if grep -qi microsoft /proc/version 2>/dev/null || grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
  IS_WSL=1
  echo "🐧 WSL environment detected."
fi

# Check for headless environment
IS_HEADLESS=0
if ! (command -v gnome-shell >/dev/null 2>&1 && echo $XDG_SESSION_TYPE | grep -q 'x11\|wayland'); then
  IS_HEADLESS=1
  echo "🕶 Headless environment detected."
fi

# --- Install VS Code if not in WSL and not headless ---
if [ "$IS_WSL" -eq 0 ] && [ "$IS_HEADLESS" -eq 0 ]; then
  echo "🔄 Installing VS Code and VS Code Insiders..."
  
  # Add Microsoft's GPG key
  wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/packages.microsoft.gpg
  sudo install -D -o root -g root -m 644 /tmp/packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
  sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
  rm -f /tmp/packages.microsoft.gpg
  
  # Install VS Code stable
  sudo apt update
  sudo apt install -y code
  
  # Install VS Code Insiders
  if ! command -v code-insiders >/dev/null 2>&1; then
    wget -O /tmp/vscode-insiders.deb "https://code.visualstudio.com/sha/download?build=insider&os=linux-deb-x64"
    sudo apt install -y /tmp/vscode-insiders.deb
    rm -f /tmp/vscode-insiders.deb
  fi
else
  echo "ℹ️ Skipping VS Code desktop installation (WSL or headless environment)."
fi

# --- Install VS Code Server Components ---
echo "📦 Setting up VS Code server components..."

# Create VS Code configuration directories
mkdir -p ~/.vscode-server/data/Machine
mkdir -p ~/.vscode-server-insiders/data/Machine

# --- Install VS Code Extensions ---
echo "🧩 Installing VS Code extensions..."

# Function to install extensions
install_extensions() {
  local CODE_CMD=$1
  
  if command -v "$CODE_CMD" >/dev/null 2>&1; then
    echo "Installing extensions for $CODE_CMD..."
    
    # Development Tools
    "$CODE_CMD" --install-extension ms-vscode.cpptools
    "$CODE_CMD" --install-extension ms-dotnettools.csharp
    "$CODE_CMD" --install-extension ms-python.python
    "$CODE_CMD" --install-extension ms-python.vscode-pylance
    "$CODE_CMD" --install-extension ms-vscode.powershell
    "$CODE_CMD" --install-extension golang.go
    "$CODE_CMD" --install-extension rust-lang.rust-analyzer
    "$CODE_CMD" --install-extension redhat.java
    "$CODE_CMD" --install-extension vscjava.vscode-java-debug
    
    # Web Development
    "$CODE_CMD" --install-extension dbaeumer.vscode-eslint
    "$CODE_CMD" --install-extension esbenp.prettier-vscode
    "$CODE_CMD" --install-extension ms-vscode.vscode-typescript-next
    "$CODE_CMD" --install-extension angular.ng-template
    "$CODE_CMD" --install-extension Vue.volar
    "$CODE_CMD" --install-extension svelte.svelte-vscode
    
    # Remote Development
    "$CODE_CMD" --install-extension ms-vscode-remote.remote-wsl
    "$CODE_CMD" --install-extension ms-vscode-remote.remote-containers
    "$CODE_CMD" --install-extension ms-vscode-remote.remote-ssh
    "$CODE_CMD" --install-extension ms-vscode.remote-explorer
    
    # DevOps & Cloud
    "$CODE_CMD" --install-extension ms-azuretools.vscode-docker
    "$CODE_CMD" --install-extension ms-kubernetes-tools.vscode-kubernetes-tools
    "$CODE_CMD" --install-extension redhat.vscode-yaml
    "$CODE_CMD" --install-extension HashiCorp.terraform
    
    # AI & ML
    "$CODE_CMD" --install-extension ms-toolsai.jupyter
    "$CODE_CMD" --install-extension ms-toolsai.jupyter-keymap
    "$CODE_CMD" --install-extension ms-toolsai.jupyter-renderers
    "$CODE_CMD" --install-extension ms-toolsai.vscode-jupyter-cell-tags
    "$CODE_CMD" --install-extension ms-toolsai.vscode-jupyter-slideshow
    
    # GitHub Tools
    "$CODE_CMD" --install-extension GitHub.vscode-pull-request-github
    "$CODE_CMD" --install-extension GitHub.copilot
    "$CODE_CMD" --install-extension GitHub.copilot-chat
    
    # Themes and UI Enhancements
    "$CODE_CMD" --install-extension vscode-icons-team.vscode-icons
    "$CODE_CMD" --install-extension dracula-theme.theme-dracula
    "$CODE_CMD" --install-extension PKief.material-icon-theme
    
    # Productivity
    "$CODE_CMD" --install-extension streetsidesoftware.code-spell-checker
    "$CODE_CMD" --install-extension eamodio.gitlens
    "$CODE_CMD" --install-extension christian-kohler.path-intellisense
    "$CODE_CMD" --install-extension usernamehw.errorlens
    
    # Testing and Debugging
    "$CODE_CMD" --install-extension ryanluker.vscode-coverage-gutters
    "$CODE_CMD" --install-extension formulahendry.code-runner
    
    echo "✅ Extensions installed for $CODE_CMD."
  else
    echo "⚠️ $CODE_CMD not found, skipping extension installation."
  fi
}

# If in desktop environment, install extensions for local VS Code
if [ "$IS_HEADLESS" -eq 0 ]; then
  install_extensions "code"
  install_extensions "code-insiders"
else
  echo "ℹ️ Headless environment detected, skipping local extension installation."
  echo "Extensions will be installed when you connect from VS Code client."
fi

# --- Setup VS Code User Settings ---
echo "⚙️ Configuring VS Code settings..."

# Create settings.json template
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

# Save settings for VS Code
mkdir -p ~/.config/Code/User/
echo "$SETTINGS" > ~/.config/Code/User/settings.json

# Save settings for VS Code Insiders
mkdir -p ~/.config/Code\ -\ Insiders/User/
echo "$SETTINGS" > ~/.config/Code\ -\ Insiders/User/settings.json

# Save settings for WSL VS Code Server
echo "$SETTINGS" > ~/.vscode-server/data/Machine/settings.json
echo "$SETTINGS" > ~/.vscode-server-insiders/data/Machine/settings.json

# --- Install Language Servers for better code intelligence ---
echo "🔄 Installing language servers and linters for better VS Code integration..."

# Node-based language servers
if command -v npm >/dev/null 2>&1; then
  echo "Installing Node-based language servers..."
  npm install -g typescript typescript-language-server vscode-langservers-extracted \
    yaml-language-server bash-language-server dockerfile-language-server-nodejs \
    @angular/language-server vls svelte-language-server
fi

# Python language servers
if command -v pip >/dev/null 2>&1; then
  echo "Installing Python language servers and linters..."
  pip install --user python-lsp-server pylint black mypy autopep8 flake8
fi

# Install tools needed for VS Code debugging and testing
echo "Installing tools for debugging and testing..."
sudo apt update
sudo apt install -y xdg-utils

echo "✅ VS Code setup completed!"
