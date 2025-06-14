#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC2034  # VERSION used in logging/reporting
readonly VERSION="1.0.0"

# Version: 1.0.0
# Last updated: 2025-06-13

# Source utility modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-log.sh"
source "$SCRIPT_DIR/util-env.sh"
source "$SCRIPT_DIR/util-install.sh"

# Initialize logging
init_logging
log_info "NPM packages setup started"

# --- Options ---
FORCE_REINSTALL=false
# shellcheck disable=SC2034  # QUIET_MODE reserved for future logging control
QUIET_MODE=false

# shellcheck disable=SC2034  # QUIET_MODE reserved for future logging control
while [[ $# -gt 0 ]]; do
  case $1 in
  --force | -f)
    FORCE_REINSTALL=true
    shift
    ;;
  --quiet | -q)
    QUIET_MODE=true
    shift
    ;;
  --help | -h)
    log_info "Usage: $0 [options]"
    log_info "  --force, -f    Force reinstall"
    log_info "  --quiet, -q    Quiet mode"
    log_info "  --help, -h     Show help"
    finish_logging
    exit 0
    ;;
  *)
    log_error "Unknown option: $1"
    finish_logging
    exit 1
    ;;
  esac
done

if ! command_exists npm; then
  log_error "npm is not installed. Please install Node.js + npm first"
  finish_logging
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

log_info "Installing global NPM packages..."
TO_INSTALL_GLOBAL=()

for pkg in "${GLOBAL_PACKAGES[@]}"; do
  if $FORCE_REINSTALL || ! is_npm_global_installed "$pkg"; then
    TO_INSTALL_GLOBAL+=("$pkg")
  else
    ((GLOBAL_SKIPPED++))
  fi
done

if [[ ${#TO_INSTALL_GLOBAL[@]} -gt 0 ]]; then
  log_info "Installing ${#TO_INSTALL_GLOBAL[@]} global packages: ${TO_INSTALL_GLOBAL[*]}"
  if npm install -g "${TO_INSTALL_GLOBAL[@]}"; then
    GLOBAL_INSTALLED=${#TO_INSTALL_GLOBAL[@]}
    log_success "Global packages installed successfully"
  else
    log_error "Failed to install some global packages"
  fi
else
  log_success "All global packages are already installed"
fi

log_info "Installing local devDependencies..."
TO_INSTALL_LOCAL=()

for pkg in "${DEV_PACKAGES[@]}"; do
  if $FORCE_REINSTALL || ! npm list --depth=0 "$pkg" &>/dev/null; then
    TO_INSTALL_LOCAL+=("$pkg")
  else
    ((LOCAL_SKIPPED++))
  fi
done

if [[ ${#TO_INSTALL_LOCAL[@]} -gt 0 ]]; then
  log_info "Installing ${#TO_INSTALL_LOCAL[@]} local packages: ${TO_INSTALL_LOCAL[*]}"
  if npm install --save-dev "${TO_INSTALL_LOCAL[@]}"; then
    LOCAL_INSTALLED=${#TO_INSTALL_LOCAL[@]}
    log_success "Local packages installed successfully"
  else
    log_error "Failed to install some local packages"
  fi
else
  log_success "All local packages are already installed"
fi

log_info "Summary:"
log_info "  Global packages installed: $GLOBAL_INSTALLED"
log_info "  Global packages skipped: $GLOBAL_SKIPPED"
log_info "  Local packages installed: $LOCAL_INSTALLED"
log_info "  Local packages skipped: $LOCAL_SKIPPED"

finish_logging
