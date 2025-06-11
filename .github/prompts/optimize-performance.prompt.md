# Optimize Shell Script Performance

Analyze the selected shell script for performance optimization opportunities. Provide specific improvements for:

## Performance Bottlenecks

- **Command Execution**: Reduce subprocess calls and external command usage
- **File Operations**: Optimize file reading/writing and directory operations
- **Network Operations**: Implement caching, parallel requests, and connection reuse
- **Loop Efficiency**: Improve iteration patterns and reduce computational complexity

## Optimization Techniques

- **Caching**: Store expensive operation results in temporary files or variables
- **Parallel Processing**: Use background jobs for independent operations
- **Built-in vs External**: Replace external commands with bash built-ins when possible
- **String Operations**: Use parameter expansion instead of `sed`/`awk` for simple tasks

## Caching Patterns

```bash
# File-based caching
cache_expensive_operation() {
  local cache_file="/tmp/cache_${FUNCNAME[1]}"
  local cache_ttl=3600  # 1 hour
  
  if [[ -f "$cache_file" && $(($(date +%s) - $(stat -c %Y "$cache_file"))) -lt $cache_ttl ]]; then
    cat "$cache_file"
    return 0
  fi
  
  # Perform expensive operation
  local result=$(expensive_operation)
  echo "$result" > "$cache_file"
  echo "$result"
}
```

## Memory Optimization

- **Variable Scope**: Use `local` to prevent memory leaks
- **Array Usage**: Optimize array operations for large datasets
- **Stream Processing**: Process large files line-by-line instead of loading into memory
- **Cleanup**: Proper cleanup of temporary resources

## Benchmarking

- Add timing measurements: `time command`
- Profile script execution with `set -x`
- Monitor resource usage during execution
- Compare before/after performance metrics

## Output Requirements

- Provide specific code replacements for performance improvements
- Include benchmarking code to measure improvements
- Suggest profiling techniques for identifying bottlenecks
- Recommend performance monitoring approaches

Focus on measurable performance gains while maintaining script reliability and readability.
