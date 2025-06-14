#!/usr/bin/env bash
# ubuntu-dev-test.sh - Comprehensive test script for utility loading
# Version: 1.0.0
# Last updated: 2025-06-13
set -euo pipefail

# Basic color definitions for test output
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
RESET="\033[0m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# Test utility declaration
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

print_header() {
    echo -e "${BLUE}=========================================${RESET}"
    echo -e "${BLUE}= Ubuntu Dev Environment - Test Suite =${RESET}"
    echo -e "${BLUE}=========================================${RESET}"
    echo ""
}

print_summary() {
    echo ""
    echo -e "${BLUE}=========================================${RESET}"
    echo -e "${BLUE}= Test Summary =${RESET}"
    echo -e "${BLUE}=========================================${RESET}"
    echo -e "Total Tests: ${TEST_COUNT}"
    echo -e "Passed: ${GREEN}${PASS_COUNT}${RESET}"

    if [[ $FAIL_COUNT -gt 0 ]]; then
        echo -e "Failed: ${RED}${FAIL_COUNT}${RESET}"
        exit 1
    else
        echo -e "Failed: ${FAIL_COUNT}"
        echo -e "${GREEN}All tests passed!${RESET}"
        exit 0
    fi
}

run_test() {
    local name="$1"
    local cmd="$2"
    ((TEST_COUNT++))

    echo -e "${YELLOW}[TEST]${RESET} $name"
    local output
    if output=$($cmd 2>&1); then
        echo -e "${GREEN}[PASS]${RESET} $name"
        echo "$output" | sed 's/^/  /'
        ((PASS_COUNT++))
    else
        local exit_code=$?
        echo -e "${RED}[FAIL]${RESET} $name (exit code: $exit_code)"
        echo "$output" | sed 's/^/  /'
        ((FAIL_COUNT++))
    fi
}

# Test utility creation
test_util_loading() {
    local utils=("util-log.sh" "util-env.sh" "util-install.sh" "util-deps.sh" "util-wsl.sh" "util-versions.sh" "util-containers.sh")
    local temp_script
    temp_script=$(mktemp)

    echo "#!/usr/bin/env bash" >"$temp_script"
    echo "set -euo pipefail" >>"$temp_script"
    echo "SCRIPT_DIR=\"$SCRIPT_DIR\"" >>"$temp_script"
    echo "readonly SCRIPT_DIR" >>"$temp_script"

    # Source each util one by one
    for util in "${utils[@]}"; do
        echo "echo \"Loading $util...\"" >>"$temp_script"
        echo "source \"\$SCRIPT_DIR/$util\" || { echo \"Failed to source $util\"; exit 1; }" >>"$temp_script"
    done

    # Source all again to test guard variables
    echo "echo \"Re-sourcing all utilities to test guard variables...\"" >>"$temp_script"
    for util in "${utils[@]}"; do
        echo "source \"\$SCRIPT_DIR/$util\" || { echo \"Failed to re-source $util\"; exit 1; }" >>"$temp_script"
    done

    echo "echo \"All utilities loaded successfully\"" >>"$temp_script"
    echo "exit 0" >>"$temp_script"

    chmod +x "$temp_script"
    "$temp_script"
    local result=$?
    rm "$temp_script"
    return $result
}

test_robust_deps() {
    # Test the install-robust.sh script's dependency resolution
    "$SCRIPT_DIR/install-robust.sh" --help >/dev/null
    return $?
}

test_new_deps() {
    # Test the install-new.sh script's dependency resolution
    "$SCRIPT_DIR/install-new.sh" --help >/dev/null
    return $?
}

# Main test sequence
print_header

run_test "Basic Utility Loading" test_util_loading
run_test "Robust Installer Dependencies" test_robust_deps
run_test "New Installer Dependencies" test_new_deps

print_summary
