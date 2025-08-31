#!/bin/bash

# Multi-runner script for running multiple Claude instances on the same task
# Each runner gets its own git worktree and branch

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load libraries
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/path-utils.sh"
source "$SCRIPT_DIR/lib/git-ops.sh"
source "$SCRIPT_DIR/lib/runner-exec.sh"

# Configuration file
MULTI_CONFIG_FILE="${1:-multi-runner-config.json}"

# Handle relative config paths
if [[ ! "$MULTI_CONFIG_FILE" = /* ]]; then
    # If file exists in current directory, use it
    if [ -f "$MULTI_CONFIG_FILE" ]; then
        MULTI_CONFIG_FILE="$(pwd)/$MULTI_CONFIG_FILE"
    # Otherwise check if it's in the script directory
    elif [ -f "$SCRIPT_DIR/$MULTI_CONFIG_FILE" ]; then
        MULTI_CONFIG_FILE="$SCRIPT_DIR/$MULTI_CONFIG_FILE"
    fi
fi

# Global variables for signal handling
BACKGROUND_PIDS=()
CLEANUP_DONE=false

# Signal handler for graceful exit
cleanup_and_exit() {
    if [ "$CLEANUP_DONE" = true ]; then
        return
    fi
    CLEANUP_DONE=true
    
    print_section "Received interrupt signal. Cleaning up..."
    
    # Kill all background processes
    for pid in "${BACKGROUND_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            log_info "Killing background process: $pid"
            kill -TERM "$pid" 2>/dev/null
            sleep 1
            if kill -0 "$pid" 2>/dev/null; then
                kill -KILL "$pid" 2>/dev/null
            fi
        fi
    done
    
    # Wait for processes to clean up
    for pid in "${BACKGROUND_PIDS[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    
    log_info "Cleanup completed. Exiting."
    exit 130
}

# Set up signal traps
trap cleanup_and_exit SIGINT SIGTERM

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    command -v jq >/dev/null 2>&1 || missing_deps+=("jq")
    command -v git >/dev/null 2>&1 || missing_deps+=("git")
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_error "Please install missing dependencies and try again."
        exit 1
    fi
    
    log_success "All dependencies found"
}

# Prepare runner
prepare_runner() {
    local task_name="$1"
    local runner_name="$2"
    local runner_index="$3"
    local worktree_base_path="$4"
    local git_project_path="$5"
    local base_branch="$6"
    
    # Get worktree path for this runner
    local worktree_path=$(get_runner_worktree_path "$worktree_base_path" "$task_name" "$runner_name")
    
    # Resolve to absolute path
    worktree_path=$(resolve_worktree_path "$worktree_path")
    
    # Create worktree and branch
    create_runner_worktree "$git_project_path" "$task_name" "$runner_name" "$worktree_path" "$base_branch" || {
        log_error "Failed to create worktree for runner: $runner_name"
        return 1
    }
    
    echo "$worktree_path"
}

# Run single task runner
run_task_runner() {
    local config_file="$1"
    local task_name="$2"
    local runner_name="$3"
    local runner_index="$4"
    local worktree_path="$5"
    local timeout="${6:-0}"
    
    log_runner_status "$runner_name" "starting"
    log_info "  Worktree: $worktree_path"
    log_info "  Runner Index: $runner_index"
    
    # Copy config file to worktree
    cp "$config_file" "$worktree_path/" || {
        log_error "Failed to copy config to worktree"
        return 1
    }
    
    local config_basename=$(basename "$config_file")
    local start_time=$(date +%s)
    
    # Execute runner
    if [ "$timeout" -gt 0 ]; then
        timeout "$timeout" bash -c "
            cd '$worktree_path' || exit 1
            source '$SCRIPT_DIR/lib/logging.sh'
            source '$SCRIPT_DIR/lib/config.sh'
            source '$SCRIPT_DIR/lib/git-ops.sh'
            source '$SCRIPT_DIR/lib/runner-exec.sh'
            execute_runner '$config_basename' '$runner_index' '$runner_name' '$worktree_path'
        " || {
            local exit_code=$?
            if [ $exit_code -eq 124 ]; then
                log_runner_status "$runner_name" "timeout"
            else
                log_runner_status "$runner_name" "failed" "exit code: $exit_code"
            fi
            return $exit_code
        }
    else
        (
            cd "$worktree_path" || exit 1
            execute_runner "$config_basename" "$runner_index" "$runner_name" "$worktree_path"
        ) || {
            log_runner_status "$runner_name" "failed" "exit code: $?"
            return $?
        }
    fi
    
    local end_time=$(date +%s)
    log_runner_status "$runner_name" "completed"
    log_execution_time "$start_time" "$end_time" "Runner $runner_name execution time"
    
    return 0
}

# Run task with multiple runners
run_task() {
    local config_file="$1"
    
    # Load configuration
    local task_name=$(get_task_name "$config_file")
    local description=$(get_task_description "$config_file")
    local runner_count=$(get_runner_count "$config_file")
    local execution_mode=$(get_execution_mode "$config_file")
    local git_project_path=$(get_git_project_path "$config_file")
    local git_base_branch=$(get_git_base_branch "$config_file")
    local worktree_base_config=$(get_worktree_base_path "$config_file")
    local timeout=3600
    
    # Ensure runner_count is a valid integer
    if [ -z "$runner_count" ] || ! [[ "$runner_count" =~ ^[0-9]+$ ]]; then
        runner_count=0
    fi
    
    # Calculate worktree base path
    local worktree_base_path=$(calculate_worktree_path "$git_project_path" "$worktree_base_config" "$SCRIPT_DIR")
    
    print_header "MULTI-RUNNER TASK: $task_name"
    log_info "Description: $description"
    log_info "Runners: $runner_count"
    log_info "Mode: $execution_mode"
    log_info "Git project: $git_project_path"
    log_info "Worktrees base: $worktree_base_path"
    
    # Prepare runners
    local runners=()
    
    # Handle case with no runners defined
    if [ "$runner_count" -eq 0 ]; then
        log_info "No runners defined - using default runner"
        runner_count=1
        runners+=("default:0")
    else
        # Collect runner information
        for ((i=0; i<runner_count; i++)); do
            local runner_name=$(get_runner_name "$config_file" "$i")
            
            # Generate name if not provided
            if [ -z "$runner_name" ]; then
                runner_name="runner_$(generate_random_id)"
            fi
            
            runners+=("$runner_name:$i")
        done
    fi
    
    # Prepare all runners first
    local prepared_runners=()
    for runner_info in "${runners[@]}"; do
        IFS=':' read -r runner_name runner_index <<< "$runner_info"
        
        log_info "Preparing runner: $runner_name"
        local worktree_path=$(prepare_runner "$task_name" "$runner_name" "$runner_index" \
                                            "$worktree_base_path" "$git_project_path" "$git_base_branch")
        
        if [ -z "$worktree_path" ]; then
            log_error "Failed to prepare runner: $runner_name"
            continue
        fi
        
        prepared_runners+=("$runner_name:$runner_index:$worktree_path")
    done
    
    # Execute runners based on execution mode
    if [ "$execution_mode" = "parallel" ]; then
        log_info "Running ${#prepared_runners[@]} runners in parallel..."
        local pids=()
        
        for runner_info in "${prepared_runners[@]}"; do
            IFS=':' read -r runner_name runner_index worktree_path <<< "$runner_info"
            
            run_task_runner "$config_file" "$task_name" "$runner_name" "$runner_index" "$worktree_path" "$timeout" &
            local pid=$!
            pids+=($pid)
            BACKGROUND_PIDS+=($pid)
        done
        
        # Wait for all runners
        log_info "Waiting for all runners to complete..."
        for pid in "${pids[@]}"; do
            if ! wait "$pid" 2>/dev/null; then
                log_warn "Runner with PID $pid failed or was interrupted"
            fi
        done
        
        # Clean up completed PIDs
        for completed_pid in "${pids[@]}"; do
            BACKGROUND_PIDS=($(printf '%s\n' "${BACKGROUND_PIDS[@]}" | grep -v "^${completed_pid}$" || true))
        done
    else
        log_info "Running ${#prepared_runners[@]} runners sequentially..."
        
        for runner_info in "${prepared_runners[@]}"; do
            IFS=':' read -r runner_name runner_index worktree_path <<< "$runner_info"
            
            run_task_runner "$config_file" "$task_name" "$runner_name" "$runner_index" "$worktree_path" "$timeout"
        done
    fi
    
    log_task_status "$task_name" "completed"
}

# Main function
main() {
    local start_time=$(date +%s)
    
    print_header "Multi-Runner Claude Script"
    
    # Check dependencies
    check_dependencies
    
    # Load and validate configuration
    if [ ! -f "$MULTI_CONFIG_FILE" ]; then
        log_error "Configuration file not found: $MULTI_CONFIG_FILE"
        exit 1
    fi
    
    # Load config
    MULTI_CONFIG_FILE=$(load_config "$MULTI_CONFIG_FILE") || exit 1
    
    # Validate configuration
    validate_config "$MULTI_CONFIG_FILE" || exit 1
    
    # Validate paths
    local git_project_path=$(get_git_project_path "$MULTI_CONFIG_FILE")
    local worktree_base_path=$(get_worktree_base_path "$MULTI_CONFIG_FILE")
    validate_paths "$SCRIPT_DIR" "$git_project_path" "$worktree_base_path" || exit 1
    
    # Setup git repository
    local git_base_branch=$(get_git_base_branch "$MULTI_CONFIG_FILE")
    setup_git_repository "$git_project_path" "$git_base_branch" || exit 1
    
    # Ensure task name exists
    local task_name=$(ensure_task_name "$MULTI_CONFIG_FILE")
    
    # Create temporary config if we generated a task name
    if [ "$task_name" != "$(get_task_name "$MULTI_CONFIG_FILE")" ]; then
        local temp_config=$(mktemp)
        jq ". + {task_name: \"$task_name\"}" "$MULTI_CONFIG_FILE" > "$temp_config"
        MULTI_CONFIG_FILE="$temp_config"
    fi
    
    # Initialize logging
    local main_log=$(init_logging "logs" "multi-run.log")
    log_info "Logging to: $main_log"
    
    # Run the task
    run_task "$MULTI_CONFIG_FILE"
    
    # Calculate total execution time
    local end_time=$(date +%s)
    log_execution_time "$start_time" "$end_time" "Total execution time"
    
    print_header "All runners completed successfully!"
}

# Run main function
main "$@"