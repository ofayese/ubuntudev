#!/bin/bash
set -euo pipefail

detect_environment() {
  if grep -qi microsoft /proc/version; then
    echo "WSL2"
  elif command -v gnome-shell >/dev/null 2>&1 && \
       (echo "${XDG_SESSION_TYPE:-}" | grep -qE 'x11|wayland'); then
    echo "DESKTOP"
  else
    echo "HEADLESS"
  fi
}

# Call the function to output the environment type
detect_environment
