#!/usr/bin/env bash
# install-new.sh - Main installer with dependency resolution and recovery
# Version: 1.0.0
# Last updated: 2025-06-13
set -euo pipefail

# Use declare first, then make readonly to avoid redeclaration issues
# when multiple scripts define the same constants
# VERSION is used for logging/reporting and debugging
declare VERSION="1.0.0"
export VERSION
readonly VERSION

# Script directory resolution - declare and assign separately to avoid masking return values
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# Global environment variables - export to be available in sourced scripts
# Use conditional declaration to avoid conflicts with other scripts
if [[ -z "${DRY_RUN+x}" ]]; then
  DRY_RUN="${DRY_RUN:-false}"
  export DRY_RUN
fi

# Operating system detection for cross-platform compatibility
# shellcheck disable=SC2034  # OS_TYPE may be used by sourced utilities
if [[ -z "${OS_TYPE+x}" ]]; then
  OS_TYPE="$(uname -s)"
  export OS_TYPE
fi

# Source utility modules with error checking
echo "DEBUG: About to source util-log.sh"
source "$SCRIPT_DIR/util-log.sh" || {
  echo "FATAL: Failed to source util-log.sh" >&2
  exit 1
}
echo "DEBUG: About to source util-env.sh"
source "$SCRIPT_DIR/util-env.sh" || {
  echo "FATAL: Failed to source util-env.sh" >&2
  exit 1
}
echo "DEBUG: About to source util-install.sh"
source "$SCRIPT_DIR/util-install.sh" || {
  echo "FATAL: Failed to source util-install.sh" >&2
  exit 1
}
echo "DEBUG: About to source util-deps.sh"
source "$SCRIPT_DIR/util-deps.sh" || {
  echo "FATAL: Failed to source util-deps.sh" >&2
  exit 1
}

# Use user-accessible log location instead of system directory
readonly LOGFILE="$HOME/.local/share/ubuntu-dev-tools/logs/ubuntu-dev-tools.log"
readonly STATE_FILE="$HOME/.ubuntu-devtools.state"

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOGFILE")"
# Simplified logging for debugging
# init_logging "$LOGFILE"
# set_error_trap

# Show help information
show_help() {
  cat <<'EOF'
🚀 Ubuntu Development Environment Installer
==========================================

USAGE:
  ./install-new.sh [OPTIONS] [COMPONENTS]

OPTIONS:
  --all                Install all available components
  --resume             Resume from previous failed installation
  --graph              Generate dependency graph and exit
  --validate           Run validation checks and exit
  --debug              Enable debug mode (set -x)
  --skip-prereqs       Skip prerequisite checks
  --help, -h           Show this help message

COMPONENTS:
  --devtools           Essential development tools (git, vim, curl, etc.)
  --terminal           Modern CLI tools (bat, ripgrep, fzf, etc.)
  --desktop            Desktop environment enhancements
  --devcontainers      Development containers setup
  --dotnet-ai          .NET and AI development tools
  --lang-sdks          Language SDKs (Node.js, Python, Java, etc.)
  --vscommunity        Visual Studio Code and extensions
  --update-env         Environment updates and optimizations

EXAMPLES:
  ./install-new.sh --all                    # Install everything
  ./install-new.sh --devtools --terminal    # Install dev tools and modern CLI
  ./install-new.sh --validate               # Just run validation
  ./install-new.sh --graph                  # Show dependency graph

FILES:
  dependencies.yaml                         # Component dependencies
  ~/.ubuntu-devtools.state                  # Installation state
  ~/.local/share/ubuntu-dev-tools/logs/     # Log files

For more information, see: README.md
EOF
}

# Parse flags
RESUME=false
GRAPH=false
VALIDATE=false
ALL=false
COMPONENT_FLAGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    show_help
    exit 0
    ;;
  --skip-prereqs)
    # shellcheck disable=SC2034  # SKIP_PREREQS may be used by sourced scripts
    SKIP_PREREQS=true
    ;;
  --resume) RESUME=true ;;
  --graph) GRAPH=true ;;
  --validate) VALIDATE=true ;;
  --all) ALL=true ;;
  --debug) set -x ;;
  *) COMPONENT_FLAGS+=("$1") ;;
  esac
  shift
