#!/usr/bin/env bash
# util-deps.sh - Dependency graph management
# Version: 1.0.0
# Last updated: 2025-06-13
set -euo pipefail

# Guard against multiple sourcing
if [[ "${UTIL_DEPS_LOADED:-}" == "true" ]]; then
  return 0
fi

# Set this first, before any potential exits
UTIL_DEPS_LOADED="true"

# Script version and last updated timestamp - scoped only to this script
# Use local variables rather than readonly globals to avoid redeclaration issues
# shellcheck disable=SC2034  # Used for version reporting in debug scenarios
declare UTIL_DEPS_VERSION="1.0.0"
# shellcheck disable=SC2034  # Used for version reporting in debug scenarios
declare UTIL_DEPS_LAST_UPDATED="2025-06-13"

# Cross-platform support - use global if set, otherwise set locally
# But don't make it readonly to avoid redeclaration issues
if [[ -z "${OS_TYPE:-}" ]]; then
  OS_TYPE="$(uname -s)"
  export OS_TYPE
fi

# Dry-run mode support - use global if set, otherwise set locally
# But don't make it readonly to avoid redeclaration issues
if [[ -z "${DRY_RUN:-}" ]]; then
  DRY_RUN="${DRY_RUN:-false}"
  export DRY_RUN
fi

# Mark as loaded only after successful initialization
readonly UTIL_DEPS_LOADED

# Script directory - use existing SCRIPT_DIR if available, otherwise calculate locally
if [[ -z "${SCRIPT_DIR:-}" ]]; then
  SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
fi

source "$SCRIPT_DIR/util-log.sh" || {
  echo "FATAL: Failed to source util-log.sh" >&2
  exit 1
}

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
        if [[ "$original_line" =~ ^[[:space:]]{4,}requires:[[:space:]]*\[(.*)\]$ ]]; then
          # Handle array format: requires: ["item1", "item2"]
          local req_list="${BASH_REMATCH[1]}"
          req_list="${req_list//\"/}" # Remove quotes
          req_list="${req_list//,/ }" # Replace commas with spaces
          REQUIRES["$comp"]="$req_list"
        elif [[ "$original_line" =~ ^[[:space:]]{4,}requires:[[:space:]]*(.*)$ ]]; then
          # Handle simple format: requires: item
          REQUIRES["$comp"]="${BASH_REMATCH[1]//\"/}"
        elif [[ "$original_line" =~ ^[[:space:]]{4,}script:[[:space:]]*\"?([^\"]+)\"?$ ]]; then
          SCRIPTS["$comp"]="${BASH_REMATCH[1]}"
        elif [[ "$original_line" =~ ^[[:space:]]{4,}description:[[:space:]]*\"([^\"]+)\"$ ]]; then
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
