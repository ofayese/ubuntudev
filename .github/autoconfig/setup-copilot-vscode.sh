#!/usr/bin/env bash
set -eux

# Ensure VS Code settings are applied
mkdir -p .vscode
cp .github/.vscode/settings.json .vscode/settings.json || true

echo "✅ VS Code Copilot settings initialized."
