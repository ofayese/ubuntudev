#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/ubuntu-dev-tools.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== [install.sh] Started at $(date) ==="


IS_HEADLESS=0
if ! (command -v gnome-shell >/dev/null 2>&1 && echo $XDG_SESSION_TYPE | grep -q 'x11\|wayland'); then
  IS_HEADLESS=1
  echo "🕶 Headless environment detected. GUI modules will be skipped."
fi

SUMMARY_LOG="/var/log/ubuntu-dev-setup-summary.txt"
echo "Ubuntu Dev Setup Summary - $(date)" > "$SUMMARY_LOG"


run_script() {
  script=$1
  if [[ "$script" == *"desktop"* && "$IS_HEADLESS" -eq 1 ]]; then
    echo "[SKIPPED] $script (headless)" | tee -a "$SUMMARY_LOG"
  else
    echo "[RUNNING] $script" | tee -a "$SUMMARY_LOG"
    ./$script
    echo "[COMPLETED] $script" >> "$SUMMARY_LOG"
  fi
}

OPTIONS=("devcontainers" "desktop" "devtools" "dotnet-ai" "npm" "node-python" "wsl" "vscode" "all")

for opt in "${OPTIONS[@]}"; do
  case "$opt" in
    devcontainers) run_script setup-devcontainers.sh ;;
    desktop) run_script setup-desktop.sh ;;
    devtools) run_script setup-devtools.sh ;;
    dotnet-ai) run_script setup-dotnet-ai.sh ;;
    npm) run_script setup-npm.sh ;;
    node-python) run_script setup-node-python.sh ;;
    wsl) run_script setup-wsl.sh ;;
    vscode) run_script setup-vscode.sh ;;
    all)
      run_script setup-devcontainers.sh
      run_script setup-desktop.sh
      run_script setup-devtools.sh
      run_script setup-dotnet-ai.sh
      run_script setup-npm.sh
      run_script setup-node-python.sh
      run_script setup-wsl.sh
      run_script setup-vscode.sh
    ;;
  esac
done

echo "✅ Summary written to $SUMMARY_LOG"
