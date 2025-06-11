# Comprehensive Shell Script Code Review

Review the selected shell script for production readiness and provide specific, actionable feedback on:

## Critical Issues

- **Error Handling**: Verify `set -euo pipefail` usage and proper exit codes
- **Security**: Check for unquoted variables, input validation, and privilege escalation
- **Edge Cases**: Identify missing validations for empty inputs, missing files, network failures
- **Idempotency**: Ensure script can be run multiple times safely without side effects

## Environment Compatibility

- **Shebang**: Verify `#!/usr/bin/env bash` for maximum compatibility
- **WSL2/Desktop Detection**: Check proper environment detection patterns
- **Dependencies**: Validate all required commands/packages are checked before use
- **Path Handling**: Ensure proper handling of WSL2 (`/mnt/c/...`) vs native paths

## Code Quality

- **Function Design**: Check for single responsibility and proper parameter handling
- **Variable Scoping**: Verify `local` usage in functions and `readonly` for constants
- **Logging**: Assess structured logging with appropriate severity levels
- **Documentation**: Review inline comments, usage examples, and error messages

## Performance & Reliability

- **Resource Cleanup**: Check for proper `trap` usage and temporary file handling
- **Timeout Mechanisms**: Verify network operations have appropriate timeouts
- **Caching**: Identify opportunities for caching expensive operations
- **Memory Usage**: Check for potential memory leaks in loops or large file processing

Provide specific line numbers, suggested fixes, and alternative approaches where applicable. Focus on actionable improvements rather than stylistic preferences.
