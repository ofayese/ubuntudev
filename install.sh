#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/ubuntu-dev-tools.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== [install.sh] Started at $(date) ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Run prerequisites check first (unless skipped)
SKIP_PREREQS=false
if [[ "${1:-}" == "--skip-prereqs" ]]; then
    SKIP_PREREQS=true
    shift
fi

if [[ "$SKIP_PREREQS" == "false" ]]; then
    echo "🔍 Running prerequisites check..."
    if ! bash "$SCRIPT_DIR/check-prerequisites.sh"; then
        echo -e "${RED}❌ Prerequisites check failed. Please address the issues above.${NC}"
        echo -e "${YELLOW}💡 You can skip this check with --skip-prereqs flag (advanced users only)${NC}"
        exit 1
    fi
else
    echo "⚠️ Skipping prerequisites check as requested"
fi

ENV_TYPE=$("$SCRIPT_DIR/env-detect.sh")

# Function to run a script with error handling
run_script() {
    local script="$1"
    local description="$2"
    
    echo -e "\n${YELLOW}🚀 Running $description...${NC}"
    
    if [ -f "$SCRIPT_DIR/$script" ]; then
        if bash "$SCRIPT_DIR/$script"; then
            echo -e "${GREEN}✅ $description completed successfully${NC}"
            return 0
        else
            echo -e "${RED}❌ $description failed${NC}"
            return 1
        fi
    else
        echo -e "${RED}❌ Script $script not found${NC}"
        return 1
    fi
}

show_help() {
  echo "Usage: $0 [--skip-prereqs] [options]"
  echo ""
  echo "  --skip-prereqs        Skip prerequisites check (advanced users only)"
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
  echo "  --validate            Validate the installation"
  echo "  --help                Show this help message"
}

install_all() {
  local failed_scripts=()
  
  echo -e "${YELLOW}🌟 Installing all components for $ENV_TYPE environment...${NC}"
  
  # Desktop-specific components
  if [[ "$ENV_TYPE" == "DESKTOP" ]]; then
    run_script "setup-desktop.sh" "Desktop Environment Setup" || failed_scripts+=("setup-desktop.sh")
  fi
  
  # Core components for all environments
  run_script "setup-node-python.sh" "Node.js and Python Setup" || failed_scripts+=("setup-node-python.sh")
  run_script "setup-devtools.sh" "Development Tools Setup" || failed_scripts+=("setup-devtools.sh")
  run_script "setup-vscode.sh" "VS Code Setup" || failed_scripts+=("setup-vscode.sh")
  run_script "setup-devcontainers.sh" "Container Development Setup" || failed_scripts+=("setup-devcontainers.sh")
  run_script "setup-dotnet-ai.sh" ".NET and AI Tools Setup" || failed_scripts+=("setup-dotnet-ai.sh")
  run_script "setup-lang-sdks.sh" "Language SDKs Setup" || failed_scripts+=("setup-lang-sdks.sh")
  run_script "setup-terminal-enhancements.sh" "Terminal Enhancements" || failed_scripts+=("setup-terminal-enhancements.sh")
  run_script "setup-npm.sh" "NPM Packages Setup" || failed_scripts+=("setup-npm.sh")
  run_script "setup-vscommunity.sh" "Visual Studio Community Setup" || failed_scripts+=("setup-vscommunity.sh")
  run_script "validate-docker-desktop.sh" "Docker Desktop Validation" || failed_scripts+=("validate-docker-desktop.sh")
  
  # WSL-specific components
  if [[ "$ENV_TYPE" == "WSL2" ]]; then
    run_script "setup-wsl.sh" "WSL2 Optimizations" || failed_scripts+=("setup-wsl.sh")
  fi
  
  # Final validation
  run_script "validate-installation.sh" "Installation Validation" || failed_scripts+=("validate-installation.sh")
  
  # Report results
  if [ ${#failed_scripts[@]} -eq 0 ]; then
    echo -e "\n${GREEN}🎉 All components installed successfully!${NC}"
  else
    echo -e "\n${YELLOW}⚠️ Some components failed to install:${NC}"
    for script in "${failed_scripts[@]}"; do
      echo -e "${RED}  ❌ $script${NC}"
    done
    echo -e "\n${YELLOW}💡 You can retry failed components individually.${NC}"
  fi
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
