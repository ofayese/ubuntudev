#!/usr/bin/env bash
# test-update-env.sh - Simple test for update-environment.sh functions
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Test sourcing utilities
echo "Testing util-log.sh..."
source "$SCRIPT_DIR/util-log.sh" || {
    echo "ERROR: Failed to source util-log.sh"
    exit 1
}

echo "Testing util-env.sh..."
source "$SCRIPT_DIR/util-env.sh" || {
    echo "ERROR: Failed to source util-env.sh"
    exit 1
}

# Test key functions
echo "Testing init_logging..."
init_logging

echo "Testing set_error_trap..."
set_error_trap

echo "Testing detect_environment..."
ENV_TYPE=$(detect_environment)
echo "Environment: $ENV_TYPE"

echo "Testing logging functions..."
log_info "Test info message"
log_success "Test success message"
log_warning "Test warning message"

echo "Testing spinner functions..."
start_spinner "Testing spinner"
sleep 1
stop_spinner "default" "Spinner test completed"

echo "All tests passed!"
