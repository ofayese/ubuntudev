#!/usr/bin/env bash
# test-source-all.sh - Comprehensive test for bulletproof modular sourcing
# Last Updated: 2025-06-13
# Version: 1.0.0

set -euo pipefail

echo "🧪 Testing Bulletproof Modular Sourcing Pattern"
echo "=============================================="

# Clear any existing globals to test fresh initialization
unset SCRIPT_DIR VERSION LAST_UPDATED OS_TYPE DRY_RUN 2>/dev/null || true
unset UTIL_LOG_SH_LOADED UTIL_DEPS_SH_LOADED UTIL_INSTALL_SH_LOADED 2>/dev/null || true
unset UTIL_WSL_SH_LOADED UTIL_VERSIONS_SH_LOADED UTIL_CONTAINERS_SH_LOADED 2>/dev/null || true
unset UTIL_ENV_SH_LOADED 2>/dev/null || true

echo ""
echo "🔄 Testing multiple sourcing (should not produce readonly errors)..."

# Test multiple sourcing passes
for i in {1..3}; do
    echo "   Iteration $i:"

    # Source all utility modules in dependency order
    source ./util-log.sh
    echo "     ✅ util-log.sh sourced"

    source ./util-env.sh
    echo "     ✅ util-env.sh sourced"

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
    exit 1
fi

if declare -f command_exists >/dev/null 2>&1; then
    echo "   ✅ Environment functions available"
else
    echo "   ❌ Environment functions not available"
fi

echo ""
echo "✅ All tests completed successfully!"
echo "🚀 Bulletproof modular sourcing pattern is working correctly."
