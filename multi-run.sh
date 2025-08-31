#!/bin/bash

# Multi-runner script for running multiple Claude instances on the same task
# Each runner gets its own git worktree and branch

MULTI_CONFIG_FILE="${1:-multi-runner-config.json}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Global variables for signal handling
BACKGROUND_PIDS=()
CLEANUP_DONE=false

# Signal handler for graceful exit
cleanup_and_exit() {
    if [ "$CLEANUP_DONE" = true ]; then
        return
    fi
    CLEANUP_DONE=true
    
    echo ""
    echo "========================================="
    echo "Received interrupt signal. Cleaning up..."
    echo "========================================="
    
    # Kill all background processes
    for pid in "${BACKGROUND_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "Killing background process: $pid"
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
    
    echo "Cleanup completed. Exiting."
    exit 130
}

# Set up signal traps
trap cleanup_and_exit SIGINT SIGTERM

# Interruptible sleep function
interruptible_sleep() {
    local duration="$1"
    local elapsed=0
    
    while [ $elapsed -lt $duration ]; do
        sleep 1
        elapsed=$((elapsed + 1))
        # Check if we received a signal
        if [ "$CLEANUP_DONE" = true ]; then
            return 1
        fi
    done
}

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    command -v jq >/dev/null 2>&1 || missing_deps+=("jq")
    command -v git >/dev/null 2>&1 || missing_deps+=("git")
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "ERROR: Missing required dependencies: ${missing_deps[*]}"
        echo "Please install missing dependencies and try again."
        exit 1
    fi
    
    # Get git project path from config (required parameter)
    local git_project_path=$(jq -r '.git_project_path // empty' "$MULTI_CONFIG_FILE")
    
    # Validate that git_project_path is provided
    if [ -z "$git_project_path" ] || [ "$git_project_path" = "null" ]; then
        echo "ERROR: git_project_path is required in configuration file"
        echo "Please specify the path to your git project in the config file."
        exit 1
    fi
    
    # Check if git project directory exists
    if [ ! -d "$git_project_path" ]; then
        echo "ERROR: Git project directory not found: $git_project_path"
        echo "Please ensure the git project exists at the specified path."
        exit 1
    fi
    
    # Check if it's a git repository
    if ! (cd "$git_project_path" && git rev-parse --git-dir >/dev/null 2>&1); then
        echo "ERROR: Directory is not a git repository: $git_project_path"
        echo "Please initialize git in the project directory first."
        exit 1
    fi
    
    echo "Using git project at: $git_project_path"
}

# Generate random ID for unnamed runners
generate_random_id() {
    local length=6
    tr -dc 'a-z0-9' < /dev/urandom | head -c "$length"
}

