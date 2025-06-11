# Security Audit for Shell Scripts

Perform a comprehensive security audit of the selected shell script. Analyze for:

## Critical Security Issues

- **Command Injection**: Unvalidated user input in command execution
- **Path Traversal**: Unsafe file path handling and directory operations
- **Privilege Escalation**: Unnecessary sudo usage or privilege requirements
- **Information Disclosure**: Sensitive data in logs, error messages, or temporary files

## Input Validation & Sanitization

```bash
# Secure input validation example
validate_input() {
  local input="$1"
  local pattern="$2"
  
  # Check for required input
  if [[ -z "$input" ]]; then
    echo "Error: Input required" >&2
    return 1
  fi
  
  # Validate against pattern
  if [[ ! "$input" =~ $pattern ]]; then
    echo "Error: Invalid input format" >&2
    return 1
  fi
  
  # Sanitize input
  input="${input//[^a-zA-Z0-9._-]/}"
  echo "$input"
}
```

## Safe File Operations

- **Temporary Files**: Use `mktemp` with proper permissions
- **File Permissions**: Set restrictive permissions (600/700) for sensitive files
- **Symbolic Links**: Validate symlink targets to prevent traversal attacks
- **Race Conditions**: Use atomic operations for file creation

## Environment Security

- **Variable Quoting**: Ensure all variables are properly quoted
- **PATH Security**: Avoid relying on PATH for critical commands
- **Environment Cleanup**: Clear sensitive environment variables
- **Signal Handling**: Proper cleanup on script termination

## Network Security

- **URL Validation**: Validate URLs before making requests
- **Certificate Verification**: Ensure SSL/TLS certificate validation
- **Timeout Settings**: Implement timeouts to prevent hanging
- **Credential Handling**: Secure storage and transmission of credentials

## Secure Patterns

```bash
# Secure command execution
execute_safe_command() {
  local cmd="$1"
  local args=("${@:2}")
  
  # Validate command exists
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: Command not found: $cmd" >&2
    return 127
  fi
  
  # Execute with controlled environment
  env -i PATH="/usr/bin:/bin" "$cmd" "${args[@]}"
}

# Secure temporary file creation
create_secure_temp() {
  local temp_file
  temp_file=$(mktemp) || return 1
  chmod 600 "$temp_file"
  echo "$temp_file"
}
```

## Audit Checklist

- [ ] All user inputs are validated and sanitized
- [ ] File operations use absolute paths or proper validation
- [ ] No hardcoded credentials or sensitive information
- [ ] Proper error handling without information disclosure
- [ ] Minimal privilege requirements
- [ ] Secure temporary file handling
- [ ] Network operations use secure protocols
- [ ] Input vectors are identified and protected

## Output Requirements

- List specific security vulnerabilities found
- Provide secure code replacements
- Suggest additional security measures
- Include security testing recommendations

Focus on practical security improvements that can be implemented immediately to reduce attack surface.
