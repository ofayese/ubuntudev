#!/usr/bin/env bash
set -euo pipefail

# Source the environment utility
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-env.sh"

# Call the function to output the environment type
detect_environment
