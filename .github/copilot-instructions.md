# Global Copilot Instructions

## Code Generation Standards

- Prefer modular bash scripts with descriptive names: `check-prerequisites.sh`, `env-detect.sh`, etc.
- Use consistent shebangs: `#!/usr/bin/env bash` and adhere to POSIX compatibility
- Always include `set -euo pipefail` for strict error handling (prefer over `set -eux` for cleaner output)
- Implement proper error handling with meaningful exit codes (0=success, 1-255=various errors)
- Include comprehensive comments explaining complex logic and usage
- Follow consistent function naming: `snake_case` for functions, `UPPER_CASE` for constants

## Environment Awareness & Detection

- Always detect environment before making assumptions using utility functions
- WSL2: Check `/proc/version` or `/proc/sys/kernel/osrelease` for "microsoft" string
- Desktop: Verify `$DISPLAY` or `$WAYLAND_DISPLAY` environment variables
- Systemd: Use `systemctl is-system-running` to verify availability
- Respect WSL2 vs native Ubuntu paths; use `/mnt/c/...` for Windows file access
- Maintain headless compatibility (CLI-only) separate from desktop variants
- Test all scripts in both WSL2 and native Ubuntu environments

## Security & Performance Best Practices

- Always validate inputs and sanitize file paths before use
- Quote all variable expansions: `"${variable}"` to prevent word splitting
- Use `readonly` for constants and configuration values
- Implement timeout mechanisms for all network operations (default 30s)
- Cache expensive operations using temporary files or environment variables
- Avoid `sudo` unless absolutely necessary; prefer user-level operations
- Use `local` for all function variables to prevent scope pollution

## Error Handling & Logging

- Implement structured logging with severity levels (INFO, WARN, ERROR)
- Use consistent exit codes: 0=success, 1=general error, 2=misuse, 126=command not executable, 127=command not found
- Provide meaningful error messages with context and suggested fixes
- Include cleanup functions for temporary resources using `trap`
- Validate dependencies before script execution with clear failure messages

## Documentation & Maintainability

- Include comprehensive usage examples in script headers
- Document all expected environment variables and their defaults
- Provide troubleshooting sections for common failure scenarios
- Use consistent indentation (2 spaces) and formatting throughout
- Include version information and last updated timestamps
- Add inline comments for complex conditionals and business logic

## Integration Patterns

- Source utility scripts consistently: `source "${SCRIPT_DIR}/util-*.sh"`
- Use environment detection functions before environment-specific operations
- Implement proper dependency chains for installation scripts
- Handle both interactive and non-interactive execution modes
- Support dry-run mode for destructive operations
