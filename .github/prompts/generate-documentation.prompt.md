# Generate Shell Script Documentation

Create comprehensive documentation for the selected shell script. Include:

## Header Documentation

```bash
#!/usr/bin/env bash
# script-name.sh - Brief description of script purpose
#
# Description:
#   Detailed explanation of what the script does, its main features,
#   and any important behavior or limitations.
#
# Usage:
#   ./script-name.sh [OPTIONS] [ARGUMENTS]
#   
# Options:
#   -h, --help        Show this help message
#   -v, --verbose     Enable verbose output
#   -d, --dry-run     Show what would be done without executing
#   -c, --config FILE Use specific configuration file
#
# Examples:
#   ./script-name.sh --verbose
#   ./script-name.sh --config /path/to/config.conf
#   ./script-name.sh --dry-run argument1 argument2
#
# Environment Variables:
#   SCRIPT_DEBUG      Set to 'true' to enable debug output
#   SCRIPT_CONFIG     Default configuration file path
#   SCRIPT_TIMEOUT    Timeout for network operations (default: 30s)
#
# Dependencies:
#   - bash 4.0+
#   - curl (for network operations)
#   - jq (for JSON processing)
#   - Optional: systemctl (for service management)
#
# Files:
#   ~/.config/script-name/config    Default configuration
#   /tmp/script-name.lock          Lock file for single instance
#   /var/log/script-name.log       Log file (if running as service)
#
# Exit Codes:
#   0    Success
#   1    General error
#   2    Invalid arguments or usage
#   126  Command not executable
#   127  Command not found
#   130  Script interrupted by user
#
# Author: [Author Name] <email@example.com>
# Version: 1.0.0
# Last Updated: $(date +%Y-%m-%d)
#
# License: [License Type]
```

## Function Documentation

For each function, provide:

```bash
# Function: function_name
# Description: What the function does
# Parameters:
#   $1 - Description of first parameter
#   $2 - Description of second parameter (optional)
# Returns:
#   0 - Success
#   1 - Error condition
# Globals:
#   GLOBAL_VAR - Description of global variable used
# Example:
#   function_name "param1" "param2"
function_name() {
  # Implementation
}
```

## README.md Section

Generate a README.md section that includes:

- Installation instructions
- Configuration guide
- Usage examples
- Troubleshooting common issues
- Contributing guidelines
- Change log

## Inline Comments

- Add explanatory comments for complex logic
- Document non-obvious bash features or tricks
- Explain environment-specific code sections
- Comment on security considerations

## Output Requirements

- Complete header documentation block
- Individual function documentation
- README.md content relevant to the script
- Suggested inline comments for complex sections

Focus on making the script self-documenting and easy for new developers to understand and maintain.
