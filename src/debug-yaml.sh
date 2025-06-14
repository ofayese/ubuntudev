#!/usr/bin/env bash
# Debug YAML parsing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-log.sh"

# Inline simple YAML parser for debugging
declare -A REQUIRES=() SCRIPTS=() DESCRIPTIONS=()
declare -a COMPONENTS=()

load_dependencies_debug() {
    local yaml="$1"
    local comp=""
    local in_components=false
    local line_num=0

    while IFS= read -r line; do
        line_num=$((line_num + 1))
        # Keep original line for indentation checking
        local original_line="$line"
        # Trim only trailing whitespace for content extraction
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "$line" == \#* ]] && continue

        # Check if we're entering the components section
        if [[ "$line" == "components:" ]]; then
            echo "DEBUG: Found components section at line $line_num"
            in_components=true
            continue
        fi

        # Only process lines within the components section
        if [[ "$in_components" == true ]]; then
            # Check for component name (indented with 2 spaces)
            if [[ "$original_line" =~ ^[[:space:]]{2}([A-Za-z0-9_-]+):$ ]]; then
                comp="${BASH_REMATCH[1]}"
                echo "DEBUG: Found component '$comp' at line $line_num"
                COMPONENTS+=("$comp")
                REQUIRES["$comp"]=""
                SCRIPTS["$comp"]=""
                DESCRIPTIONS["$comp"]=""
            fi

            # Process component properties (indented with 4+ spaces)
            if [[ -n "$comp" ]]; then
                # Handle new dependencies.required format
                if [[ "$original_line" =~ ^[[:space:]]{6,}required:[[:space:]]*\[(.*)\]$ ]]; then
                    # Handle array format under dependencies: required: ["item1", "item2"]
                    local req_list="${BASH_REMATCH[1]}"
                    req_list="${req_list//\"/}" # Remove quotes
                    req_list="${req_list//,/ }" # Replace commas with spaces
                    echo "DEBUG: Found required array for '$comp': '$req_list' at line $line_num"
                    REQUIRES["$comp"]="$req_list"
                elif [[ "$original_line" =~ ^[[:space:]]{6,}required:[[:space:]]*(.*)$ ]]; then
                    # Handle simple format under dependencies: required: item
                    local req_value="${BASH_REMATCH[1]//\"/}"
                    echo "DEBUG: Found required value for '$comp': '$req_value' at line $line_num"
                    [[ "$req_value" != "[]" ]] && REQUIRES["$comp"]="$req_value"
                elif [[ "$original_line" =~ ^[[:space:]]{4,}script:[[:space:]]*\"?([^\"]+)\"?$ ]]; then
                    echo "DEBUG: Found script for '$comp': '${BASH_REMATCH[1]}' at line $line_num"
                    SCRIPTS["$comp"]="${BASH_REMATCH[1]}"
                elif [[ "$original_line" =~ ^[[:space:]]{4,}description:[[:space:]]*\"([^\"]+)\"$ ]]; then
                    echo "DEBUG: Found description for '$comp': '${BASH_REMATCH[1]}' at line $line_num"
                    DESCRIPTIONS["$comp"]="${BASH_REMATCH[1]}"
                fi
            fi
        fi
    done <"$yaml"
}

echo "=== Loading dependencies with debug ==="
load_dependencies_debug "$SCRIPT_DIR/dependencies.yaml"

echo ""
echo "=== Components loaded ==="
for comp in "${COMPONENTS[@]:-}"; do
    echo "Component: $comp"
    echo "  Requires: '${REQUIRES[$comp]:-}'"
    echo "  Script: '${SCRIPTS[$comp]:-}'"
    echo "  Description: '${DESCRIPTIONS[$comp]:-}'"
    echo ""
done
