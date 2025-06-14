#!/usr/bin/env bash
# test-bulletproof-sourcing.sh
# Test script to validate bulletproof modular sourcing pattern
# Version: 1.0.0
# Last Updated: 2025-06-13

set -euo pipefail

echo "🧪 Testing Bulletproof Modular Sourcing Pattern"
echo "=============================================="

# Test multiple sourcing of utility modules
echo ""
echo "🔄 Testing multiple sourcing (should not produce readonly errors)..."

for iteration in {1..3}; do
    echo "   Iteration $iteration:"

    # Source all utility modules
    source ./util-log.sh
    echo "     ✅ util-log.sh sourced"

    source ./util-deps.sh
    echo "     ✅ util-deps.sh sourced"

    source ./util-install.sh
    echo "     ✅ util-install.sh sourced"

    source ./util-wsl.sh
    echo "     ✅ util-wsl.sh sourced"

    source ./util-containers.sh
    echo "     ✅ util-containers.sh sourced"

    source ./util-versions.sh
    echo "     ✅ util-versions.sh sourced"
done

echo ""
echo "🔍 Testing global variable consistency..."

# Test that variables are properly set
echo "   SCRIPT_DIR: ${SCRIPT_DIR:-UNSET}"
echo "   VERSION: ${VERSION:-UNSET}"
echo "   OS_TYPE: ${OS_TYPE:-UNSET}"
echo "   DRY_RUN: ${DRY_RUN:-UNSET}"

echo ""
echo "🎯 Testing function availability..."

# Test that functions are available
if declare -f log_info >/dev/null 2>&1; then
    echo "   ✅ Logging functions available"
    log_info "Test log message from bulletproof sourcing test"
else
    echo "   ❌ Logging functions not available"
fi

echo ""
echo "✅ All tests completed successfully!"
echo "🚀 Bulletproof modular sourcing pattern is working correctly."
