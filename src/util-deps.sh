#!/usr/bin/env bash
# Utility: util-deps.sh
# Description: Dependency graph management utilities
# Last Updated: 2025-06-13
# Version: 1.0.0

set -euo pipefail

# Load guard to prevent multiple sourcing
if [[ -n "${UTIL_DEPS_SH_LOADED:-}" ]]; then
  return 0
fi
readonly UTIL_DEPS_SH_LOADED=1

# ------------------------------------------------------------------------------
# Global Variable Initialization (Safe conditional pattern)
# ------------------------------------------------------------------------------

# Script directory (only declare once globally)
if [[ -z "${SCRIPT_DIR:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  readonly SCRIPT_DIR
fi

# Version & timestamp (only declare once globally)
if [[ -z "${VERSION:-}" ]]; then
  VERSION="1.0.0"
  readonly VERSION
fi

if [[ -z "${LAST_UPDATED:-}" ]]; then
  LAST_UPDATED="2025-06-13"
  readonly LAST_UPDATED
fi

# OS detection (only declare once globally)
if [[ -z "${OS_TYPE:-}" ]]; then
  OS_TYPE="$(uname -s)"
  readonly OS_TYPE
fi

# Dry run support (only declare once globally)
if [[ -z "${DRY_RUN:-}" ]]; then
  DRY_RUN="false"
  readonly DRY_RUN
fi

# ------------------------------------------------------------------------------
# Dependency: Logging functions (optional)
# ------------------------------------------------------------------------------

if [[ -z "${UTIL_LOG_SH_LOADED:-}" && -f "${SCRIPT_DIR}/util-log.sh" ]]; then
  source "${SCRIPT_DIR}/util-log.sh" || {
    echo "[ERROR] Failed to source util-log.sh" >&2
    exit 1
  }
fi

# ------------------------------------------------------------------------------
# Module Functions
# ------------------------------------------------------------------------------

# Initialize/clear dependency arrays if they don't exist or we need fresh state
# Use conditional declaration to avoid redeclaring if already sourced in parent script
if [[ -z "${REQUIRES+x}" ]]; then
  declare -A REQUIRES=() DEPENDENTS=() SCRIPTS=() DESCRIPTIONS=()
  declare -a COMPONENTS=()
  # Export arrays for use by other scripts
  export REQUIRES DEPENDENTS SCRIPTS DESCRIPTIONS COMPONENTS
fi

load_dependencies() {
  local yaml="$1"
  local comp=""
  local in_components=false

  while IFS= read -r line; do
    # Keep original line for indentation checking
    local original_line="$line"
    # Trim only trailing whitespace for content extraction
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue

    # Check if we're entering the components section
    if [[ "$line" == "components:" ]]; then
      in_components=true
      continue
    fi

    # Stop processing if we hit the legacy section or any other top-level section
    if [[ "$line" =~ ^[a-z]+:$ && "$line" != "components:" && "$in_components" == true ]]; then
      break
    fi

    # Only process lines within the components section
    if [[ "$in_components" == true ]]; then
      # Check for component name (indented with 2 spaces)
      if [[ "$original_line" =~ ^[[:space:]]{2}([A-Za-z0-9_-]+):$ ]]; then
        comp="${BASH_REMATCH[1]}"
        COMPONENTS+=("$comp")
        REQUIRES["$comp"]=""
        SCRIPTS["$comp"]=""
        DESCRIPTIONS["$comp"]=""
      fi

      # Process component properties (indented with 4+ spaces)
      if [[ -n "$comp" ]]; then
        # Handle legacy requires format
        if [[ "$original_line" =~ ^[[:space:]]{4,}requires:[[:space:]]*\[(.*)\]$ ]]; then
          # Handle array format: requires: ["item1", "item2"]
          local req_list="${BASH_REMATCH[1]}"
          req_list="${req_list//\"/}" # Remove quotes
          req_list="${req_list//,/ }" # Replace commas with spaces
          REQUIRES["$comp"]="$req_list"
        elif [[ "$original_line" =~ ^[[:space:]]{4,}requires:[[:space:]]*(.*)$ ]]; then
          # Handle simple format: requires: item
          REQUIRES["$comp"]="${BASH_REMATCH[1]//\"/}"

        # Handle new dependencies.required format
        elif [[ "$original_line" =~ ^[[:space:]]{6,}required:[[:space:]]*\[(.*)\]$ ]]; then
          # Handle array format under dependencies: required: ["item1", "item2"]
          local req_list="${BASH_REMATCH[1]}"
          req_list="${req_list//\"/}" # Remove quotes
          req_list="${req_list//,/ }" # Replace commas with spaces
          REQUIRES["$comp"]="$req_list"
        elif [[ "$original_line" =~ ^[[:space:]]{6,}required:[[:space:]]*(.*)$ ]]; then
          # Handle simple format under dependencies: required: item
          local req_value="${BASH_REMATCH[1]//\"/}"
          [[ "$req_value" != "[]" ]] && REQUIRES["$comp"]="$req_value"

        elif [[ "$original_line" =~ ^[[:space:]]{4,}script:[[:space:]]*\"?([^\"]+)\"?$ ]]; then
          SCRIPTS["$comp"]="${BASH_REMATCH[1]}"
        elif [[ "$original_line" =~ ^[[:space:]]{4,}description:[[:space:]]*\"([^\"]+)\"$ ]]; then
          # Handle quoted descriptions
          DESCRIPTIONS["$comp"]="${BASH_REMATCH[1]}"
        elif [[ "$original_line" =~ ^[[:space:]]{4,}description:[[:space:]]*([^\"]+)$ ]]; then
          # Handle unquoted descriptions
          DESCRIPTIONS["$comp"]="${BASH_REMATCH[1]}"
        fi
      fi
    fi
  done <"$yaml"

  # Build dependents mapping
  for c in "${COMPONENTS[@]}"; do
    for d in ${REQUIRES[$c]}; do DEPENDENTS["$d"]+="$c "; done
  done
}

# Revert to a simpler implementation to avoid circular name reference issues
# These declarations are okay here because they're being used by the functions below
declare -a _resolved_components=()
declare -A _mark_map=() _temp_map=()

# Simple implementation that avoids nameref issues
resolve_comp() {
  local c="$1"
  [[ -n "${_temp_map[$c]:-}" ]] && {
    log_error "Cycle detected at component: $c"
    exit 1
  }
  [[ -n "${_mark_map[$c]:-}" ]] && return

  # Mark as being processed
  _temp_map["$c"]=1

  # Process dependencies
  for d in ${REQUIRES[$c]:-}; do
    resolve_comp "$d"
  done

  # Mark as resolved
  _mark_map["$c"]=1
  unset "_temp_map[$c]"
  _resolved_components+=("$c")
}

resolve_selected() {
  # Reset global resolution state
  _resolved_components=()
  _mark_map=()
  _temp_map=()

  # Process each requested component
  for s in "$@"; do
    if [[ -n "${COMPONENTS[*]}" && " ${COMPONENTS[*]} " != *" $s "* ]]; then
      log_error "Unknown component: $s"
      continue
    fi
    [[ -z "${_mark_map[$s]:-}" ]] && resolve_comp "$s"
  done

  # Return the resolved components
  echo "${_resolved_components[@]:-}"
}

print_dependency_graph() {
  echo "digraph G {"
  for c in "${COMPONENTS[@]}"; do
    if [[ -z "${REQUIRES[$c]}" ]]; then
      echo "  $c;"
    else
      for d in ${REQUIRES[$c]}; do echo "  $d -> $c;"; done
    fi
  done
  echo "}"
}
