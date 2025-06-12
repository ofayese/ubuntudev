#!/usr/bin/env bash
# install-new.sh - Main installer with dependency resolution and recovery
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-log.sh"
source "$SCRIPT_DIR/util-env.sh"
source "$SCRIPT_DIR/util-install.sh"
source "$SCRIPT_DIR/util-deps.sh"

LOGFILE="/var/log/ubuntu-dev-tools.log"
init_logging "$LOGFILE"
set_error_trap

STATE_FILE="$HOME/.ubuntu-devtools.state"
RESUME=false

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-prereqs) SKIP_PREREQS=true ;;
    --resume)       RESUME=true ;;
    --graph)        GRAPH=true ;;
    --validate)     VALIDATE=true ;;
    --all)          ALL=true ;;
    *) COMPONENT_FLAGS+=("$1") ;;
  esac
  shift
done

# Handle graph & validation
load_dependencies "$SCRIPT_DIR/dependencies.yaml"
if [[ "${GRAPH:-false}" == true ]]; then
  print_dependency_graph | tee "$SCRIPT_DIR/dependency-graph.dot"
  finish_logging; exit 0
fi
if [[ "${VALIDATE:-false}" == true ]]; then
  bash "$SCRIPT_DIR/validate-installation.sh"
  finish_logging; exit 0
fi

# Resume logic
[[ "${RESUME}" == true ]] || rm -f "$STATE_FILE"
touch "$STATE_FILE"

# Prereqs
[[ "${SKIP_PREREQS:-false}" == true ]] || bash "$SCRIPT_DIR/check-prerequisites.sh" || exit 1

# Determine components
load_dependencies "$SCRIPT_DIR/dependencies.yaml"
if [[ "${ALL:-false}" == true ]]; then
  selected=("${COMPONENTS[@]}")
else
  for f in "${COMPONENT_FLAGS[@]}"; do
    case "$f" in
      --devtools)            selected+=("devtools") ;;
      --terminal)            selected+=("terminal-enhancements") ;;
      --desktop)             selected+=("desktop") ;;
      --devcontainers)       selected+=("devcontainers") ;;
      --dotnet-ai)           selected+=("dotnet-ai") ;;
      --lang-sdks)           selected+=("lang-sdks") ;;
      --vscommunity)         selected+=("vscommunity") ;;
      --update-env)          selected+=("update-env") ;;
      --validate)            selected+=("validate") ;;
    esac
  done
fi

# Unique & ordered components
unique=(); declare -A seen
for c in "${selected[@]}"; do [[ -z "${seen[$c]}" ]] && unique+=("$c") && seen["$c"]=1; done
ordered=($(resolve_selected "${unique[@]}"))

log_info "Installation order: ${ordered[*]}"
log_info "Total components to install: ${#ordered[@]}"

mark_done() { grep -Fxq "$1" "$STATE_FILE" || echo "$1" >> "$STATE_FILE"; }
is_done()   { grep -Fxq "$1" "$STATE_FILE"; }

failed=(); declare -A skip
current_step=0

for comp in "${ordered[@]}"; do
  ((current_step++))
  
  if [[ "${RESUME}" == true && is_done "$comp" ]]; then
    log_info "Skipping $comp (already done)."
    show_progress "$current_step" "${#ordered[@]}" "Installation Progress"
    continue
  fi
  if [[ -n "${skip[$comp]:-}" ]]; then
    log_warning "Skipping $comp due to failed dependency."
    failed+=("$comp")
    show_progress "$current_step" "${#ordered[@]}" "Installation Progress"
    continue
  fi
  
  script="${SCRIPTS[$comp]}"
  desc="${DESCRIPTIONS[$comp]:-$comp}"
  
  log_info "[$current_step/${#ordered[@]}] Installing: $desc"
  show_progress "$current_step" "${#ordered[@]}" "Installation Progress"
  
  install_component "$script" "$desc" || { failed+=("$comp"); for d in ${DEPENDENTS[$comp]}; do skip["$d"]=1; done; }
  mark_done "$comp"
done

if [[ ${#failed[@]} -gt 0 ]]; then
  log_warning "Failures/skips:"
  for f in "${failed[@]}"; do log_error "  - $f"; done
  log_info "Run --resume to retry."
else
  log_success "All done!"
fi

finish_logging
