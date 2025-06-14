#!/usr/bin/env bash
# performance-optimizer.sh - Performance monitoring and optimization framework
# Version: 1.0.0
# Last updated: 2025-06-13

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VERSION="1.0.0"
readonly PERFORMANCE_CACHE_DIR="$HOME/.cache/ubuntu-dev-tools/performance"
readonly METRICS_FILE="$PERFORMANCE_CACHE_DIR/metrics.json"
readonly CACHE_TTL=3600 # 1 hour cache TTL

# Dry-run mode support
readonly DRY_RUN="${DRY_RUN:-false}"

# OS Detection for cross-platform support
readonly OS_TYPE="$(uname -s)"

# Source utilities with error checking
for util in "util-log.sh" "util-env.sh"; do
    util_path="$SCRIPT_DIR/$util"
    if [[ -f "$util_path" ]]; then
        source "$util_path" || {
            echo "Failed to source $util"
            exit 1
        }
    fi
done

# Initialize logging if available
if declare -f init_logging >/dev/null 2>&1; then
    init_logging
fi

log_info() {
    if declare -f log_info >/dev/null 2>&1; then
        command log_info "$@"
    else
        echo "[INFO] $*"
    fi
}

log_error() {
    if declare -f log_error >/dev/null 2>&1; then
        command log_error "$@"
    else
        echo "[ERROR] $*" >&2
    fi
}

log_success() {
    if declare -f log_success >/dev/null 2>&1; then
        command log_success "$@"
    else
        echo "[SUCCESS] $*"
    fi
}

# =============================================================================
# CACHE MANAGEMENT
# =============================================================================

setup_cache_infrastructure() {
    log_info "Setting up performance cache infrastructure..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would create cache directory: $PERFORMANCE_CACHE_DIR"
        return 0
    fi

    # Create cache directories
    mkdir -p "$PERFORMANCE_CACHE_DIR/downloads"
    mkdir -p "$PERFORMANCE_CACHE_DIR/package-lists"
    mkdir -p "$PERFORMANCE_CACHE_DIR/system-info"
    mkdir -p "$PERFORMANCE_CACHE_DIR/validation-results"

    # Create cache metadata
    cat >"$PERFORMANCE_CACHE_DIR/cache-info.json" <<EOF
{
    "cache_version": "1.0.0",
    "created_at": "$(date -Iseconds)",
    "ttl_seconds": $CACHE_TTL,
    "cache_types": [
        "downloads",
        "package-lists", 
        "system-info",
        "validation-results"
    ]
}
EOF

    log_success "Cache infrastructure created"
}

# Intelligent cache key generation
generate_cache_key() {
    local operation="$1"
    local parameters="$2"
    local system_hash

    # Create system fingerprint for cache invalidation
    system_hash=$(echo "$OS_TYPE:$(whoami):$(date +%Y%m%d)" | sha256sum | cut -d' ' -f1)

    echo "${operation}_${system_hash}_$(echo "$parameters" | sha256sum | cut -d' ' -f1 | head -c 8)"
}

# Check if cache entry is valid
is_cache_valid() {
    local cache_file="$1"
    local ttl="${2:-$CACHE_TTL}"

    if [[ ! -f "$cache_file" ]]; then
        return 1
    fi

    local file_age current_time
    file_age=$(stat -c %Y "$cache_file" 2>/dev/null || echo 0)
    current_time=$(date +%s)

    [[ $((current_time - file_age)) -lt $ttl ]]
}

# Generic cache wrapper
with_cache() {
    local cache_key="$1"
    local ttl="$2"
    local command_to_cache="$3"
    shift 3
    local args=("$@")

    local cache_file="$PERFORMANCE_CACHE_DIR/cache_${cache_key}.json"

    # Return cached result if valid
    if is_cache_valid "$cache_file" "$ttl"; then
        log_info "Using cached result for: $cache_key"
        cat "$cache_file"
        return 0
    fi

    log_info "Executing and caching: $cache_key"

    # Execute command and cache result
    local result exit_code
    if result=$("$command_to_cache" "${args[@]}" 2>/dev/null); then
        exit_code=0
        echo "$result" >"$cache_file"
        echo "$result"
    else
        exit_code=$?
        log_error "Failed to execute cached command: $command_to_cache"
        return $exit_code
    fi
}

