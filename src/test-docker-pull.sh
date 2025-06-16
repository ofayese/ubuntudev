#!/usr/bin/env bash
# Simple test script for the simplified docker-pull-essentials

echo "Testing simplified docker-pull-essentials.sh..."
echo "==============================================="

# Make sure the script is executable
chmod +x ./docker-pull-essentials.sh

# Test 1: Show help
echo "Test 1: Help output"
./docker-pull-essentials.sh --help

echo -e "\n\nTest 2: Dry run test (sequential processing)"
./docker-pull-essentials.sh --config ./docker-pull-config.yaml --dry-run

echo -e "\n\nTo run actual pulls sequentially:"
echo "./docker-pull-essentials.sh --config ./docker-pull-config.yaml"
echo ""
echo "The script now pulls images one at a time for better reliability!"
