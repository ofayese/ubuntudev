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

# Script directory - calculate locally or use existing
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"

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

# Use function-local arrays to avoid global namespace pollution
resolve_comp() {
  local c="$1"
  local -n _temp_arr="$2"
  local -n _mark_arr="$3"
  local -n _resolved_arr="$4"

  [[ -n "${_temp_arr[$c]:-}" ]] && {
    log_error "Cycle at $c"
    exit 1
  }
  [[ -n "${_mark_arr[$c]:-}" ]] && return
  _temp_arr["$c"]=1
  for d in ${REQUIRES[$c]}; do
    resolve_comp "$d" _temp_arr _mark_arr _resolved_arr
  done
  _mark_arr["$c"]=1
  unset "_temp_arr[$c]"
  _resolved_arr+=("$c")
}

resolve_selected() {
  # Local arrays for resolution within this function call
  local -a resolved=()
  # shellcheck disable=SC2034  # TEMP is used via nameref in resolve_comp
  local -A MARK=() TEMP=()

  # Resolve the requested components
  for s in "$@"; do
    [[ -z "${MARK[$s]:-}" ]] && resolve_comp "$s" TEMP MARK resolved
  done
  echo "${resolved[@]}"
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
