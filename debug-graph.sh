#!/usr/bin/env bash
# Debug dependency graph generation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-log.sh"
source "$SCRIPT_DIR/util-deps.sh"

load_dependencies "$SCRIPT_DIR/dependencies.yaml"

echo "=== Manual graph generation ==="
echo "digraph G {"
for c in "${COMPONENTS[@]}"; do
    echo "Processing component: $c"
    echo "  Requires: '${REQUIRES[$c]}'"
    if [[ -z "${REQUIRES[$c]}" ]]; then
        echo "  -> Standalone: $c;"
    else
        for d in ${REQUIRES[$c]}; do
            echo "  -> Edge: $d -> $c;"
        done
    fi
done
echo "}"
