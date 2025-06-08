#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/ubuntu-dev-tools.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== [setup-npm.sh] Started at $(date) ==="

# --- Options ---
FORCE_REINSTALL=false
QUIET_MODE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --force|-f) FORCE_REINSTALL=true; shift ;;
    --quiet|-q) QUIET_MODE=true; shift ;;
    --help|-h)
      echo "Usage: $0 [options]"
      echo "  --force, -f    Force reinstall"
      echo "  --quiet, -q    Quiet mode"
      echo "  --help, -h     Show help"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if ! command -v npm >/dev/null 2>&1; then
  echo "❌ npm is not installed. Please install Node.js + npm first."
  exit 1
fi

# --- Global packages ---
GLOBAL_PACKAGES=(
  @vscode/dev-container-cli
  @vscode/test-cli
  @devcontainers/cli
  yo
  generator-code
  http-server
  typescript
  ts-node
)

# Optional (for Podman-based environments)
if command -v podman >/dev/null 2>&1; then
  GLOBAL_PACKAGES+=(
    podman-mcp-server
    @podman-desktop/podman-extension-api
    @podman-desktop/webview-api
  )
fi

# --- Dev dependencies (project-local) ---
DEV_PACKAGES=(
  vscode-uri
  vscode-languageserver-types
  vscode-languageserver-protocol
  vscode-json-languageservice
  vscode-languageserver-textdocument
  vscode-languageclient
  vscode-markdown-languageservice
  @vscode/test-electron
  @vscode/l10n
  @vscode/sqlite3
  @vscode/emmet-helper
  @vscode/chat-extension-utils
  @vscode/debugprotocol
  @vscode/wasm-wasi
)

GLOBAL_INSTALLED=0
GLOBAL_SKIPPED=0
LOCAL_INSTALLED=0
LOCAL_SKIPPED=0

echo "📦 Installing global NPM packages..."
TO_INSTALL_GLOBAL=()

for pkg in "${GLOBAL_PACKAGES[@]}"; do
  if $FORCE_REINSTALL || ! npm list -g --depth=0 "$pkg" &>/dev/null; then
    TO_INSTALL_GLOBAL+=("$pkg")
  else
    ((GLOBAL_SKIPPED++))
  fi
done

if [[ ${#TO_INSTALL_GLOBAL[@]} -gt 0 ]]; then
  npm install -g "${TO_INSTALL_GLOBAL[@]}"
  GLOBAL_INSTALLED=${#TO_INSTALL_GLOBAL[@]}
else
  echo "✅ All global packages are already installed"
fi

echo "📦 Installing local devDependencies..."
TO_INSTALL_LOCAL=()

for pkg in "${DEV_PACKAGES[@]}"; do
  if $FORCE_REINSTALL || ! npm list --depth=0 "$pkg" &>/dev/null; then
    TO_INSTALL_LOCAL+=("$pkg")
  else
    ((LOCAL_SKIPPED++))
  fi
done

if [[ ${#TO_INSTALL_LOCAL[@]} -gt 0 ]]; then
  npm install --save-dev "${TO_INSTALL_LOCAL[@]}"
  LOCAL_INSTALLED=${#TO_INSTALL_LOCAL[@]}
else
  echo "✅ All local packages are already installed"
fi

echo "📊 Summary:"
echo "  Global packages installed: $GLOBAL_INSTALLED"
echo "  Skipped: $GLOBAL_SKIPPED"
echo "  Local packages installed:  $LOCAL_INSTALLED"
echo "  Skipped: $LOCAL_SKIPPED"