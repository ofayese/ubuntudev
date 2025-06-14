#!/usr/bin/env bash
# verify-fix.sh - Verify that util-deps.sh can be sourced with readonly variables
set -euo pipefail

echo "=== Starting verification ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "SCRIPT_DIR=${SCRIPT_DIR}"

echo "=== Defining readonly variables ==="
VERSION="2.0.0"
LAST_UPDATED="2025-06-13"
OS_TYPE="$(uname -s)"
DRY_RUN="${DRY_RUN:-false}"

# Make them readonly
readonly VERSION
readonly LAST_UPDATED
readonly OS_TYPE
readonly DRY_RUN

echo "=== Successfully defined readonly variables ==="
echo "VERSION=$VERSION"
echo "LAST_UPDATED=$LAST_UPDATED"
echo "OS_TYPE=$OS_TYPE"
echo "DRY_RUN=$DRY_RUN"

# Now source util-deps.sh to see if it works without errors
echo "=== Attempting to source util-deps.sh... ==="
source "$SCRIPT_DIR/util-deps.sh" || {
    echo "ERROR: Failed to source util-deps.sh"
    exit 1
}
echo "=== Successfully sourced util-deps.sh ==="

# Print the values again to confirm they are intact
echo "=== After sourcing: ==="
echo "VERSION=$VERSION"
echo "LAST_UPDATED=$LAST_UPDATED"
echo "OS_TYPE=$OS_TYPE"
echo "DRY_RUN=$DRY_RUN"

echo "=== Test completed successfully - the fix is working! ==="
