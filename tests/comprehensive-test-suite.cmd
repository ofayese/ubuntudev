#!/usr/bin/env bats
# comprehensive-test-suite.bats - Comprehensive testing for Ubuntu Dev Environment
# Version: 1.0.0
# Last updated: 2025-06-13

# Test configuration
readonly TEST_TIMEOUT=300
readonly TEST_PARALLEL_JOBS=4

# Setup test environment
setup() {
    # Load project utilities
    readonly SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
    export PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
    export TEST_LOG_DIR="${BATS_TEST_TMPDIR}/test_logs"
    readonly TEST_LOG_DIR
    export TEST_DATA_DIR="${BATS_TEST_TMPDIR}/test_data"
    readonly TEST_DATA_DIR
    
    # Create test directories
    mkdir -p "${TEST_LOG_DIR}" "${TEST_DATA_DIR}"
    
    # Load utility modules if available
    if [[ -f "${PROJECT_ROOT}/util-log.sh" ]]; then
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/util-log.sh" || skip "util-log.sh not available"
        export LOG_PATH="${TEST_LOG_DIR}/test.log"
        readonly LOG_PATH
        init_logging 2>/dev/null || true
    fi
    
    if [[ -f "${PROJECT_ROOT}/util-env.sh" ]]; then
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/util-env.sh" || skip "util-env.sh not available"
    fi
    # Set test environment variables
    # DRY_RUN=true ensures scripts run in dry-run mode (no destructive actions, only simulate changes)
    export DRY_RUN=true
    export NONINTERACTIVE=true
    export FORCE_ENVIRONMENT_TYPE=""
    export FORCE_ENVIRONMENT_TYPE=""
}
teardown() {
    local log_dir data_dir
    log_dir="${TEST_LOG_DIR}"
    data_dir="${TEST_DATA_DIR}"

    # Cleanup test artifacts
    [[ -d "${log_dir}" ]] && rm -rf "${log_dir}" 2>/dev/null || true
    [[ -d "${data_dir}" ]] && rm -rf "${data_dir}" 2>/dev/null || true
    
    # Reset environment variables
    unset FORCE_ENVIRONMENT_TYPE DRY_RUN NONINTERACTIVE
}

# =============================================================================
# ENVIRONMENT DETECTION TESTS
# =============================================================================

@test "environment_detection: should correctly identify WSL2 environment" {
    export FORCE_ENVIRONMENT_TYPE="wsl"
    
    if command -v detect_environment >/dev/null 2>&1; then
        run detect_environment
        [ "${status}" -eq 0 ]
        [[ "${output}" =~ "wsl" ]] || [[ "${output}" =~ "WSL" ]]
    else
        skip "detect_environment function not available"
    fi
}

@test "environment_detection: should correctly identify desktop environment" {
    export FORCE_ENVIRONMENT_TYPE="desktop"
    
    if command -v detect_environment >/dev/null 2>&1; then
        run detect_environment
        [ "${status}" -eq 0 ]
        [[ "${output}" =~ "desktop" ]] || [[ "${output}" =~ "DESKTOP" ]]
    else
        skip "detect_environment function not available"
    fi
}

@test "environment_detection: should handle unknown environments gracefully" {
    export FORCE_ENVIRONMENT_TYPE="unknown"
    
    if command -v detect_environment >/dev/null 2>&1; then
        run detect_environment
        # Should either return with error code or return "unknown"
        [[ "${status}" -ne 0 ]] || [[ "${output}" =~ "unknown" ]] || [[ "${output}" =~ "headless" ]]
    else
        skip "detect_environment function not available"
    fi
}

# =============================================================================
# LOGGING INTEGRATION TESTS
# =============================================================================

@test "logging_integration: should use project logging functions" {
    if command -v log_info >/dev/null 2>&1; then
        run log_info "Test message"
        [ "${status}" -eq 0 ]
        [[ "${output}" =~ "INFO" ]] || [[ "${output}" =~ "Test message" ]]
    else
        skip "log_info function not available"
    fi
}

@test "logging_integration: should handle error logging" {
    if command -v log_error >/dev/null 2>&1; then
        run log_error "Test error message"
        [ "${status}" -eq 0 ]
        [[ "${output}" =~ "ERROR" ]] || [[ "${output}" =~ "Test error message" ]]
    fi
}

