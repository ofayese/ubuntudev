#!/usr/bin/env bash
# test-args.sh - Test argument parsing
set -euo pipefail

echo "Script received $# arguments:"
for ((i = 1; i <= $#; i++)); do
    echo "Arg $i: '${!i}'"
done
