#!/usr/bin/env bash
# test-dependency-loading.sh - Test script for dependency management
# This script tests for variable redeclaration issues when sourcing multiple utility scripts
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# Enable extended debug mode
echo "Starting dependency load test..."
echo "==============================================="

# Source utilities with error checking
echo "1. Loading util-log.sh..."
source "$SCRIPT_DIR/util-log.sh" || {
    echo "FATAL: Failed to source util-log.sh" >&2
    exit 1
}

echo "2. Loading util-env.sh..."
source "$SCRIPT_DIR/util-env.sh" || {
    echo "FATAL: Failed to source util-env.sh" >&2
    exit 1
}

echo "3. Loading util-install.sh..."
source "$SCRIPT_DIR/util-install.sh" || {
    echo "FATAL: Failed to source util-install.sh" >&2
    exit 1
}

echo "4. Loading util-deps.sh..."
source "$SCRIPT_DIR/util-deps.sh" || {
    echo "FATAL: Failed to source util-deps.sh" >&2
    exit 1
}

# Test dependency loading
echo "5. Loading dependencies from YAML..."
load_dependencies "$SCRIPT_DIR/dependencies.yaml"

# Print dependency info
echo "6. Dependency information:"
echo "   - Components: ${#COMPONENTS[@]}"
for comp in "${COMPONENTS[@]}"; do
    echo "   - $comp requires: ${REQUIRES[$comp]}"
    [[ -n "${SCRIPTS[$comp]}" ]] && echo "     Script: ${SCRIPTS[$comp]}"
done

echo "7. Now trying to source scripts again (should be skipped)..."
source "$SCRIPT_DIR/util-log.sh"
source "$SCRIPT_DIR/util-deps.sh"

echo "8. Testing dependency resolution..."
selected=(setup-desktop setup-lang-sdks)
echo "   - Resolving: ${selected[*]}"
# shellcheck disable=SC2207  # Using command substitution to populate array deliberately
IFS=" " read -r -a resolved <<<"$(resolve_selected "${selected[@]}")"
echo "   - Resolution order: ${resolved[*]}"

echo "==============================================="
echo "Test completed successfully!"
exit 0