done

# Handle graph & validation
load_dependencies "$SCRIPT_DIR/dependencies.yaml"
if [[ "${GRAPH:-false}" == true ]]; then
  print_dependency_graph | tee "$SCRIPT_DIR/dependency-graph.dot"
  finish_logging
  exit 0
fi
if [[ "${VALIDATE:-false}" == true ]]; then
  bash "$SCRIPT_DIR/validate-installation.sh"
  finish_logging
  exit 0
fi

# Resume logic
[[ "${RESUME}" == true ]] || rm -f "$STATE_FILE"
touch "$STATE_FILE"

# Prerequisites checking has been completely removed from the codebase
# Installation will proceed without prerequisite validation

# Determine components
load_dependencies "$SCRIPT_DIR/dependencies.yaml"
selected=()

if [[ "${ALL:-false}" == true ]]; then
  # Copy all components to selected array
  for comp in "${COMPONENTS[@]}"; do
    selected+=("$comp")
  done
else
  for f in "${COMPONENT_FLAGS[@]}"; do
    case "$f" in
    --devtools) selected+=("devtools") ;;
    --terminal) selected+=("terminal-enhancements") ;;
    --desktop) selected+=("desktop") ;;
    --devcontainers) selected+=("devcontainers") ;;
    --dotnet-ai) selected+=("dotnet-ai") ;;
    --lang-sdks) selected+=("lang-sdks") ;;
    --vscommunity) selected+=("vscommunity") ;;
    --update-env) selected+=("update-env") ;;
    --validate) selected+=("validate") ;;
    esac
  done
fi

# Unique & ordered components
unique=()
declare -A seen
echo "DEBUG: Processing selected components: ${selected[*]:-none}"
for c in "${selected[@]}"; do
  echo "DEBUG: Processing component: $c"
  [[ -z "${seen[$c]:-}" ]] && unique+=("$c") && seen["$c"]=1
done
echo "DEBUG: Unique components: ${unique[*]:-none}"

# Get resolved dependency order
echo "DEBUG: About to resolve dependencies for: ${unique[*]}"

# Simple dependency resolution - for now just use the selected components
# TODO: Fix the complex resolve_selected function
ordered=("${unique[@]}")
echo "DEBUG: Using simple order, got ${#ordered[@]} components"

echo "Selected components: ${unique[*]}"
echo "Installation order: ${ordered[*]}"
echo "Total components to install: ${#ordered[@]}"

mark_done() { grep -Fxq "$1" "$STATE_FILE" || echo "$1" >>"$STATE_FILE"; }
is_done() { grep -Fxq "$1" "$STATE_FILE"; }

failed=()
declare -A skip=()
current_step=0

for comp in "${ordered[@]}"; do
  current_step=$((current_step + 1))

  if [[ "${RESUME}" == "true" ]] && is_done "$comp"; then
    echo "Skipping $comp (already done)."
    # show_progress "$current_step" "${#ordered[@]}" "Installation Progress"
    continue
  fi
  if [[ -n "${skip[$comp]:-}" ]]; then
    echo "Skipping $comp due to failed dependency."
    failed+=("$comp")
    # show_progress "$current_step" "${#ordered[@]}" "Installation Progress"
    continue
  fi

  script="${SCRIPTS[$comp]}"
  desc="${DESCRIPTIONS[$comp]:-$comp}"

  echo "[$current_step/${#ordered[@]}] Installing: $desc"
  # show_progress "$current_step" "${#ordered[@]}" "Installation Progress"

  install_component "$script" "$desc" "$SCRIPT_DIR" || {
    failed+=("$comp")
    for d in ${DEPENDENTS[$comp]:-}; do skip["$d"]=1; done
  }
  mark_done "$comp"
done

if [[ ${#failed[@]} -gt 0 ]]; then
  echo "Failures/skips:"
  for f in "${failed[@]}"; do echo "  - $f"; done
  echo "Run --resume to retry."
else
  echo "All done!"
fi

# finish_logging
# finish_logging
