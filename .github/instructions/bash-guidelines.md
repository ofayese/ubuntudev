---
applyTo: "**/*.sh"
---

# Bash Script Development Guidelines

## Script Structure Standards

- Always start with `#!/usr/bin/env bash` for maximum compatibility
- Include `set -euo pipefail` immediately after shebang for strict error handling
- Use consistent 2-space indentation throughout
- Organize code: constants, utilities, main functions, execution block

## Function Design Patterns

```bash
# Function template with proper error handling
function_name() {
  local param1="$1"
  local param2="${2:-default_value}"
  
  # Validate required parameters
  if [[ -z "$param1" ]]; then
    echo "Error: param1 is required" >&2
    return 1
  fi
  
  # Function logic here
  local result
  result=$(some_operation "$param1") || {
    echo "Error: Operation failed" >&2
    return 1
  }
  
  echo "$result"
  return 0
}
```

## Error Handling Best Practices

- Use meaningful exit codes (0=success, 1-255=various errors)
- Provide context in error messages with suggested solutions
- Implement cleanup with `trap` for temporary resources
- Log errors to stderr, normal output to stdout

## Variable and Constant Naming

- Use `UPPER_CASE` for constants and environment variables
- Use `snake_case` for function names and local variables
- Use `readonly` for constants to prevent modification
- Always quote variable expansions: `"${variable}"`

## Documentation Requirements

- Include comprehensive header with usage, examples, and dependencies
- Document all functions with parameters, return values, and examples
- Add inline comments for complex logic and environment-specific code
- Provide troubleshooting section for common issues