# Create git worktree and branch for a runner
create_runner_worktree() {
    local task_name="$1"
    local runner_name="$2"
    local worktree_path="$3"
    local branch_name="${task_name}/${runner_name}"
    local base_branch=$(jq -r '.git_base_branch // "main"' "$MULTI_CONFIG_FILE")
    local git_project_path=$(jq -r '.git_project_path // empty' "$MULTI_CONFIG_FILE")
    
    # Convert to absolute path if relative
    if [[ ! "$git_project_path" = /* ]]; then
        git_project_path="$(cd "$git_project_path" 2>/dev/null && pwd)" || git_project_path="$(realpath "$git_project_path")"
    fi
    
    # Convert worktree path to absolute path if relative
    if [[ ! "$worktree_path" = /* ]]; then
        # Create parent directory first if it doesn't exist for realpath to work
        local parent_dir="$(dirname "$worktree_path")"
        mkdir -p "$parent_dir" 2>/dev/null || true
        worktree_path="$(realpath "$worktree_path" 2>/dev/null)" || {
            # If realpath fails, construct absolute path manually
            worktree_path="$(pwd)/$worktree_path"
        }
    fi
    
    echo "Creating worktree for runner: $runner_name"
    echo "  Branch: $branch_name"
    echo "  Path: $worktree_path"
    echo "  Git project: $git_project_path"
    
    # Change to git project directory for git operations
    cd "$git_project_path" || {
        echo "ERROR: Failed to cd into git project: $git_project_path"
        exit 1
    }

    # Checkout base branch
    git checkout "$base_branch" 2>/dev/null || {
        echo "ERROR: Could not checkout base branch $base_branch"
        exit 1
    }
    
    # Create worktree directory and add worktree using absolute path
    mkdir -p "$(dirname "$worktree_path")"

    echo "pwd: $(pwd)"
    
    # Check if worktree already exists and clean up any conflicts
    if git worktree list | grep -q "$branch_name"; then
        echo "Warning: Worktree for branch $branch_name already exists, removing it first..."
        COMMAND="git worktree remove --force $(git worktree list | grep "$branch_name" | awk '{print $1}')"
        echo "COMMAND: $COMMAND"
        $COMMAND
    fi
    
    # Remove any existing directory at worktree path
    if [ -d "$worktree_path" ]; then
        echo "Removing existing directory at $worktree_path"
        rm -rf "$worktree_path"
    fi
    
    # Create worktree directory and add worktree
    mkdir -p "$(dirname "$worktree_path")"

    # Delete branch if it exists
    if git show-ref --quiet refs/heads/"$branch_name"; then
        echo "Deleting branch $branch_name"
        git branch -D "$branch_name"
    fi

    # Create new branch as it should not exist
    COMMAND="git worktree add $worktree_path -b $branch_name"
    echo "COMMAND: $COMMAND"
    $COMMAND || {
        echo "ERROR: Failed to create worktree at $worktree_path"
        exit 1
    }
    
    # Note: Using --allowedTools flag instead of copying .claude/settings.json
    # due to CLI parsing bug with parentheses in tool permissions
    
    # Switch back to original branch
    git checkout "$base_branch" 2>/dev/null || {
        echo "Warning: Could not switch back to base branch $base_branch"
    }
    
    # Return to script directory
    cd "$SCRIPT_DIR"
}

# Create runner configuration by merging common prompts with runner-specific settings
create_runner_config() {
    local task_index="$1"
    local task_name="$2"
    local runner_name="$3"
    local runner_index="$4"
    local runner_config_path="$5"
    
    echo "Creating runner config: $runner_config_path"
    
    # Create config from inline common prompts + runner modifications
    create_inline_runner_config "$task_index" "$task_name" "$runner_name" "$runner_index" "$runner_config_path"
}

# Create runner config from inline common prompts
create_inline_runner_config() {
    local task_index="$1"
    local task_name="$2"
    local runner_name="$3"
    local runner_index="$4"
    local runner_config_path="$5"

    local append_to_all
    append_to_all=$(jq -r ".runners[$runner_index].prompt_modifications.append_to_all // \"\"" "$MULTI_CONFIG_FILE")
    local append_to_initial
    append_to_initial=$(jq -r ".runners[$runner_index].prompt_modifications.append_to_initial // \"\"" "$MULTI_CONFIG_FILE")
    local append_to_loop
    append_to_loop=$(jq -r ".runners[$runner_index].prompt_modifications.append_to_loop // \"\"" "$MULTI_CONFIG_FILE")
    local append_to_final
    append_to_final=$(jq -r ".runners[$runner_index].prompt_modifications.append_to_final // \"\"" "$MULTI_CONFIG_FILE")

    jq \
      --arg runner_index "$runner_index" \
      --arg runner_name "$runner_name" \
      --arg append_to_all "$append_to_all" \
      --arg append_to_initial "$append_to_initial" \
      --arg append_to_loop "$append_to_loop" \
      --arg append_to_final "$append_to_final" '
      def safe_prompts($arr; $suffix):
        ($arr // [])
        | map(
            . as $p
            | ($p.prompt // "") as $base
            | $p + { prompt: ($base + ($append_to_all // "") + ($suffix // "")) }
          );

      {
        config: {
          retry_attempts: 5,
          retry_delay: 3600,
          log_file: ("logs/" + $runner_name + "-log.log"),
          error_file: ("logs/" + $runner_name + "-error.log")
        },
        max_loops: (.max_loops // 10),
        initial_prompts:
          ( safe_prompts(.initial_prompts; $append_to_initial)
            + (.runners[$runner_index|tonumber].extra_prompts.initial_prompts // []) ),
        loop_prompts:
          ( safe_prompts(.loop_prompts; $append_to_loop)
            + (.runners[$runner_index|tonumber].extra_prompts.loop_prompts // []) ),
        exit_conditions:
          ( (.exit_conditions // []) + (.runners[$runner_index|tonumber].extra_prompts.exit_conditions // []) ),
        end_prompts:
          ( safe_prompts(.end_prompts; $append_to_final)
            + (.runners[$runner_index|tonumber].extra_prompts.end_prompts // []) )
      }
      ' "$MULTI_CONFIG_FILE" > "$runner_config_path" || {
        echo "ERROR: Failed to generate $runner_config_path from $MULTI_CONFIG_FILE"
        exit 1
      }
}



# Define allowed tools (without parentheses due to CLI parsing bug)
GET_ALLOWED_TOOLS() {
    echo "Read,Edit,Write,MultiEdit,NotebookEdit,Bash,TodoWrite,Glob,Grep,Task,WebFetch,WebSearch,ExitPlanMode,BashOutput,KillBash"
}

# Auto-commit changes after Claude execution (external git operations)
auto_commit_changes() {
    local runner_name="$1"
    local iteration="$2"
    local worktree_path="$3"
    local runner_config="$4"
    local claude_output="$5"
    local prompt_type="$6"
    local original_prompt="$7"
    
    # Auto-commit is always enabled
    
    cd "$worktree_path" || return 1
    
    # Check if there are any files to add, or changes to commit
    if git status --porcelain | grep -q '^[^ ]' || ! git diff --quiet || ! git diff --cached --quiet; then
        # There ARE changes - proceed with commit
        git add .
        # Use entire Claude output as commit message
        local claude_commit_msg=""
        if [ -n "$claude_output" ]; then
            claude_commit_msg="$claude_output"
        fi
        
        # Generate comprehensive commit message
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local commit_msg="[$prompt_type] $runner_name: $claude_commit_msg

Prompt: $original_prompt
Runner: $runner_name
Iteration: $iteration
Type: $prompt_type
Timestamp: $timestamp"
        
        # Commit changes with descriptive message
        git commit -m "$commit_msg"
        
        echo "Auto-committed changes for $runner_name ($prompt_type): $claude_commit_msg"
    else
        echo "No files to add, or changes to commit for $runner_name (iteration $iteration)"
        return 0
    fi
}

# Clean git commands from prompts to avoid Claude failures
clean_git_commands_from_prompt() {
    local prompt="$1"
    # Remove common git write commands that Claude can't execute
    echo "$prompt" | sed 's/git add[^;]*[;]*//g' | sed 's/git commit[^;]*[;]*//g' | sed 's/git push[^;]*[;]*//g'
}

# Claude execution with retry logic and auto-commit
run_claude_with_retry() {
    local prompt="$1"
    local runner_config="$2"
    local runner_name="$3"
    local iteration="$4"
    local worktree_path="$5"
    local prompt_type="$6"
    
    local max_attempts=5
    local retry_delay=3600
    local log_file=$(jq -r '.log_file // "logs/log.log"' "$runner_config")
    local allowed_tools=$(GET_ALLOWED_TOOLS)
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo "--------------------------------" >> "$log_file"
        echo "Attempt $attempt: Running claude command..."
        echo "Command: $prompt"
        echo "$prompt" >> "$log_file"
        
        local output
        local exit_code
        
        # Clean git commands from prompt and add commit message request
        local clean_prompt=$(clean_git_commands_from_prompt "$prompt")
        local enhanced_prompt="$clean_prompt\n\nReturn a simple string describing changes made for git commit."
        output=$(claude --allowedTools "$allowed_tools" -p "$enhanced_prompt" 2>&1)
        exit_code=$?
        
        # Auto-commit changes if command succeeded
        if [ $exit_code -eq 0 ] && [ -n "$worktree_path" ]; then
            auto_commit_changes "$runner_name" "$iteration" "$worktree_path" "$runner_config" "$output" "$prompt_type" "$prompt"
        fi
        
        # Check if output contains "limit reached"
        if echo "$output" | grep -q "limit reached"; then
            echo "Limit reached detected. Waiting $retry_delay seconds before retry..."
            interruptible_sleep "$retry_delay"
            attempt=$((attempt + 1))
        else
            echo "Command completed successfully!"
            echo "$output"
            echo "$output" >> "$log_file"
            return $exit_code
        fi
    done
    
    echo "Maximum attempts reached. Exiting..."
    return 1
}

# Execute prompts from config (integrated logic from run.sh)
execute_runner_config() {
    local runner_config="$1"
    local runner_name="$2"
    local worktree_path="$3"
    
    echo "Executing runner config: $runner_config"
    
    # Run initial prompts
    local initial_count=$(jq -r '(.initial_prompts // []) | length' "$runner_config")
    for ((i=0; i<initial_count; i++)); do
        local name=$(jq -r ".initial_prompts[$i].name" "$runner_config")
        local prompt=$(jq -r ".initial_prompts[$i].prompt" "$runner_config")
        local skip_condition=$(jq -r ".initial_prompts[$i].skip_condition // null" "$runner_config")
        
        if [ "$skip_condition" != "null" ] && [ -n "$skip_condition" ]; then
            if eval "$skip_condition"; then
                echo "Skipping initial prompt '$name' due to condition: $skip_condition"
                continue
            fi
        fi
        
        echo "Running initial prompt: $name"
        if ! run_claude_with_retry "$prompt" "$runner_config" "$runner_name" "initial_$i" "$worktree_path" "initial"; then
            echo "Failed to complete initial prompt '$name'. Exiting runner."
            return 1
        fi
    done
    
    # Special handling for npm install if package.json exists
    if [ -f package.json ]; then
        echo "Installing dependencies with npm."
        npm install
    fi
    
    # Main loop
    local COUNT=0
    local loop_count=$(jq -r '(.loop_prompts // []) | length' "$runner_config")
    
    # Skip main loop if there are no loop prompts
    if [ "$loop_count" -eq 0 ]; then
        echo "No loop prompts defined. Skipping main loop and proceeding to end prompts."
        run_end_prompts "$runner_config" "$runner_name" "$worktree_path"
        return 0
    fi
    
    local max_loops=$(jq -r '.max_loops // 10' "$runner_config")
    # Ensure max_loops is a valid integer
    if ! [[ "$max_loops" =~ ^[0-9]+$ ]]; then
        max_loops=10
    fi
    while [ $COUNT -lt $max_loops ]; do
        echo "Iteration $COUNT"
        
        # Check exit conditions first
        local exit_conditions_count=$(jq -r '(.exit_conditions // []) | length' "$runner_config")
        for ((i=0; i<exit_conditions_count; i++)); do
            local file=$(jq -r ".exit_conditions[$i].file" "$runner_config")
            local name=$(jq -r ".exit_conditions[$i].name" "$runner_config")
            
            if [ -f "$file" ]; then
                echo "Exit condition triggered: $name"
                run_end_prompts "$runner_config" "$runner_name" "$worktree_path"
                return 0
            fi
        done
        
        # Run loop prompts based on their period
        for ((i=0; i<loop_count; i++)); do
            local name=$(jq -r ".loop_prompts[$i].name" "$runner_config")
            local prompt=$(jq -r ".loop_prompts[$i].prompt" "$runner_config")
            local period=$(jq -r ".loop_prompts[$i].period // 1" "$runner_config")
            
            # Handle null or empty period
            if [ "$period" = "null" ] || [ -z "$period" ] || ! [[ "$period" =~ ^[0-9]+$ ]]; then
                period=1
            fi
            
            # Check if this prompt should run on this iteration
            if [ $((COUNT % period)) -eq 0 ]; then
                echo "Running loop prompt: $name (period: $period)"
                if ! run_claude_with_retry "$prompt" "$runner_config" "$runner_name" "loop_${COUNT}_${i}" "$worktree_path" "loop"; then
                    echo "Failed to complete loop prompt '$name'. Exiting runner."
                    return 1
                fi
            fi
        done
        
        COUNT=$((COUNT + 1))
    done
}

# Run end prompts
run_end_prompts() {
    local runner_config="$1"
    local runner_name="$2"
    local worktree_path="$3"
    
    local end_count=$(jq -r '(.end_prompts // []) | length' "$runner_config")
    for ((i=0; i<end_count; i++)); do
        local name=$(jq -r ".end_prompts[$i].name" "$runner_config")
        local prompt=$(jq -r ".end_prompts[$i].prompt" "$runner_config")
        
        echo "Running end prompt: $name"
        run_claude_with_retry "$prompt" "$runner_config" "$runner_name" "end_$i" "$worktree_path" "final"
    done
}

# Run a single task runner
run_task_runner() {
    local task_name="$1"
    local runner_name="$2"
    local worktree_path="$3"
    local runner_config="$4"
    local timeout="$5"
    
    echo "========================================="
    echo "Starting runner: $runner_name"
    echo "Worktree: $worktree_path"
    echo "Config: $runner_config"
    echo "========================================="
    
    cd "$worktree_path" || {
        echo "ERROR: Failed to cd into worktree: $worktree_path"
        return 1
    }
    
    # Create logs directory for logs
    mkdir -p logs || {
        echo "ERROR: Failed to create logs directory"
        return 1
    }
    
    # Copy runner config to worktree
    cp "$SCRIPT_DIR/$runner_config" ./ || {
        echo "ERROR: Failed to copy runner config to worktree"
        return 1
    }
    
    # Execute the runner config directly (no dependency on run.sh)
    if [ "$timeout" -gt 0 ]; then
        timeout "$timeout" bash -c "$(declare -f execute_runner_config run_claude_with_retry run_end_prompts auto_commit_changes clean_git_commands_from_prompt GET_ALLOWED_TOOLS); execute_runner_config '$runner_config' '$runner_name' '$worktree_path'" || {
            local exit_code=$?
            if [ $exit_code -eq 124 ]; then
                echo "Runner $runner_name timed out after $timeout seconds"
            else
                echo "Runner $runner_name failed with exit code: $exit_code"
            fi
            return $exit_code
        }
    else
        execute_runner_config "$runner_config" "$runner_name" "$worktree_path" || {
            echo "Runner $runner_name failed with exit code: $?"
            return $?
        }
    fi
    
    echo "Runner $runner_name completed successfully"
    cd "$SCRIPT_DIR"
}

# Run task with multiple runners
run_task() {
    local task_name=$(jq -r ".task_name // \"untitled_task\"" "$MULTI_CONFIG_FILE")
    local description=$(jq -r ".task_description // \"No description provided\"" "$MULTI_CONFIG_FILE")
    local runner_count=$(jq -r "(.runners // []) | length" "$MULTI_CONFIG_FILE")
    local execution_mode=$(jq -r ".execution_mode // \"sequential\"" "$MULTI_CONFIG_FILE")
    local worktree_base_path_config=$(jq -r ".worktree_base_path // \"worktrees\"" "$MULTI_CONFIG_FILE")
    local git_project_path=$(jq -r '.git_project_path // empty' "$MULTI_CONFIG_FILE")
    local timeout=3600
    
    # Calculate worktree base path based on git project location
    local worktree_base_path
    if [[ "$worktree_base_path_config" = /* ]]; then
        # Absolute path provided
        worktree_base_path="$worktree_base_path_config"
    else
        # Relative path - create parallel to git project
        if [[ "$git_project_path" = /* ]]; then
            # Git project is absolute, create worktrees parallel to it
            local git_parent_dir="$(dirname "$git_project_path")"
            local git_project_name="$(basename "$git_project_path")"
            worktree_base_path="${git_parent_dir}/${git_project_name}-${worktree_base_path_config}"
        else
            # Git project is relative, use relative worktree path
            worktree_base_path="$worktree_base_path_config"
        fi
    fi
    
    echo "========================================="
    echo "MULTI-RUNNER TASK: $task_name"
    echo "Description: $description"
    echo "Runners: $runner_count"
    echo "Mode: $execution_mode"
    echo "Git project: $git_project_path"
    echo "Worktrees base: $worktree_base_path"
    echo "========================================="
    
    # Create runners array with names and instructions
    local runners=()
    local runner_configs=()
    
    for ((i=0; i<runner_count; i++)); do
        local runner_name=$(jq -r ".runners[$i].name // empty" "$MULTI_CONFIG_FILE")
        local extra_instructions=$(jq -r ".runners[$i].extra_instructions // \"\"" "$MULTI_CONFIG_FILE")
        
        # Generate random name if not provided
        if [ -z "$runner_name" ]; then
            runner_name="runner_$(generate_random_id)"
        fi
        
        local worktree_path="${worktree_base_path}/${task_name}_${runner_name}"
        local runner_config_name="${runner_name}-config.json"
        
        # Convert worktree path to absolute path if relative
        if [[ ! "$worktree_path" = /* ]]; then
            # Create parent directory first if it doesn't exist for realpath to work
            local parent_dir="$(dirname "$worktree_path")"
            mkdir -p "$parent_dir" 2>/dev/null || true
            worktree_path="$(realpath "$worktree_path" 2>/dev/null)" || {
                # If realpath fails, construct absolute path manually
                worktree_path="$(pwd)/$worktree_path"
            }
        fi
        
        # Create worktree and branch
        create_runner_worktree "$task_name" "$runner_name" "$worktree_path"
        
        # Create runner-specific config
        create_runner_config "0" "$task_name" "$runner_name" "$i" "$runner_config_name"
        
        runners+=("$runner_name:$worktree_path:$runner_config_name")
    done
    
    # Execute runners based on execution mode
    if [ "$execution_mode" = "parallel" ]; then
        echo "Running $runner_count runners in parallel..."
        local pids=()
        
        for runner_info in "${runners[@]}"; do
            IFS=':' read -r runner_name worktree_path runner_config <<< "$runner_info"
            run_task_runner "$task_name" "$runner_name" "$worktree_path" "$runner_config" "$timeout" &
            local pid=$!
            pids+=($pid)
            BACKGROUND_PIDS+=($pid)
        done
        
        # Wait for all runners to complete
        echo "Waiting for all runners to complete..."
        for pid in "${pids[@]}"; do
            if ! wait "$pid" 2>/dev/null; then
                echo "Runner with PID $pid failed or was interrupted"
            fi
        done
        
        # Remove completed PIDs from BACKGROUND_PIDS
        for completed_pid in "${pids[@]}"; do
            BACKGROUND_PIDS=($(printf '%s\n' "${BACKGROUND_PIDS[@]}" | grep -v "^${completed_pid}$"))
        done
    else
        echo "Running $runner_count runners sequentially..."
        for runner_info in "${runners[@]}"; do
            IFS=':' read -r runner_name worktree_path runner_config <<< "$runner_info"
            run_task_runner "$task_name" "$runner_name" "$worktree_path" "$runner_config" "$timeout"
        done
    fi
    
    echo "All runners completed for task: $task_name"
}

# Main execution
main() {
    echo "Multi-Runner Claude Script"
    echo "=========================="
    
    check_dependencies
    
    if [ ! -f "$MULTI_CONFIG_FILE" ]; then
        echo "ERROR: Multi-runner config file not found: $MULTI_CONFIG_FILE"
        exit 1
    fi
    
    # Check if task_name exists
    if ! jq -e '.task_name' "$MULTI_CONFIG_FILE" >/dev/null 2>&1; then
        echo "No task_name found in configuration"
        exit 1
    fi
    
    # Check if runners exist
    local runner_count=$(jq -r '(.runners // []) | length' "$MULTI_CONFIG_FILE")
    if [ "$runner_count" -eq 0 ]; then
        echo "No runners found in configuration"
        exit 1
    fi
    
    echo "Found task with $runner_count runner(s)"
    
    run_task
    
    echo "========================================="
    echo "Task completed with all runners!"
    echo "========================================="
}

# Run main function
main "$@"