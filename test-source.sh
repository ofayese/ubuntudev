#!/usr/bin/env bash
# test-source.sh - Test sourcing util-deps.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# Define variables that util-deps.sh also defines
readonly VERSION="1.0.0"
readonly LAST_UPDATED="2025-06-13"
readonly OS_TYPE="$(uname -s)"
readonly DRY_RUN="${DRY_RUN:-false}"

echo "Before sourcing: VERSION=$VERSION"

# Source util-deps.sh
source "$SCRIPT_DIR/util-deps.sh" || {
    echo "FATAL: Failed to source util-deps.sh" >&2
    exit 1
}

echo "After sourcing: VERSION=$VERSION"
echo "Test completed successfully"