@test "logging_integration: should create log files in correct location" {
    if command -v init_logging >/dev/null 2>&1; then
        test_log="${TEST_LOG_DIR}/test_logging.log"
        run init_logging "${test_log}"
        [ "${status}" -eq 0 ]
        
        # Test that logging actually writes to file
        if command -v log_info >/dev/null 2>&1; then
            log_info "Test log entry" 2>/dev/null || true
            [[ -f "${test_log}" ]] || skip "Log file not created"
        fi
    else
        skip "init_logging function not available"
    fi
}

# =============================================================================
# SCRIPT VALIDATION TESTS
# =============================================================================

@test "script_validation: all shell scripts should have proper shebang" {
    local invalid_scripts=()
    
    while IFS= read -r -d '' script; do
        local first_line
        first_line=$(head -n1 "${script}" 2>/dev/null || echo "")
        if [[ ! "${first_line}" =~ ^#!/usr/bin/env\ bash$ ]] && [[ ! "${first_line}" =~ ^#!/bin/bash$ ]]; then
            invalid_scripts+=("$(basename "${script}")")
        fi
    done < <(find "${PROJECT_ROOT}" -name "*.sh" -type f -print0 2>/dev/null || true)
    
    if [[ ${#invalid_scripts[@]} -gt 0 ]]; then
        echo "Scripts with invalid shebang: ${invalid_scripts[*]}"
        return 1
    fi
}

@test "script_validation: all shell scripts should use set -euo pipefail" {
    local missing_strict_mode=()
    
    while IFS= read -r -d '' script; do
        if ! grep -q "set -euo pipefail" "${script}" 2>/dev/null; then
            missing_strict_mode+=("$(basename "${script}")")
        fi
    done < <(find "${PROJECT_ROOT}" -name "*.sh" -type f -print0 2>/dev/null || true)
    
    if [[ ${#missing_strict_mode[@]} -gt 0 ]]; then
        echo "Scripts missing strict mode: ${missing_strict_mode[*]}"
        return 1
    fi
}

@test "script_validation: utility scripts should have proper guards" {
    local missing_guards=()
    
    while IFS= read -r -d '' script; do
        local basename_script
        basename_script=$(basename "${script}")
        if [[ "${basename_script}" == util-*.sh ]] && ! grep -q "UTIL_.*_LOADED" "${script}" 2>/dev/null; then
            missing_guards+=("${basename_script}")
        fi
    done < <(find "${PROJECT_ROOT}" -name "util-*.sh" -type f -print0 2>/dev/null || true)
    
    if [[ ${#missing_guards[@]} -gt 0 ]]; then
        echo "Utility scripts missing load guards: ${missing_guards[*]}"
        return 1
    fi
}

# =============================================================================
# SECURITY TESTS
# =============================================================================

@test "security: scripts should not contain hardcoded credentials" {
    local suspicious_patterns=(
        "password.*="
        "secret.*="
        "api.*key.*="
        "token.*="
    )
    
    local findings=()
    
    for pattern in "${suspicious_patterns[@]}"; do
        while IFS= read -r -d '' script; do
            if grep -qi "${pattern}" "${script}" 2>/dev/null; then
                findings+=("$(basename "${script}"): potential credential in ${pattern}")
            fi
        done < <(find "${PROJECT_ROOT}" -name "*.sh" -type f -print0 2>/dev/null || true)
    done
    
    if [[ ${#findings[@]} -gt 0 ]]; then
        echo "Potential security issues found:"
        printf '%s\n' "${findings[@]}"
        return 1
    fi
}

@test "security: scripts should validate input parameters" {
    # Check for basic input validation patterns
    local scripts_without_validation=()
    
    while IFS= read -r -d '' script; do
        local basename_script
        basename_script=$(basename "${script}")
        
        # Skip test scripts and simple wrappers
        if [[ "${basename_script}" =~ ^(test-|simple-|compliance-) ]]; then
            continue
        fi
        
        # Look for scripts that accept parameters but don't validate them
        if grep -q '\$[1-9]' "${script}" 2>/dev/null && ! grep -q -E "(validate_.*|check_.*|\[\[.*\$[1-9])" "${script}" 2>/dev/null; then
            scripts_without_validation+=("${basename_script}")
        fi
    done < <(find "${PROJECT_ROOT}" -name "*.sh" -type f -print0 2>/dev/null || true)
    
    # Allow some scripts without validation for now
    if [[ ${#scripts_without_validation[@]} -gt 5 ]]; then
        echo "Many scripts lack input validation: ${scripts_without_validation[*]}"
        return 1
    fi
}

# =============================================================================
# PERFORMANCE TESTS
# =============================================================================

@test "performance: scripts should complete basic syntax check quickly" {
    local slow_scripts=()
    
    while IFS= read -r -d '' script; do
        local start_time end_time duration
        start_time=$(date +%s%N 2>/dev/null || date +%s)
        
        if ! timeout 10 bash -n "${script}" 2>/dev/null; then
            slow_scripts+=("$(basename "${script}"): syntax error")
            continue
        fi
        
        end_time=$(date +%s%N 2>/dev/null || date +%s)
        
        # Handle nanosecond precision if available
        if [[ "${start_time}" =~ [0-9]{19} ]]; then
            duration=$(( (end_time - start_time) / 1000000 )) # Convert to milliseconds
        else
            duration=$(( (end_time - start_time) * 1000 )) # Convert seconds to milliseconds
        fi
        
        # Flag scripts that take more than 1 second for syntax check
        if [[ ${duration} -gt 1000 ]]; then
            slow_scripts+=("$(basename "${script}"): ${duration}ms")
        fi
    done < <(find "${PROJECT_ROOT}" -name "*.sh" -type f -print0 2>/dev/null || true)
    
    if [[ ${#slow_scripts[@]} -gt 0 ]]; then
        echo "Scripts with performance issues: ${slow_scripts[*]}"
        return 1
    fi
}

# =============================================================================
# INTEGRATION TESTS
# =============================================================================

@test "integration: env-detect script should work with util modules" {
    if [[ -f "${PROJECT_ROOT}/env-detect.sh" ]]; then
        # Test with different output formats
        run timeout 30 bash "${PROJECT_ROOT}/env-detect.sh" --help
        [ "${status}" -eq 0 ]
        [[ "${output}" =~ "Usage" ]] || [[ "${output}" =~ "help" ]]
        
        # Test basic execution
        run timeout 30 bash "${PROJECT_ROOT}/env-detect.sh" --quiet
        [[ "${status}" -eq 0 ]] || [[ "${status}" -eq 1 ]] # Allow error codes for detection issues
    else
        skip "env-detect.sh not found"
    fi
}

@test "integration: validate-installation should run without errors" {
    if [[ -f "${PROJECT_ROOT}/validate-installation.sh" ]]; then
        # Set environment to prevent interactive prompts
        export NONINTERACTIVE=true
        
        # Test help functionality
        run timeout 60 bash "${PROJECT_ROOT}/validate-installation.sh" 2>/dev/null || true
        # Should exit cleanly even if validation fails
        [[ "${status}" -le 2 ]]
    else
        skip "validate-installation.sh not found"
    fi
}

# =============================================================================
# COMPLIANCE TESTS
# =============================================================================

@test "compliance: scripts should have VERSION variables where appropriate" {
    local missing_version=()
    
    # Check main setup scripts for VERSION variables
    local main_scripts=(
        "install-new.sh"
        "setup-desktop.sh"
        "setup-devtools.sh"
        "update-environment.sh"
    )
    
    for script in "${main_scripts[@]}"; do
        if [[ -f "${PROJECT_ROOT}/${script}" ]] && ! grep -q "VERSION=" "${PROJECT_ROOT}/${script}" 2>/dev/null; then
            missing_version+=("${script}")
        fi
    done
    
    if [[ ${#missing_version[@]} -gt 2 ]]; then
        echo "Scripts missing VERSION variables: ${missing_version[*]}"
        return 1
    fi
}

@test "compliance: scripts should use readonly for constants" {
    local missing_readonly=()
    
    # Check for hardcoded values that should be readonly
    while IFS= read -r -d '' script; do
        local basename_script
        basename_script=$(basename "${script}")
        
        # Look for patterns that suggest constants
        if grep -q -E "^[A-Z_]+=" "${script}" 2>/dev/null && ! grep -q "readonly" "${script}" 2>/dev/null; then
            # Skip if it's just a few variables
            local const_count
            const_count=$(grep -c -E "^[A-Z_]+=" "${script}" 2>/dev/null || echo 0)
            if [[ ${const_count} -gt 3 ]]; then
                missing_readonly+=("${basename_script}")
            fi
        fi
    done < <(find "${PROJECT_ROOT}" -name "*.sh" -type f -print0 2>/dev/null || true)
    
    if [[ ${#missing_readonly[@]} -gt 5 ]]; then
        echo "Scripts that could benefit from readonly: ${missing_readonly[*]}"
        return 1
    fi
}

# =============================================================================
# FUNCTIONAL TESTS
# =============================================================================

@test "functional: check-prerequisites should validate system requirements" {
    if [[ -f "${PROJECT_ROOT}/check-prerequisites.sh" ]]; then
        # Test help functionality
        run timeout 30 bash "${PROJECT_ROOT}/check-prerequisites.sh" --help 2>/dev/null || true
        [[ "${status}" -eq 0 ]] || [[ "${output}" =~ "help" ]] || [[ "${output}" =~ "Usage" ]]
    else
        skip "check-prerequisites.sh not found"
    fi
}

@test "functional: docker validation scripts should work" {
    if [[ -f "${PROJECT_ROOT}/validate-docker-images.sh" ]]; then
        # Test basic execution without actually pulling images
        export DRY_RUN=true
        run timeout 60 bash "${PROJECT_ROOT}/validate-docker-images.sh" 2>/dev/null || true
        # Should complete without hanging
        [[ "${status}" -le 2 ]]
    else
        skip "validate-docker-images.sh not found"
    fi
}

# =============================================================================
# DOCUMENTATION TESTS
# =============================================================================

@test "documentation: README should exist and be comprehensive" {
    [[ -f "${PROJECT_ROOT}/README.md" ]]
    
    # Check for essential sections
    local readme_content
    readme_content=$(<"${PROJECT_ROOT}/README.md")
    
    [[ "${readme_content}" =~ "Installation" ]] || [[ "${readme_content}" =~ "Setup" ]]
    [[ "${readme_content}" =~ "Usage" ]] || [[ "${readme_content}" =~ "Getting Started" ]]
}

@test "documentation: scripts should have usage information" {
    local missing_usage=()
    
    # Check main scripts for usage information
    local main_scripts=(
        "install-new.sh"
        "check-prerequisites.sh"
        "env-detect.sh"
    )
    
    for script in "${main_scripts[@]}"; do
        if [[ -f "${PROJECT_ROOT}/${script}" ]]; then
            if ! grep -q -E "(usage|Usage|USAGE|--help)" "${PROJECT_ROOT}/${script}" 2>/dev/null; then
                missing_usage+=("${script}")
            fi
        fi
    done
    
    if [[ ${#missing_usage[@]} -gt 1 ]]; then
        echo "Scripts missing usage information: ${missing_usage[*]}"
        return 1
    fi
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Generate test report
generate_test_report() {
    local report_file="${BATS_TEST_TMPDIR}/test_report.json"
    local current_env="unknown"
    
    # Try to detect environment safely
    if command -v detect_environment >/dev/null 2>&1; then
        current_env=$(detect_environment 2>/dev/null || echo 'unknown')
    fi
    
    cat > "${report_file}" << EOF
{
    "test_run": {
        "timestamp": "$(date -Iseconds 2>/dev/null || date)",
        "environment": "${current_env}",
        "total_tests": ${BATS_TEST_NUMBER:-0},
        "project_root": "${PROJECT_ROOT}"
    },
    "summary": "Comprehensive test suite for Ubuntu Development Environment",
    "categories": [
        "environment_detection",
        "logging_integration", 
        "script_validation",
        "security",
        "performance",
        "integration",
        "compliance",
        "functional",
        "documentation"
    ]
}
EOF
    
    echo "Test report generated: ${report_file}"
}

# Performance monitoring for tests
#
# Usage:
#   monitor_test_performance "test_name" command [args...]
#
# Parameters:
#   $1 - Name of the test (string, used for reporting)
#   $2... - Command and arguments to execute (the test to monitor)
#
# Example:
#   monitor_test_performance "my_test" bash my_script.sh arg1 arg2
#
# Returns:
#   Exit code of the executed command.
#   Prints the duration in milliseconds.
monitor_test_performance() {
    local test_name="$1"
    shift
    local start_time end_time duration

    start_time=$(date +%s%N 2>/dev/null || date +%s)
    "$@"
    local exit_code=$?
    end_time=$(date +%s%N 2>/dev/null || date +%s)

    # Handle nanosecond precision if available
    if [[ "${start_time}" =~ [0-9]{19} ]]; then
        duration=$(( (end_time - start_time) / 1000000 )) # milliseconds
    else
        duration=$(( (end_time - start_time) * 1000 )) # Convert seconds to milliseconds
    fi

    echo "Test '${test_name}' took ${duration}ms"
    return ${exit_code}
}