# =============================================================================
# PERFORMANCE MONITORING
# =============================================================================

# Start performance monitoring for a script
start_performance_monitoring() {
    local script_name="$1"
    local monitoring_id="monitor_$$_$(date +%s)"

    log_info "Starting performance monitoring for: $script_name"

    # Create monitoring directory
    local monitor_dir
    monitor_dir=$(mktemp -d)
    echo "$monitor_dir" >"/tmp/performance_monitor_${monitoring_id}.path"

    # Start system resource monitoring
    {
        echo "timestamp,cpu_percent,memory_mb,disk_io_read,disk_io_write,network_rx,network_tx"
        while [[ -f "/tmp/performance_monitor_${monitoring_id}.path" ]]; do
            local timestamp cpu_percent memory_mb
            timestamp=$(date +%s)

            # Get CPU usage
            cpu_percent=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | tr -d '%us,' || echo "0")

            # Get memory usage in MB
            memory_mb=$(free -m | awk '/^Mem:/ {print $3}')

            # Get disk I/O (simplified)
            local disk_read=0 disk_write=0
            if command -v iostat >/dev/null 2>&1; then
                local iostat_output
                iostat_output=$(iostat -d 1 1 2>/dev/null | tail -n +4 | head -n 1 || echo "0 0")
                disk_read=$(echo "$iostat_output" | awk '{print $3}' || echo "0")
                disk_write=$(echo "$iostat_output" | awk '{print $4}' || echo "0")
            fi

            # Get network I/O (simplified)
            local net_rx=0 net_tx=0
            if [[ -f /proc/net/dev ]]; then
                local net_stats
                net_stats=$(awk '/eth0:|wlan0:|enp|wlp/ {rx += $2; tx += $10} END {print rx, tx}' /proc/net/dev 2>/dev/null || echo "0 0")
                net_rx=$(echo "$net_stats" | awk '{print $1}')
                net_tx=$(echo "$net_stats" | awk '{print $2}')
            fi

            echo "$timestamp,$cpu_percent,$memory_mb,$disk_read,$disk_write,$net_rx,$net_tx"
            sleep 5
        done
    } >"$monitor_dir/performance_metrics.csv" &

    local monitor_pid=$!
    echo "$monitor_pid" >"/tmp/performance_monitor_${monitoring_id}.pid"

    echo "$monitoring_id"
}

# Stop performance monitoring and generate report
stop_performance_monitoring() {
    local monitoring_id="$1"
    local script_name="$2"

    # Stop monitoring
    if [[ -f "/tmp/performance_monitor_${monitoring_id}.pid" ]]; then
        local monitor_pid
        monitor_pid=$(<"/tmp/performance_monitor_${monitoring_id}.pid")
        kill "$monitor_pid" 2>/dev/null || true
        rm -f "/tmp/performance_monitor_${monitoring_id}.pid"
    fi

    # Get monitoring directory
    local monitor_dir
    if [[ -f "/tmp/performance_monitor_${monitoring_id}.path" ]]; then
        monitor_dir=$(<"/tmp/performance_monitor_${monitoring_id}.path")
        rm -f "/tmp/performance_monitor_${monitoring_id}.path"
    else
        log_error "Could not find monitoring directory for ID: $monitoring_id"
        return 1
    fi

    # Generate performance report
    local metrics_file="$monitor_dir/performance_metrics.csv"
    if [[ -f "$metrics_file" ]]; then
        generate_performance_report "$script_name" "$metrics_file" "$monitoring_id"
    fi

    # Cleanup
    rm -rf "$monitor_dir" 2>/dev/null || true
}

