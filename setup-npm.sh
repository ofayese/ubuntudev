#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/ubuntu-dev-tools.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== [setup-npm.sh] Started at $(date) ==="

#!/bin/bash
# npm-dev-deps-installer.sh - Install npm global and local development dependencies

# Exit on error
set -e

# Command line options
FORCE_REINSTALL=false
QUIET_MODE=false

# Process command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --force|-f)
      FORCE_REINSTALL=true
      shift
      ;;
    --quiet|-q)
      QUIET_MODE=true
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  --force, -f    Force reinstall of packages even if already installed"
      echo "  --quiet, -q    Quiet mode (less output)"
      echo "  --help, -h     Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Check if npm is installed
if ! command -v npm &>/dev/null; then
  echo "❌ Error: npm is not installed or not in PATH. Please install Node.js and npm first."
  exit 1
fi

# Global CLI packages
GLOBAL_PACKAGES=(
  podman-mcp-server
  @podman-desktop/podman-extension-api
  @podman-desktop/webview-api
  yo
  generator-code
  @vscode/test-cli
  @vscode/dev-container-cli
)

# Local project packages as devDependencies
DEV_PACKAGES=(
  vscode-uri
  vscode-languageserver-types
  vscode-languageserver-protocol
  vscode-json-languageservice
  vscode-languageserver-textdocument
  vscode-languageclient
  vscode-textmate
  vscode-jsonrpc
  vscode-css-languageservice
  @vscode/l10n
  vscode-html-languageservice
  @vscode/vscode-languagedetection
  @vscode/test-electron
  http-proxy-agent
  @vscode/emmet-helper
  @vscode/sqlite3
  node-addon-api
  @vscode/sudo-prompt
  @vscode/debugprotocol
  @vscode/debugadapter
  @vscode/windows-registry
  @vscode/web-custom-data
  vscode-markdown-languageservice
  vscode-markdown-languageserver
  @vscode/wasm-wasi
  @vscode/jupyter-ipywidgets8
  @vscode/windows-ca-certs
  @vscode/openssl-prebuilt
  @vscode/prompt-tsx
  @vscode/chat-extension-utils
)

# Counters for summary
GLOBAL_INSTALLED=0
GLOBAL_SKIPPED=0
LOCAL_INSTALLED=0
LOCAL_SKIPPED=0

# Check if running with sudo/admin privileges for global installs
if [[ "$EUID" -ne 0 ]] && [[ "$(uname)" != "Darwin" ]] && [[ "$(uname)" != "MINGW"* ]]; then
  echo "⚠️  Warning: Installing global packages may require admin privileges"
  echo "Consider running this script with sudo if global installations fail"
fi

echo "🔧 Installing global packages..."
GLOBAL_TO_INSTALL=()

for pkg in "${GLOBAL_PACKAGES[@]}"; do
  if $FORCE_REINSTALL || ! npm list -g --depth=0 "$pkg" &>/dev/null; then
    GLOBAL_TO_INSTALL+=("$pkg")
  else
    if ! $QUIET_MODE; then
      echo "✅ $pkg already installed globally"
    fi
    ((GLOBAL_SKIPPED++))
  fi
done

if [ ${#GLOBAL_TO_INSTALL[@]} -gt 0 ]; then
  echo "📦 Installing ${#GLOBAL_TO_INSTALL[@]} global packages..."
  if ! $QUIET_MODE; then
    echo "${GLOBAL_TO_INSTALL[@]}"
  fi
  npm install -g "${GLOBAL_TO_INSTALL[@]}"
  GLOBAL_INSTALLED=${#GLOBAL_TO_INSTALL[@]}
else
  echo "👍 All global packages are already installed"
fi

echo "🔧 Installing devDependencies..."
LOCAL_TO_INSTALL=()

for pkg in "${DEV_PACKAGES[@]}"; do
  if $FORCE_REINSTALL || ! npm list --depth=0 "$pkg" &>/dev/null; then
    LOCAL_TO_INSTALL+=("$pkg")
  else
    if ! $QUIET_MODE; then
      echo "✅ $pkg already in project"
    fi
    ((LOCAL_SKIPPED++))
  fi
done

if [ ${#LOCAL_TO_INSTALL[@]} -gt 0 ]; then
  echo "📦 Installing ${#LOCAL_TO_INSTALL[@]} local devDependencies..."
  if ! $QUIET_MODE; then
    echo "${LOCAL_TO_INSTALL[@]}"
  fi
  npm install --save-dev "${LOCAL_TO_INSTALL[@]}"
  LOCAL_INSTALLED=${#LOCAL_TO_INSTALL[@]}
else
  echo "👍 All local packages are already installed"
fi

# Print summary
echo "📊 Installation Summary:"
echo "   Global packages installed: $GLOBAL_INSTALLED"
echo "   Global packages skipped: $GLOBAL_SKIPPED"
echo "   Local packages installed: $LOCAL_INSTALLED"
echo "   Local packages skipped: $LOCAL_SKIPPED"

echo "🎉 All done!"

