#!/usr/bin/env bash
# simple-compliance-check.sh - Quick compliance assessment
set -euo pipefail

echo "=== Codebase Compliance Review ==="
echo "Global Copilot Instructions Compliance Assessment"
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo

# Check for readonly usage
echo "1. Checking for readonly constants..."
echo "Scripts with readonly declarations:"
grep -c "readonly.*=" *.sh | while IFS=: read -r file count; do
    if [[ $count -gt 0 ]]; then
        echo "  ✓ $file: $count declarations"
    else
        echo "  ✗ $file: No readonly declarations"
    fi
done
echo

# Check for VERSION variables
echo "2. Checking for VERSION variables..."
echo "Scripts with VERSION variables:"
grep -c "VERSION=" *.sh | while IFS=: read -r file count; do
    if [[ $count -gt 0 ]]; then
        echo "  ✓ $file: Has VERSION"
    else
        echo "  ✗ $file: Missing VERSION"
    fi
done
echo

# Check for proper sourcing
echo "3. Checking source statements..."
echo "Top scripts using utility sourcing:"
grep -c "source.*util-" *.sh | head -5
echo

# Check for dry-run support
echo "4. Checking for dry-run support..."
echo "Scripts with dry-run capability:"
grep -c "DRY_RUN" *.sh | while IFS=: read -r file count; do
    if [[ $count -gt 0 ]]; then
        echo "  ✓ $file: $count DRY_RUN references"
    fi
done
total_dry_run=$(grep -l "DRY_RUN" *.sh | wc -l)
echo "  Total scripts with dry-run: $total_dry_run"
echo

# Check for macOS detection
echo "5. Checking for macOS detection..."
echo "Scripts with cross-platform detection:"
if grep -l "uname.*-s\|darwin\|OS_TYPE" *.sh 2>/dev/null; then
    echo "  ✓ Found macOS detection"
else
    echo "  ✗ No macOS detection found - scripts may not work on macOS"
fi
echo

# Check for mktemp usage
echo "6. Checking for secure temp file creation..."
echo "Scripts using mktemp:"
grep -l "mktemp" *.sh | while read -r file; do
    count=$(grep -c "mktemp" "$file")
    echo "  ✓ $file: $count mktemp usage(s)"
done
echo

# Check shellcheck compliance
echo "7. Scripts with shellcheck directives..."
echo "Shellcheck-aware scripts:"
if shellcheck_files=$(grep -l "shellcheck" *.sh 2>/dev/null); then
    echo "$shellcheck_files" | while read -r file; do
        echo "  ✓ $file"
    done
else
    echo "  ✗ No shellcheck directives found"
fi
echo

# Advanced compliance checks
echo "8. Error handling compliance..."
echo "Scripts with proper error handling:"
scripts_with_set_e=$(grep -l "set -euo pipefail" *.sh | wc -l)
scripts_with_trap=$(grep -l "trap.*EXIT\|trap.*ERR" *.sh | wc -l)
echo "  Scripts with 'set -euo pipefail': $scripts_with_set_e"
echo "  Scripts with cleanup traps: $scripts_with_trap"
echo

echo "9. Logging standardization..."
echo "Scripts using structured logging:"
scripts_with_logging=$(grep -l "log_info\|log_error\|log_success" *.sh | wc -l)
echo "  Scripts with structured logging: $scripts_with_logging"
echo

echo "=== Priority Improvement Recommendations ==="
echo
echo "HIGH PRIORITY:"
echo "1. Add readonly declarations to constants in ALL scripts"
echo "2. Add VERSION variables and timestamps to major scripts"
echo "3. Implement error-checked sourcing (source ... || exit 1)"
echo "4. Add dry-run support to destructive operations"
echo
echo "MEDIUM PRIORITY:"
echo "5. Add macOS detection (OS_TYPE=\$(uname -s)) to utility scripts"
echo "6. Replace temporary file creation with mktemp"
echo "7. Add shellcheck directives to all scripts"
echo
echo "LOW PRIORITY:"
echo "8. Standardize log format across all scripts"
echo "9. Add comprehensive error recovery mechanisms"
echo "10. Implement resource cleanup with trap handlers"
echo

echo "=== Scripts Requiring Immediate Attention ==="
echo "Target files for compliance improvements:"

# Priority order for improvements
priority_scripts=(
    "env-detect.sh"
    "install-new.sh"
    "setup-desktop.sh"
    "setup-devcontainers.sh"
    "setup-devtools.sh"
    "setup-lang-sdks.sh"
    "setup-npm.sh"
    "setup-vscommunity.sh"
    "update-environment.sh"
    "update-homebrew.sh"
    "util-install.sh"
    "util-deps.sh"
    "util-wsl.sh"
    "validate-installation.sh"
    "validate-docker-desktop.sh"
)

for script in "${priority_scripts[@]}"; do
    if [[ -f "$script" ]]; then
        readonly_count=$(grep -c "readonly.*=" "$script" 2>/dev/null || echo 0)
        version_count=$(grep -c "VERSION=" "$script" 2>/dev/null || echo 0)
        dryrun_count=$(grep -c "DRY_RUN" "$script" 2>/dev/null || echo 0)

        status=""
        if [[ $readonly_count -eq 0 ]]; then status+="[NO-READONLY] "; fi
        if [[ $version_count -eq 0 ]]; then status+="[NO-VERSION] "; fi
        if [[ $dryrun_count -eq 0 ]]; then status+="[NO-DRYRUN] "; fi

        echo "  $script $status"
    fi
done

echo
echo "=== Compliance Score ==="
total_scripts=27
compliant_scripts=0

# Calculate rough compliance score
for script in *.sh; do
    [[ "$script" == "simple-compliance-check.sh" ]] && continue
    [[ "$script" == "improve-codebase-compliance.sh" ]] && continue

    score=0
    if grep -q "readonly.*=" "$script" 2>/dev/null; then ((score++)); fi
    if grep -q "VERSION=" "$script" 2>/dev/null; then ((score++)); fi
    if grep -q "set -euo pipefail" "$script" 2>/dev/null; then ((score++)); fi
    if grep -q "source.*util-" "$script" 2>/dev/null; then ((score++)); fi

    if [[ $score -ge 3 ]]; then
        ((compliant_scripts++))
    fi
done

compliance_percentage=$((compliant_scripts * 100 / total_scripts))
echo "Overall Compliance: $compliance_percentage% ($compliant_scripts/$total_scripts scripts)"

if [[ $compliance_percentage -lt 50 ]]; then
    echo "Status: 🔴 CRITICAL - Immediate action required"
elif [[ $compliance_percentage -lt 75 ]]; then
    echo "Status: 🟡 MODERATE - Significant improvements needed"
else
    echo "Status: 🟢 GOOD - Minor improvements needed"
fi