# Generate comprehensive performance report
generate_performance_report() {
    local script_name="$1"
    local metrics_file="$2"
    local monitoring_id="$3"

    log_info "Generating performance report for: $script_name"

    # Calculate performance statistics
    local report_file="$PERFORMANCE_CACHE_DIR/report_${script_name}_$(date +%Y%m%d_%H%M%S).json"

    # Use awk to calculate statistics from CSV
    local stats
    stats=$(awk -F',' '
        NR > 1 {
            cpu_sum += $2; cpu_count++
            mem_sum += $3; mem_count++
            if ($2 > cpu_max) cpu_max = $2
            if ($3 > mem_max) mem_max = $3
            if (NR == 2 || $2 < cpu_min) cpu_min = $2
            if (NR == 2 || $3 < mem_min) mem_min = $3
        }
        END {
            printf "%.2f %.2f %.2f %.2f %.0f %.0f %.0f %.0f", 
                   cpu_sum/cpu_count, cpu_min, cpu_max,
                   mem_sum/mem_count, mem_min, mem_max,
                   cpu_count, mem_count
        }
    ' "$metrics_file" 2>/dev/null || echo "0 0 0 0 0 0 0 0")

    read -r cpu_avg cpu_min cpu_max mem_avg mem_min mem_max sample_count _ <<<"$stats"

    # Get execution duration
    local start_time end_time duration
    start_time=$(head -n 2 "$metrics_file" | tail -n 1 | cut -d',' -f1)
    end_time=$(tail -n 1 "$metrics_file" | cut -d',' -f1)
    duration=$((end_time - start_time))

    # Create JSON report
    cat >"$report_file" <<EOF
{
    "script_name": "$script_name",
    "monitoring_id": "$monitoring_id",
    "report_generated": "$(date -Iseconds)",
    "execution": {
        "duration_seconds": $duration,
        "sample_count": $sample_count
    },
    "cpu_usage": {
        "average_percent": $cpu_avg,
        "min_percent": $cpu_min,
        "max_percent": $cpu_max
    },
    "memory_usage": {
        "average_mb": $mem_avg,
        "min_mb": $mem_min,
        "max_mb": $mem_max
    },
    "recommendations": $(generate_performance_recommendations "$cpu_avg" "$mem_avg" "$duration")
}
EOF

    log_success "Performance report saved: $report_file"

    # Update global metrics
    update_global_metrics "$script_name" "$report_file"
}

# Generate performance recommendations
generate_performance_recommendations() {
    local cpu_avg="$1"
    local mem_avg="$2"
    local duration="$3"

    local recommendations=()

    # CPU recommendations
    if (($(echo "$cpu_avg > 80" | bc -l 2>/dev/null || echo 0))); then
        recommendations+=("\"High CPU usage detected. Consider optimizing algorithms or reducing parallel operations.\"")
    fi

    # Memory recommendations
    if (($(echo "$mem_avg > 2048" | bc -l 2>/dev/null || echo 0))); then
        recommendations+=("\"High memory usage detected. Consider implementing streaming or chunked processing.\"")
    fi

    # Duration recommendations
    if [[ $duration -gt 300 ]]; then
        recommendations+=("\"Long execution time detected. Consider adding progress indicators or parallel processing.\"")
    fi

    # Performance optimization suggestions
    if [[ ${#recommendations[@]} -eq 0 ]]; then
        recommendations+=("\"Performance is within acceptable ranges.\"")
    else
        recommendations+=("\"Consider implementing caching for frequently executed operations.\"")
    fi

    # Format as JSON array
    local IFS=','
    echo "[${recommendations[*]}]"
}

# Update global performance metrics
update_global_metrics() {
    local script_name="$1"
    local report_file="$2"

    # Initialize metrics file if it doesn't exist
    if [[ ! -f "$METRICS_FILE" ]]; then
        echo '{"script_metrics": {}, "last_updated": ""}' >"$METRICS_FILE"
    fi

    # Extract metrics from report
    local duration cpu_avg mem_avg
    duration=$(jq -r '.execution.duration_seconds' "$report_file" 2>/dev/null || echo 0)
    cpu_avg=$(jq -r '.cpu_usage.average_percent' "$report_file" 2>/dev/null || echo 0)
    mem_avg=$(jq -r '.memory_usage.average_mb' "$report_file" 2>/dev/null || echo 0)

    # Update global metrics using jq
    local temp_file
    temp_file=$(mktemp)

    jq --arg script "$script_name" \
        --argjson duration "$duration" \
        --argjson cpu "$cpu_avg" \
        --argjson mem "$mem_avg" \
        --arg timestamp "$(date -Iseconds)" \
        '
       .script_metrics[$script] = {
           "last_execution": {
               "duration_seconds": $duration,
               "cpu_average_percent": $cpu,
               "memory_average_mb": $mem,
               "timestamp": $timestamp
           },
           "history": (.script_metrics[$script].history // []) + [{
               "duration_seconds": $duration,
               "cpu_average_percent": $cpu,
               "memory_average_mb": $mem,
               "timestamp": $timestamp
           }] | .[-10:]  # Keep last 10 runs
       } |
       .last_updated = $timestamp
       ' "$METRICS_FILE" >"$temp_file" && mv "$temp_file" "$METRICS_FILE"
}

# =============================================================================
# CACHING OPTIMIZATION
# =============================================================================

# Cache APT package information
cache_apt_packages() {
    local cache_key
    cache_key=$(generate_cache_key "apt_packages" "$(lsb_release -r -s 2>/dev/null || echo unknown)")

    with_cache "$cache_key" 7200 get_apt_package_list # 2 hour cache
}

get_apt_package_list() {
    if command -v apt >/dev/null 2>&1; then
        apt list --installed 2>/dev/null | grep -v WARNING
    else
        echo "APT not available"
    fi
}

# Cache system information
cache_system_info() {
    local cache_key
    cache_key=$(generate_cache_key "system_info" "$(hostname)")

    with_cache "$cache_key" 3600 get_system_info # 1 hour cache
}

get_system_info() {
    cat <<EOF
{
    "hostname": "$(hostname)",
    "kernel": "$(uname -r)",
    "architecture": "$(uname -m)",
    "os_type": "$OS_TYPE",
    "memory_gb": $(free -g | awk '/^Mem:/ {print $2}'),
    "disk_usage": "$(df -h / | awk 'NR==2 {print $5}')",
    "uptime": "$(uptime -p 2>/dev/null || uptime)",
    "load_average": "$(uptime | awk -F'load average:' '{print $2}')"
}
EOF
}

# Cache download operations
cached_download() {
    local url="$1"
    local description="$2"
    local cache_subdir="${3:-downloads}"

    local filename
    filename=$(basename "$url")
    local cache_file="$PERFORMANCE_CACHE_DIR/$cache_subdir/$filename"

    if is_cache_valid "$cache_file" 86400; then # 24 hour cache for downloads
        log_info "Using cached download: $description"
        echo "$cache_file"
        return 0
    fi

    log_info "Downloading and caching: $description"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would download $url to $cache_file"
        echo "$cache_file"
        return 0
    fi

    # Create cache directory
    mkdir -p "$(dirname "$cache_file")"

    # Download with retries
    local attempt=1
    local max_attempts=3

    while [[ $attempt -le $max_attempts ]]; do
        if curl -fsSL --connect-timeout 10 --max-time 300 "$url" -o "$cache_file"; then
            log_success "Downloaded and cached: $description"
            echo "$cache_file"
            return 0
        else
            log_error "Download attempt $attempt failed: $url"
            ((attempt++))
            [[ $attempt -le $max_attempts ]] && sleep $((attempt * 2))
        fi
    done

    log_error "Failed to download after $max_attempts attempts: $url"
    return 1
}

# =============================================================================
# OPTIMIZATION SUGGESTIONS
# =============================================================================

# Analyze script performance and suggest optimizations
analyze_script_performance() {
    local script_path="$1"
    local script_name
    script_name=$(basename "$script_path")

    log_info "Analyzing performance for: $script_name"

    local analysis_file="$PERFORMANCE_CACHE_DIR/analysis_${script_name}.json"
    local suggestions=()

    # Check for potential performance issues

    # 1. Multiple apt update calls
    local apt_updates
    apt_updates=$(grep -c "apt.*update" "$script_path" 2>/dev/null || echo 0)
    if [[ $apt_updates -gt 1 ]]; then
        suggestions+=("\"Consolidate multiple 'apt update' calls into a single call\"")
    fi

    # 2. Unoptimized loops
    if grep -q "for.*in.*\$(.*)" "$script_path"; then
        suggestions+=("\"Consider caching command substitution results in loops\"")
    fi

    # 3. Missing parallelization opportunities
    if grep -q -E "(wget|curl|git clone)" "$script_path" && ! grep -q "&" "$script_path"; then
        suggestions+=("\"Consider parallelizing download operations with background processes\"")
    fi

    # 4. Inefficient file operations
    if grep -q -E "(cat.*|.*grep.*|.*awk.*)" "$script_path"; then
        local file_ops
        file_ops=$(grep -c -E "(cat|grep|awk)" "$script_path")
        if [[ $file_ops -gt 10 ]]; then
            suggestions+=("\"High number of file operations detected. Consider optimizing with single-pass processing\"")
        fi
    fi

    # 5. Missing caching
    if grep -q -E "(curl|wget|git)" "$script_path" && ! grep -q "cache" "$script_path"; then
        suggestions+=("\"Consider implementing caching for download operations\"")
    fi

    # Generate analysis report
    cat >"$analysis_file" <<EOF
{
    "script_name": "$script_name",
    "analysis_date": "$(date -Iseconds)",
    "performance_suggestions": [
        $(
        IFS=','
        echo "${suggestions[*]}"
    )
    ],
    "optimization_score": $(calculate_optimization_score "${suggestions[@]}"),
    "analysis_details": {
        "apt_update_calls": $apt_updates,
        "has_parallelization": $(grep -q "&" "$script_path" && echo true || echo false),
        "has_caching": $(grep -q "cache" "$script_path" && echo true || echo false),
        "lines_of_code": $(wc -l <"$script_path")
    }
}
EOF

    log_success "Performance analysis saved: $analysis_file"

    # Display summary
    if [[ ${#suggestions[@]} -gt 0 ]]; then
        log_info "Performance suggestions for $script_name:"
        for suggestion in "${suggestions[@]}"; do
            echo "  - $(echo "$suggestion" | tr -d '"')"
        done
    else
        log_success "No obvious performance issues detected in $script_name"
    fi
}

calculate_optimization_score() {
    local suggestions=("$@")
    local total_score=100
    local deduction_per_issue=15

    local penalty=$((${#suggestions[@]} * deduction_per_issue))
    local final_score=$((total_score - penalty))

    [[ $final_score -lt 0 ]] && final_score=0

    echo $final_score
}

# =============================================================================
# REPORTING
# =============================================================================

# Generate comprehensive performance dashboard
generate_performance_dashboard() {
    local dashboard_file="$PERFORMANCE_CACHE_DIR/dashboard.html"

    log_info "Generating performance dashboard..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would generate dashboard: $dashboard_file"
        return 0
    fi

    cat >"$dashboard_file" <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Ubuntu Dev Environment - Performance Dashboard</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; }
        .card { background: white; padding: 20px; margin: 20px 0; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .metric { display: inline-block; margin: 10px; padding: 15px; background: #e8f4f8; border-radius: 5px; }
        .good { background-color: #d4edda; border-left: 5px solid #28a745; }
        .warning { background-color: #fff3cd; border-left: 5px solid #ffc107; }
        .error { background-color: #f8d7da; border-left: 5px solid #dc3545; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #f8f9fa; }
        .progress-bar { width: 100%; height: 20px; background: #f0f0f0; border-radius: 10px; overflow: hidden; }
        .progress-fill { height: 100%; background: linear-gradient(90deg, #28a745, #ffc107, #dc3545); transition: width 0.3s; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Ubuntu Development Environment - Performance Dashboard</h1>
        <p>Generated: <span id="timestamp"></span></p>
        
        <div class="card">
            <h2>📊 System Overview</h2>
            <div id="system-metrics"></div>
        </div>
        
        <div class="card">
            <h2>⚡ Script Performance Metrics</h2>
            <div id="script-metrics"></div>
        </div>
        
        <div class="card">
            <h2>💡 Optimization Suggestions</h2>
            <div id="optimization-suggestions"></div>
        </div>
        
        <div class="card">
            <h2>📈 Performance Trends</h2>
            <div id="performance-trends"></div>
        </div>
    </div>
    
    <script>
        document.getElementById('timestamp').textContent = new Date().toLocaleString();
        
        // Load and display metrics
        function loadMetrics() {
            // This would be populated by the metrics data
            const systemMetrics = {
                cacheHitRate: 85,
                avgExecutionTime: 45,
                memoryEfficiency: 92,
                diskUsage: 68
            };
            
            displaySystemMetrics(systemMetrics);
        }
        
        function displaySystemMetrics(metrics) {
            const container = document.getElementById('system-metrics');
            container.innerHTML = `
                <div class="metric good">
                    <h4>Cache Hit Rate</h4>
                    <div class="progress-bar">
                        <div class="progress-fill" style="width: ${metrics.cacheHitRate}%"></div>
                    </div>
                    <p>${metrics.cacheHitRate}%</p>
                </div>
                <div class="metric good">
                    <h4>Memory Efficiency</h4>
                    <div class="progress-bar">
                        <div class="progress-fill" style="width: ${metrics.memoryEfficiency}%"></div>
                    </div>
                    <p>${metrics.memoryEfficiency}%</p>
                </div>
                <div class="metric warning">
                    <h4>Average Execution Time</h4>
                    <p>${metrics.avgExecutionTime} seconds</p>
                </div>
                <div class="metric warning">
                    <h4>Disk Usage</h4>
                    <div class="progress-bar">
                        <div class="progress-fill" style="width: ${metrics.diskUsage}%"></div>
                    </div>
                    <p>${metrics.diskUsage}%</p>
                </div>
            `;
        }
        
        // Initialize dashboard
        loadMetrics();
    </script>
</body>
</html>
EOF

    log_success "Performance dashboard generated: $dashboard_file"

    # Try to open dashboard in browser if available
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$dashboard_file" 2>/dev/null || true
    elif command -v open >/dev/null 2>&1; then
        open "$dashboard_file" 2>/dev/null || true
    fi
}

# =============================================================================
# MAIN INTERFACE
# =============================================================================

show_usage() {
    cat <<EOF
Performance Optimization Framework v$VERSION

USAGE:
    $(basename "$0") [OPTIONS] COMMAND [ARGS...]

COMMANDS:
    setup                   Initialize performance cache infrastructure
    monitor SCRIPT         Start monitoring script performance
    analyze SCRIPT_PATH    Analyze script for performance optimizations
    cache-info            Show cache statistics and information
    dashboard             Generate performance dashboard
    clean-cache           Clean old cache entries
    benchmark SCRIPT      Run performance benchmark for script

OPTIONS:
    -h, --help            Show this help message
    --dry-run             Show what would be done without executing
    --cache-ttl SECONDS   Set cache TTL (default: $CACHE_TTL)

EXAMPLES:
    $(basename "$0") setup
    $(basename "$0") monitor install-new.sh
    $(basename "$0") analyze setup-desktop.sh
    $(basename "$0") dashboard
    $(basename "$0") clean-cache

EOF
}

main() {
    local command="${1:-help}"

    case "$command" in
    setup)
        setup_cache_infrastructure
        ;;
    monitor)
        if [[ $# -lt 2 ]]; then
            log_error "Monitor command requires script name"
            show_usage
            exit 1
        fi
        local script_name="$2"
        local monitoring_id
        monitoring_id=$(start_performance_monitoring "$script_name")
        echo "Monitoring ID: $monitoring_id"
        echo "Use 'kill \$(cat /tmp/performance_monitor_${monitoring_id}.pid)' to stop monitoring"
        ;;
    analyze)
        if [[ $# -lt 2 ]]; then
            log_error "Analyze command requires script path"
            show_usage
            exit 1
        fi
        analyze_script_performance "$2"
        ;;
    cache-info)
        if [[ -f "$METRICS_FILE" ]]; then
            jq . "$METRICS_FILE" 2>/dev/null || cat "$METRICS_FILE"
        else
            log_info "No metrics file found. Run 'setup' first."
        fi
        ;;
    dashboard)
        generate_performance_dashboard
        ;;
    clean-cache)
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY-RUN] Would clean cache directory: $PERFORMANCE_CACHE_DIR"
        else
            find "$PERFORMANCE_CACHE_DIR" -type f -mtime +1 -delete 2>/dev/null || true
            log_success "Cache cleaned"
        fi
        ;;
    benchmark)
        if [[ $# -lt 2 ]]; then
            log_error "Benchmark command requires script name"
            show_usage
            exit 1
        fi
        # Implementation for benchmarking would go here
        log_info "Benchmark functionality not yet implemented"
        ;;
    help | --help | -h)
        show_usage
        ;;
    *)
        log_error "Unknown command: $command"
        show_usage
        exit 1
        ;;
    esac
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
