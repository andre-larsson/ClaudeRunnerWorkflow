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

# Validate paths to prevent nested git repositories
validate_paths() {
    local git_project_path="$1"
    local worktree_base_path_config=$(jq -r ".worktree_base_path // \"worktrees\"" "$MULTI_CONFIG_FILE")
    
    # Get absolute path of the script directory (multiclaude directory)
    local script_abs_path="$(realpath "$SCRIPT_DIR")"
    
    # Resolve git_project_path to absolute path using cd method for relative paths
    local git_project_abs_path
    if [[ "$git_project_path" = /* ]]; then
        # Already absolute
        git_project_abs_path="$git_project_path"
    else
        # Relative path - resolve properly using cd
        git_project_abs_path="$(cd "$SCRIPT_DIR" && realpath -m "$git_project_path")"
    fi
    
    # Calculate worktree base path (same logic as in run_task function)
    local worktree_base_path
    if [[ "$worktree_base_path_config" = /* ]]; then
        worktree_base_path="$worktree_base_path_config"
    else
        if [[ "$git_project_path" = /* ]]; then
            local git_parent_dir="$(dirname "$git_project_abs_path")"
            local git_project_name="$(basename "$git_project_abs_path")"
            worktree_base_path="${git_parent_dir}/${git_project_name}-${worktree_base_path_config}"
        else
            worktree_base_path="$(cd "$SCRIPT_DIR" && pwd)/$worktree_base_path_config"
        fi
    fi
    
    # Resolve worktree path to absolute path
    local worktree_abs_path
    if [[ "$worktree_base_path" = /* ]]; then
        # Already absolute
        worktree_abs_path="$(realpath -m "$worktree_base_path")"
    else
        # Relative path - resolve from script directory
        worktree_abs_path="$(cd "$SCRIPT_DIR" && realpath -m "$worktree_base_path")"
    fi
    
    # Check if git_project_path is inside script directory
    case "$git_project_abs_path/" in
        "$script_abs_path"/*)
            echo "ERROR: git_project_path cannot be inside the multiclaude directory"
            echo "git_project_path: $git_project_abs_path"
            echo "multiclaude directory: $script_abs_path" 
            echo "This would create nested git repositories and cause conflicts."
            echo "Please use a path outside the multiclaude directory (e.g., '../my-project')"
            exit 1
            ;;
    esac
    
    # Check if worktree_base_path is inside script directory
    case "$worktree_abs_path/" in
        "$script_abs_path"/*)
            echo "ERROR: worktree_base_path cannot be inside the multiclaude directory"
            echo "worktree_base_path: $worktree_abs_path"
            echo "multiclaude directory: $script_abs_path"
            echo "This would create git worktrees inside the multiclaude git repository."
            echo "Please use a path outside the multiclaude directory (e.g., '../worktrees')"
            exit 1
            ;;
    esac
    
    echo "✓ Path validation passed"
    echo "  Git project: $git_project_abs_path"
    echo "  Worktrees: $worktree_abs_path"
    echo "  Multiclaude: $script_abs_path"
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
    
    # Validate paths to prevent nested git repositories
    validate_paths "$git_project_path"
    
    # Get git base branch from config
    local git_base_branch=$(jq -r '.git_base_branch // "main"' "$MULTI_CONFIG_FILE")
    
    # Create git project directory if it doesn't exist
    if [ ! -d "$git_project_path" ]; then
        echo "Creating git project directory: $git_project_path"
        mkdir -p "$git_project_path" || {
            echo "ERROR: Failed to create directory: $git_project_path"
            exit 1
        }
    fi
    
    # Initialize git repository if it doesn't exist
    if ! (cd "$git_project_path" && git rev-parse --git-dir >/dev/null 2>&1); then
        echo "Initializing git repository: $git_project_path"
        (cd "$git_project_path" && git init) || {
            echo "ERROR: Failed to initialize git repository"
            exit 1
        }
    fi
    
    # Ensure there's at least one commit (needed for branching)
    if ! (cd "$git_project_path" && git rev-parse HEAD >/dev/null 2>&1); then
        echo "Creating initial commit in: $git_project_path"
        (cd "$git_project_path" && {
            echo "# Initial repository" > README.md
            git add README.md
            git commit -m "Initial commit"
        }) || {
            echo "ERROR: Failed to create initial commit"
            exit 1
        }
    fi
    
    # Ensure the base branch exists and is checked out
    (cd "$git_project_path" && {
        local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
        if [ "$current_branch" != "$git_base_branch" ]; then
            if git show-ref --quiet refs/heads/"$git_base_branch"; then
                echo "Checking out existing base branch: $git_base_branch"
                git checkout "$git_base_branch"
            else
                echo "Creating and checking out base branch: $git_base_branch"
                git checkout -b "$git_base_branch"
            fi
        fi
    }) || {
        echo "ERROR: Failed to ensure base branch exists: $git_base_branch"
        exit 1
    }
    
    echo "Using git project at: $git_project_path (branch: $git_base_branch)"
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

# Dynamic config helper function - generates runner config on-the-fly
get_runner_config() {
    local runner_index="$1"
    local runner_name="$2"
    local query="$3"
    
    local append_to_all
    append_to_all=$(jq -r ".runners[$runner_index].prompt_modifications.append_to_all // \"\"" "$MULTI_CONFIG_FILE")
    local append_to_initial
    append_to_initial=$(jq -r ".runners[$runner_index].prompt_modifications.append_to_initial // \"\"" "$MULTI_CONFIG_FILE")
    local append_to_loop
    append_to_loop=$(jq -r ".runners[$runner_index].prompt_modifications.append_to_loop // \"\"" "$MULTI_CONFIG_FILE")
    local append_to_final
    append_to_final=$(jq -r ".runners[$runner_index].prompt_modifications.append_to_final // \"\"" "$MULTI_CONFIG_FILE")

    jq -r \
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
        loop_break_condition:
          ( .loop_break_condition // (.runners[$runner_index|tonumber].extra_prompts.loop_break_condition // null) ),
        end_prompts:
          ( safe_prompts(.end_prompts; $append_to_final)
            + (.runners[$runner_index|tonumber].extra_prompts.end_prompts // []) )
      } | '"$query"'
      ' "$MULTI_CONFIG_FILE"
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
    local runner_index="$4"
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
    local runner_index="$2"
    local runner_name="$3"
    local iteration="$4"
    local worktree_path="$5"
    local prompt_type="$6"
    
    local max_attempts=5
    local retry_delay=3600
    local log_file=$(get_runner_config "$runner_index" "$runner_name" '.config.log_file // "logs/log.log"')
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
            auto_commit_changes "$runner_name" "$iteration" "$worktree_path" "$runner_index" "$output" "$prompt_type" "$prompt"
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
    local runner_index="$1"
    local runner_name="$2"
    local worktree_path="$3"
    
    echo "Executing runner config for: $runner_name (index: $runner_index)"
    
    # Run initial prompts
    local initial_count=$(get_runner_config "$runner_index" "$runner_name" '(.initial_prompts // []) | length')
    for ((i=0; i<initial_count; i++)); do
        local name=$(get_runner_config "$runner_index" "$runner_name" ".initial_prompts[$i].name")
        local prompt=$(get_runner_config "$runner_index" "$runner_name" ".initial_prompts[$i].prompt")
        local skip_condition=$(get_runner_config "$runner_index" "$runner_name" ".initial_prompts[$i].skip_condition // null")
        
        if [ "$skip_condition" != "null" ] && [ -n "$skip_condition" ]; then
            if eval "$skip_condition"; then
                echo "Skipping initial prompt '$name' due to condition: $skip_condition"
                continue
            fi
        fi
        
        echo "Running initial prompt: $name"
        if ! run_claude_with_retry "$prompt" "$runner_index" "$runner_name" "initial_$i" "$worktree_path" "initial"; then
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
    local loop_count=$(get_runner_config "$runner_index" "$runner_name" '(.loop_prompts // []) | length')
    
    # Skip main loop if there are no loop prompts
    if [ "$loop_count" -eq 0 ]; then
        echo "No loop prompts defined. Skipping main loop and proceeding to end prompts."
        run_end_prompts "$runner_index" "$runner_name" "$worktree_path"
        return 0
    fi
    
    local max_loops=$(get_runner_config "$runner_index" "$runner_name" '.max_loops // 10')
    # Ensure max_loops is a valid integer
    if ! [[ "$max_loops" =~ ^[0-9]+$ ]]; then
        max_loops=10
    fi
    while [ $COUNT -lt $max_loops ]; do
        echo "Iteration $COUNT"
        
        # Check exit condition first
        local loop_break_condition=$(get_runner_config "$runner_index" "$runner_name" '.loop_break_condition // null')
        if [ "$loop_break_condition" != "null" ]; then
            local file=$(get_runner_config "$runner_index" "$runner_name" '.loop_break_condition.file')
            local name=$(get_runner_config "$runner_index" "$runner_name" '.loop_break_condition.name // ""')
            
            if [ -f "$file" ]; then
                echo "Exit condition triggered: $name"
                run_end_prompts "$runner_index" "$runner_name" "$worktree_path"
                return 0
            fi
        fi
        
        # Run loop prompts based on their period
        for ((i=0; i<loop_count; i++)); do
            local name=$(get_runner_config "$runner_index" "$runner_name" ".loop_prompts[$i].name")
            local prompt=$(get_runner_config "$runner_index" "$runner_name" ".loop_prompts[$i].prompt")
            local period=$(get_runner_config "$runner_index" "$runner_name" ".loop_prompts[$i].period // 1")
            
            # Handle null or empty period
            if [ "$period" = "null" ] || [ -z "$period" ] || ! [[ "$period" =~ ^[0-9]+$ ]]; then
                period=1
            fi
            
            # Check if this prompt should run on this iteration
            if [ $((COUNT % period)) -eq 0 ]; then
                echo "Running loop prompt: $name (period: $period)"
                if ! run_claude_with_retry "$prompt" "$runner_index" "$runner_name" "loop_${COUNT}_${i}" "$worktree_path" "loop"; then
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
    local runner_index="$1"
    local runner_name="$2"
    local worktree_path="$3"
    
    local end_count=$(get_runner_config "$runner_index" "$runner_name" '(.end_prompts // []) | length')
    for ((i=0; i<end_count; i++)); do
        local name=$(get_runner_config "$runner_index" "$runner_name" ".end_prompts[$i].name")
        local prompt=$(get_runner_config "$runner_index" "$runner_name" ".end_prompts[$i].prompt")
        
        echo "Running end prompt: $name"
        run_claude_with_retry "$prompt" "$runner_index" "$runner_name" "end_$i" "$worktree_path" "final"
    done
}

# Run a single task runner
run_task_runner() {
    local task_name="$1"
    local runner_name="$2"
    local worktree_path="$3"
    local runner_index="$4"
    local timeout="$5"
    
    echo "========================================="
    echo "Starting runner: $runner_name"
    echo "Worktree: $worktree_path"
    echo "Runner Index: $runner_index"
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
    
    # Copy the main config file to worktree so get_runner_config can access it
    cp "$SCRIPT_DIR/$MULTI_CONFIG_FILE" ./ || {
        echo "ERROR: Failed to copy main config to worktree"
        return 1
    }
    
    if [ "$timeout" -gt 0 ]; then
        timeout "$timeout" bash -c "$(declare -f execute_runner_config run_claude_with_retry run_end_prompts auto_commit_changes clean_git_commands_from_prompt GET_ALLOWED_TOOLS get_runner_config); MULTI_CONFIG_FILE='$(basename "$MULTI_CONFIG_FILE")'; execute_runner_config '$runner_index' '$runner_name' '$worktree_path'" || {
            local exit_code=$?
            if [ $exit_code -eq 124 ]; then
                echo "Runner $runner_name timed out after $timeout seconds"
            else
                echo "Runner $runner_name failed with exit code: $exit_code"
            fi
            return $exit_code
        }
    else
        execute_runner_config "$runner_index" "$runner_name" "$worktree_path" || {
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
            worktree_base_path="${git_parent_dir}/${worktree_base_path_config}"
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
        
        runners+=("$runner_name:$worktree_path:$i")
    done
    
    # Execute runners based on execution mode
    if [ "$execution_mode" = "parallel" ]; then
        echo "Running $runner_count runners in parallel..."
        local pids=()
        
        for runner_info in "${runners[@]}"; do
            IFS=':' read -r runner_name worktree_path runner_index <<< "$runner_info"
            run_task_runner "$task_name" "$runner_name" "$worktree_path" "$runner_index" "$timeout" &
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
            IFS=':' read -r runner_name worktree_path runner_index <<< "$runner_info"
            run_task_runner "$task_name" "$runner_name" "$worktree_path" "$runner_index" "$timeout"
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