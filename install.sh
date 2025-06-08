#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/ubuntu-dev-tools.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== [install.sh] Started at $(date) ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_TYPE=$("$SCRIPT_DIR/env-detect.sh")

show_help() {
  echo "Usage: $0 [options]"
  echo ""
  echo "  --all                 Install everything"
  echo "  --desktop             Run desktop customizations"
  echo "  --node-python         Setup Node.js and Python with version managers"
  echo "  --devtools            Install CLI dev tools, linters, shells, etc."
  echo "  --vscode              Install VS Code, Insiders, extensions, config"
  echo "  --devcontainers       Setup Docker Desktop or containerd/devcontainers"
  echo "  --dotnet-ai           Install .NET, PowerShell, AI/ML tools"
  echo "  --lang-sdks           Install Java, Rust, Haskell (via SDKMAN, rustup, ghcup)"
  echo "  --terminal            Finalize terminal: starship, alacritty, zsh plugins"
  echo "  --npm                 Install npm global and local dependencies"
  echo "  --help                Show this help message"
}

install_all() {
  "$SCRIPT_DIR/setup-desktop.sh"
  "$SCRIPT_DIR/setup-node-python.sh"
  "$SCRIPT_DIR/setup-devtools.sh"
  "$SCRIPT_DIR/setup-vscode.sh"
  "$SCRIPT_DIR/setup-devcontainers.sh"
  "$SCRIPT_DIR/setup-dotnet-ai.sh"
  "$SCRIPT_DIR/setup-lang-sdks.sh"
  "$SCRIPT_DIR/setup-terminal-enhancements.sh"
  "$SCRIPT_DIR/setup-npm.sh"
  "$SCRIPT_DIR/setup-vscommunity.sh"
  "$SCRIPT_DIR/validate-docker-desktop.sh"
  "$SCRIPT_DIR/setup-wsl.sh" 2>/dev/null || true
}

# --- Parse CLI arguments ---
if [[ $# -eq 0 ]]; then
  show_help
  exit 1
fi

for arg in "$@"; do
  case "$arg" in
    --all) install_all ;;
    --desktop) "$SCRIPT_DIR/setup-desktop.sh" ;;
    --node-python) "$SCRIPT_DIR/setup-node-python.sh" ;;
    --devtools) "$SCRIPT_DIR/setup-devtools.sh" ;;
    --vscode) "$SCRIPT_DIR/setup-vscode.sh" ;;
    --devcontainers) "$SCRIPT_DIR/setup-devcontainers.sh" ;;
    --dotnet-ai) "$SCRIPT_DIR/setup-dotnet-ai.sh" ;;
    --lang-sdks) "$SCRIPT_DIR/setup-lang-sdks.sh" ;;
    --terminal) "$SCRIPT_DIR/setup-terminal-enhancements.sh" ;;
    --npm) "$SCRIPT_DIR/setup-npm.sh" ;;
    --help|-h) show_help; exit 0 ;;
    *) echo "❌ Unknown option: $arg"; show_help; exit 1 ;;
  esac
done

# --- Final validation ---
echo "✅ Validating development environment..."

declare -A tools=(
  [nvm]="Node Version Manager"
  [pyenv]="Python Version Manager"
  [sdk]="SDKMAN for Java"
  [rustup]="Rust Toolchain Manager"
  [ghcup]="Haskell Toolchain Manager"
)

for cmd in "${!tools[@]}"; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "⚠️  ${tools[$cmd]} ($cmd) not found in PATH"
  else
    echo "✅ ${tools[$cmd]} is installed: $($cmd --version 2>/dev/null || true)"
  fi
done

if [[ "$ENV_TYPE" == "WSL2" ]]; then
  echo "🔍 WSL2 detected — verifying systemd state..."
  if pidof systemd &>/dev/null && systemctl is-system-running --quiet; then
    echo "✅ systemd is running inside WSL2"
  else
    echo "⚠️  systemd is not active in WSL2 — double-check your /etc/wsl.conf"
  fi

  echo ""
  echo "📢 To apply WSL configuration changes, please run:"
  echo "   👉 wsl --shutdown"
  echo "Then reopen your WSL terminal."
fi

echo ""
echo "🎉 All requested components installed successfully."
echo "💡 Restart your terminal or re-login for full effect."
