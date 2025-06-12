#!/usr/bin/env bash
# test-deps.sh - Quick test of dependency parsing
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-deps.sh"

echo "Testing dependency loading..."
load_dependencies "$SCRIPT_DIR/dependencies.yaml"

echo "Components found: ${COMPONENTS[*]}"
echo ""

for comp in "${COMPONENTS[@]}"; do
  echo "Component: $comp"
  echo "  Description: ${DESCRIPTIONS[$comp]}"
  echo "  Script: ${SCRIPTS[$comp]}"
  echo "  Requires: ${REQUIRES[$comp]}"
  echo ""
done

echo "Testing resolution for all components..."
readarray -t resolved < <(resolve_selected "${COMPONENTS[@]}" | tr ' ' '\n')
echo "Resolved order: ${resolved[*]}"
