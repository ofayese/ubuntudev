#!/usr/bin/env bash
# demo-progress.sh - Demonstration of progress indicators
set -euo pipefail

# Source utility modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-log.sh"

# Initialize logging
init_logging

log_info "Starting progress indicator demonstration"

# Demonstrate spinner
echo "Demonstrating spinner for indeterminate progress:"
start_spinner "Processing large dataset"
sleep 3
stop_spinner "Processing large dataset"

echo ""

# Demonstrate progress bar
echo "Demonstrating progress bar for determinate progress:"
total_items=20

for ((i=1; i<=total_items; i++)); do
  show_progress "$i" "$total_items" "Data Processing"
  sleep 0.2
done

echo ""

# Demonstrate step-by-step progress
echo "Demonstrating step-by-step progress tracking:"

declare -a DEMO_STEPS=(
  "initializing"
  "downloading"
  "extracting" 
  "installing"
  "configuring"
  "finalizing"
)

current_step=0
total_steps=${#DEMO_STEPS[@]}

for step in "${DEMO_STEPS[@]}"; do
  ((current_step++))
  log_info "[$current_step/$total_steps] Step: $step"
  show_progress "$current_step" "$total_steps" "Demo Installation"
  
  start_spinner "Executing $step"
  sleep 1
  stop_spinner "Executing $step"
done

# Show completion summary
show_completion_summary "PROGRESS DEMONSTRATION" "12 seconds"

finish_logging
