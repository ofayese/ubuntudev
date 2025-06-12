#!/usr/bin/env bash
# util-deps.sh - Dependency graph management
set -euo pipefail

# Guard against multiple sourcing
if [[ "${UTIL_DEPS_LOADED:-}" == "true" ]]; then
  return 0
fi
readonly UTIL_DEPS_LOADED="true"

source "$(dirname "${BASH_SOURCE[0]}")/util-log.sh"

declare -A REQUIRES DEPENDENTS SCRIPTS DESCRIPTIONS
COMPONENTS=()

# Export arrays for use by other scripts
export REQUIRES DEPENDENTS SCRIPTS DESCRIPTIONS COMPONENTS

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
          req_list="${req_list//\"/}"  # Remove quotes
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
  done < "$yaml"
  
  # Build dependents mapping
  for c in "${COMPONENTS[@]}"; do
    for d in ${REQUIRES[$c]}; do DEPENDENTS["$d"]+="$c "; done
  done
}

resolved=(); declare -A MARK TEMP SEL
resolve_comp() {
  local c="$1"
  [[ -n "${TEMP[$c]:-}" ]] && { log_error "Cycle at $c"; exit 1; }
  [[ -n "${MARK[$c]:-}" ]] && return
  TEMP["$c"]=1
  for d in ${REQUIRES[$c]}; do resolve_comp "$d"; done
  MARK["$c"]=1; unset "TEMP[$c]"; resolved+=("$c")
}

resolve_selected() {
  # Reset arrays for fresh resolution
  resolved=()
  declare -A MARK TEMP SEL
  
  for s in "$@"; do SEL["$s"]=1; done
  for s in "$@"; do [[ -z "${MARK[$s]:-}" ]] && resolve_comp "$s"; done
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
