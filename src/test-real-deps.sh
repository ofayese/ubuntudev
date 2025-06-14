#!/usr/bin/env bash
# Simple test of actual dependency loading

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-log.sh"
source "$SCRIPT_DIR/util-deps.sh"

load_dependencies "$SCRIPT_DIR/dependencies.yaml"

echo "=== All Components ==="
for comp in "${COMPONENTS[@]}"; do
    echo "Component: $comp"
    echo "  Requires: '${REQUIRES[$comp]}'"
    echo ""
done

echo "=== Testing terminal-enhancements specifically ==="
echo "REQUIRES[terminal-enhancements]: '${REQUIRES[terminal - enhancements]}'"
echo "SCRIPTS[terminal-enhancements]: '${SCRIPTS[terminal - enhancements]}'"
