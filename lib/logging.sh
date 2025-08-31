#!/bin/bash

# Logging utilities library
# Provides consistent logging functions and formatting

# Colors for terminal output
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_RESET='\033[0m'

# Log levels
readonly LOG_ERROR=1
readonly LOG_WARN=2
readonly LOG_INFO=3
readonly LOG_DEBUG=4

# Current log level (can be overridden)
LOG_LEVEL=${LOG_LEVEL:-$LOG_INFO}

# Print colored message
print_color() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${COLOR_RESET}"
}

# Log error message
log_error() {
    local message="$1"
    if [ $LOG_LEVEL -ge $LOG_ERROR ]; then
        print_color "$COLOR_RED" "ERROR: $message" >&2
    fi
}

# Log warning message
log_warn() {
    local message="$1"
    if [ $LOG_LEVEL -ge $LOG_WARN ]; then
        print_color "$COLOR_YELLOW" "WARNING: $message"
    fi
}

# Log info message
log_info() {
    local message="$1"
    if [ $LOG_LEVEL -ge $LOG_INFO ]; then
        echo "$message"
    fi
}

# Log debug message
log_debug() {
    local message="$1"
    if [ $LOG_LEVEL -ge $LOG_DEBUG ]; then
        print_color "$COLOR_BLUE" "DEBUG: $message"
    fi
}

# Log success message
log_success() {
    local message="$1"
    print_color "$COLOR_GREEN" "✓ $message"
}

# Print separator line
print_separator() {
    local char="${1:-=}"
    local width="${2:-40}"
    printf '%*s\n' "$width" '' | tr ' ' "$char"
}

# Print header
print_header() {
    local title="$1"
    local width="${2:-40}"
    
    print_separator "=" "$width"
    echo "$title"
    print_separator "=" "$width"
}

# Print section
print_section() {
    local title="$1"
    echo ""
    print_separator "-" 40
    echo "$title"
    print_separator "-" 40
}

# Log to file
log_to_file() {
    local log_file="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] $message" >> "$log_file"
}

# Create log entry with metadata
create_log_entry() {
    local level="$1"
    local component="$2"
    local message="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] [$component] $message"
}

# Initialize logging
init_logging() {
    local log_dir="${1:-logs}"
    local log_file="${2:-multi-run.log}"
    
    # Create logs directory if it doesn't exist
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir" || {
            log_error "Failed to create log directory: $log_dir"
            return 1
        }
    fi
    
    # Create main log file
    local full_log_path="$log_dir/$log_file"
    touch "$full_log_path" || {
        log_error "Failed to create log file: $full_log_path"
        return 1
    }
    
    echo "$full_log_path"
}

# Log runner status
log_runner_status() {
    local runner_name="$1"
    local status="$2"
    local details="${3:-}"
    
    case "$status" in
        "starting")
            log_info "🚀 Starting runner: $runner_name"
            ;;
        "completed")
            log_success "Runner completed: $runner_name"
            ;;
        "failed")
            log_error "Runner failed: $runner_name"
            [ -n "$details" ] && log_error "  Details: $details"
            ;;
        "timeout")
            log_warn "Runner timed out: $runner_name"
            ;;
        *)
            log_info "Runner $runner_name: $status"
            ;;
    esac
}

# Log task status
log_task_status() {
    local task_name="$1"
    local status="$2"
    
    case "$status" in
        "starting")
            print_header "STARTING TASK: $task_name"
            ;;
        "completed")
            print_header "TASK COMPLETED: $task_name"
            ;;
        "failed")
            print_header "TASK FAILED: $task_name"
            ;;
        *)
            log_info "Task $task_name: $status"
            ;;
    esac
}

# Progress indicator
show_progress() {
    local current="$1"
    local total="$2"
    local label="${3:-Progress}"
    
    local percent=$((current * 100 / total))
    echo "$label: $current/$total ($percent%)"
}

# Spinner for long operations
start_spinner() {
    local pid=$1
    local message="${2:-Processing...}"
    local spinstr='|/-\'
    
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c] %s" "$spinstr" "$message"
        spinstr=$temp${spinstr%"$temp"}
        sleep 0.1
        printf "\r"
    done
    printf "    %s\n" "$message"
}

# Format duration
format_duration() {
    local seconds="$1"
    local hours=$((seconds / 3600))
    local minutes=$(( (seconds % 3600) / 60 ))
    local secs=$((seconds % 60))
    
    if [ $hours -gt 0 ]; then
        printf "%dh %dm %ds" $hours $minutes $secs
    elif [ $minutes -gt 0 ]; then
        printf "%dm %ds" $minutes $secs
    else
        printf "%ds" $secs
    fi
}

# Log execution time
log_execution_time() {
    local start_time="$1"
    local end_time="$2"
    local label="${3:-Execution time}"
    
    local duration=$((end_time - start_time))
    local formatted=$(format_duration "$duration")
    
    log_info "$label: $formatted"
}