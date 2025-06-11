# Generate Comprehensive Bash Unit Tests

Generate comprehensive unit tests for the selected Bash script using the Bats testing framework. Follow these requirements:

## Test Structure

- Create test file named `test-<script-name>.bats`
- Include proper Bats shebang: `#!/usr/bin/env bats`
- Use descriptive test names that explain the scenario being tested
- Organize tests by function/feature with clear groupings

## Test Coverage Requirements

- **Happy Path**: Test normal execution with valid inputs
- **Edge Cases**: Empty inputs, missing files, invalid parameters
- **Error Conditions**: Network failures, permission issues, dependency missing
- **Environment Variations**: WSL2 vs Desktop vs Headless scenarios
- **Idempotency**: Verify script can run multiple times safely

## Test Patterns

```bash
@test "function_name: should handle valid input correctly" {
  # Setup
  local temp_dir=$(mktemp -d)
  
  # Execute
  run function_name "valid_input"
  
  # Assert
  [ "$status" -eq 0 ]
  [[ "$output" =~ "expected_pattern" ]]
  
  # Cleanup
  rm -rf "$temp_dir"
}
```

## Mocking & Setup

- Mock external dependencies (curl, apt, systemctl, etc.)
- Create temporary test environments when needed
- Use `setup()` and `teardown()` functions for common test setup
- Mock environment detection functions for different scenarios

## Assertions

- Check exit codes: `[ "$status" -eq 0 ]`
- Validate output patterns: `[[ "$output" =~ "pattern" ]]`
- Verify file operations: `[ -f "expected_file" ]`
- Test variable assignments and function returns

Output only the complete Bats test file with comprehensive coverage of the selected script.
