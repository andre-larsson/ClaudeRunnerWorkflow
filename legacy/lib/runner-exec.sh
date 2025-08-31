#!/bin/bash

# Runner execution library
# Handles Claude command execution, retry logic, and prompt management

# Define allowed tools for Claude
get_allowed_tools() {
    echo "Read,Edit,Write,MultiEdit,NotebookEdit,Bash,TodoWrite,Glob,Grep,Task,WebFetch,WebSearch,ExitPlanMode,BashOutput,KillBash"
}

# Clean git commands from prompts
clean_git_commands() {
    local prompt="$1"
    # Remove common git write commands that Claude can't execute
    echo "$prompt" | sed 's/git add[^;]*[;]*//g' | sed 's/git commit[^;]*[;]*//g' | sed 's/git push[^;]*[;]*//g'
}

# Interruptible sleep function
interruptible_sleep() {
    local duration="$1"
    local elapsed=0
    
    while [ $elapsed -lt $duration ]; do
        sleep 1
        elapsed=$((elapsed + 1))
        # Check for interrupt signal (would need global flag)
        if [ "${CLEANUP_DONE:-false}" = true ]; then
            return 1
        fi
    done
    return 0
}

# Execute Claude command with retry logic
run_claude_with_retry() {
    local prompt="$1"
    local runner_name="$2"
    local iteration="$3"
    local worktree_path="$4"
    local prompt_type="$5"
    local log_file="${6:-logs/${runner_name}-log.log}"
    local max_attempts="${7:-5}"
    local retry_delay="${8:-3600}"
    
    local allowed_tools=$(get_allowed_tools)
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo "--------------------------------" >> "$log_file"
        echo "Attempt $attempt: Running claude command..."
        echo "Command: $prompt"
        echo "$prompt" >> "$log_file"
        
        local output
        local exit_code
        
        # Clean git commands and add commit message request
        local clean_prompt=$(clean_git_commands "$prompt")
        local enhanced_prompt="$clean_prompt

Return a simple string describing changes made for git commit."
        
        # Execute Claude command
        output=$(claude --allowedTools "$allowed_tools" -p "$enhanced_prompt" 2>&1)
        exit_code=$?
        
        # Log output
        echo "$output" >> "$log_file"
        
        # Check for rate limit
        if echo "$output" | grep -q "limit reached"; then
            echo "Rate limit reached. Waiting $retry_delay seconds before retry..."
            interruptible_sleep "$retry_delay" || return 1
            attempt=$((attempt + 1))
        else
            if [ $exit_code -eq 0 ]; then
                echo "Command completed successfully!"
                # Return output for commit message
                echo "$output"
                return 0
            else
                echo "Command failed with exit code: $exit_code"
                return $exit_code
            fi
        fi
    done
    
    echo "Maximum retry attempts reached. Exiting..."
    return 1
}

# Execute initial prompts
execute_initial_prompts() {
    local config_file="$1"
    local runner_index="$2"
    local runner_name="$3"
    local worktree_path="$4"
    
    # Load config library functions
    source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
    
    local merged_config=$(merge_runner_config "$config_file" "$runner_index" "$runner_name")
    local initial_prompts=$(echo "$merged_config" | jq -c '.initial_prompts')
    local prompt_count=$(echo "$initial_prompts" | jq 'length')
    
    # Ensure prompt_count is a valid integer
    if [ -z "$prompt_count" ] || ! [[ "$prompt_count" =~ ^[0-9]+$ ]]; then
        prompt_count=0
    fi
    
    if [ "$prompt_count" -eq 0 ]; then
        echo "No initial prompts defined."
        return 0
    fi
    
    for ((i=0; i<prompt_count; i++)); do
        local prompt_obj=$(echo "$initial_prompts" | jq -r ".[$i]")
        local name=$(echo "$prompt_obj" | jq -r '.name // "unnamed"')
        local prompt=$(echo "$prompt_obj" | jq -r '.prompt // ""')
        local skip_condition=$(echo "$prompt_obj" | jq -r '.skip_condition // ""')
        
        # Check skip condition
        if [ -n "$skip_condition" ] && [ "$skip_condition" != "null" ]; then
            if (cd "$worktree_path" && eval "$skip_condition"); then
                echo "Skipping initial prompt '$name' due to condition: $skip_condition"
                continue
            fi
        fi
        
        echo "Running initial prompt: $name"
        
        # Run command in worktree directory
        (
            cd "$worktree_path" || exit 1
            local output=$(run_claude_with_retry "$prompt" "$runner_name" "initial_$i" "$worktree_path" "initial")
            local exit_code=$?
            
            # Auto-commit if successful
            if [ $exit_code -eq 0 ]; then
                source "$(dirname "${BASH_SOURCE[0]}")/git-ops.sh"
                auto_commit_changes "$worktree_path" "$runner_name" "initial_$i" "initial" "$output" "$prompt"
            fi
            
            exit $exit_code
        ) || {
            echo "Failed to complete initial prompt '$name'"
            return 1
        }
    done
    
    return 0
}

# Execute loop prompts
execute_loop_prompts() {
    local config_file="$1"
    local runner_index="$2"
    local runner_name="$3"
    local worktree_path="$4"
    local iteration="$5"
    
    # Load config library functions
    source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
    
    local merged_config=$(merge_runner_config "$config_file" "$runner_index" "$runner_name")
    local loop_prompts=$(echo "$merged_config" | jq -c '.loop_prompts')
    local prompt_count=$(echo "$loop_prompts" | jq 'length')
    
    # Ensure prompt_count is a valid integer
    if [ -z "$prompt_count" ] || ! [[ "$prompt_count" =~ ^[0-9]+$ ]]; then
        prompt_count=0
    fi
    
    if [ "$prompt_count" -eq 0 ]; then
        return 0
    fi
    
    for ((i=0; i<prompt_count; i++)); do
        local prompt_obj=$(echo "$loop_prompts" | jq -r ".[$i]")
        local name=$(echo "$prompt_obj" | jq -r '.name // "unnamed"')
        local prompt=$(echo "$prompt_obj" | jq -r '.prompt // ""')
        local period=$(echo "$prompt_obj" | jq -r '.period // 1')
        
        # Ensure period is valid
        if [ "$period" = "null" ] || ! [[ "$period" =~ ^[0-9]+$ ]]; then
            period=1
        fi
        
        # Check if should run this iteration
        if [ $((iteration % period)) -eq 0 ]; then
            echo "Running loop prompt: $name (period: $period)"
            
            # Run command in worktree directory
            (
                cd "$worktree_path" || exit 1
                local output=$(run_claude_with_retry "$prompt" "$runner_name" "loop_${iteration}_${i}" "$worktree_path" "loop")
                local exit_code=$?
                
                # Auto-commit if successful
                if [ $exit_code -eq 0 ]; then
                    source "$(dirname "${BASH_SOURCE[0]}")/git-ops.sh"
                    auto_commit_changes "$worktree_path" "$runner_name" "loop_${iteration}_${i}" "loop" "$output" "$prompt"
                fi
                
                exit $exit_code
            ) || {
                echo "Failed to complete loop prompt '$name'"
                return 1
            }
        fi
    done
    
    return 0
}

# Execute end prompts
execute_end_prompts() {
    local config_file="$1"
    local runner_index="$2"
    local runner_name="$3"
    local worktree_path="$4"
    
    # Load config library functions
    source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
    
    local merged_config=$(merge_runner_config "$config_file" "$runner_index" "$runner_name")
    local end_prompts=$(echo "$merged_config" | jq -c '.end_prompts')
    local prompt_count=$(echo "$end_prompts" | jq 'length')
    
    # Ensure prompt_count is a valid integer
    if [ -z "$prompt_count" ] || ! [[ "$prompt_count" =~ ^[0-9]+$ ]]; then
        prompt_count=0
    fi
    
    if [ "$prompt_count" -eq 0 ]; then
        echo "No end prompts defined."
        return 0
    fi
    
    for ((i=0; i<prompt_count; i++)); do
        local prompt_obj=$(echo "$end_prompts" | jq -r ".[$i]")
        local name=$(echo "$prompt_obj" | jq -r '.name // "unnamed"')
        local prompt=$(echo "$prompt_obj" | jq -r '.prompt // ""')
        
        echo "Running end prompt: $name"
        
        # Run command in worktree directory
        (
            cd "$worktree_path" || exit 1
            local output=$(run_claude_with_retry "$prompt" "$runner_name" "end_$i" "$worktree_path" "final")
            local exit_code=$?
            
            # Auto-commit if successful
            if [ $exit_code -eq 0 ]; then
                source "$(dirname "${BASH_SOURCE[0]}")/git-ops.sh"
                auto_commit_changes "$worktree_path" "$runner_name" "end_$i" "final" "$output" "$prompt"
            fi
            
            exit $exit_code
        ) || {
            echo "Failed to complete end prompt '$name'"
            return 1
        }
    done
    
    return 0
}

# Check loop break condition
check_loop_break_condition() {
    local config_file="$1"
    local runner_index="$2"
    local runner_name="$3"
    local worktree_path="$4"
    
    # Load config library functions
    source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
    
    local merged_config=$(merge_runner_config "$config_file" "$runner_index" "$runner_name")
    local break_condition=$(echo "$merged_config" | jq -c '.loop_break_condition')
    
    if [ "$break_condition" = "null" ]; then
        return 1  # No break condition, continue loop
    fi
    
    local file=$(echo "$break_condition" | jq -r '.file // ""')
    local name=$(echo "$break_condition" | jq -r '.name // "exit condition"')
    
    if [ -n "$file" ] && [ "$file" != "null" ]; then
        if (cd "$worktree_path" && [ -f "$file" ]); then
            echo "Loop break condition triggered: $name (file: $file exists)"
            return 0  # Break condition met
        fi
    fi
    
    return 1  # Continue loop
}

# Main runner execution
execute_runner() {
    local config_file="$1"
    local runner_index="$2"
    local runner_name="$3"
    local worktree_path="$4"
    
    echo "Executing runner: $runner_name (index: $runner_index)"
    
    # Load config library
    source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
    
    # Change to worktree directory
    cd "$worktree_path" || {
        echo "ERROR: Failed to cd into worktree: $worktree_path"
        return 1
    }
    
    # Create logs directory
    mkdir -p logs || {
        echo "ERROR: Failed to create logs directory"
        return 1
    }
    
    # Check for package.json and install dependencies
    if [ -f package.json ]; then
        echo "Installing npm dependencies..."
        npm install
    fi
    
    # Execute initial prompts
    execute_initial_prompts "$config_file" "$runner_index" "$runner_name" "$worktree_path" || return 1
    
    # Check if we have loop prompts before starting the loop
    local merged_config=$(merge_runner_config "$config_file" "$runner_index" "$runner_name")
    local loop_prompts=$(echo "$merged_config" | jq -c '.loop_prompts')
    local loop_prompt_count=$(echo "$loop_prompts" | jq 'length' 2>/dev/null || echo "0")
    
    # Ensure it's a valid integer
    if [ -z "$loop_prompt_count" ] || ! [[ "$loop_prompt_count" =~ ^[0-9]+$ ]]; then
        loop_prompt_count=0
    fi
    
    if [ "$loop_prompt_count" -gt 0 ]; then
        # Get max loops
        local max_loops=$(get_max_loops "$config_file")
        
        # Main loop
        local iteration=0
        while [ $iteration -lt $max_loops ]; do
            echo "Iteration $iteration of $max_loops"
            
            # Check break condition
            if check_loop_break_condition "$config_file" "$runner_index" "$runner_name" "$worktree_path"; then
                break
            fi
            
            # Execute loop prompts
            execute_loop_prompts "$config_file" "$runner_index" "$runner_name" "$worktree_path" "$iteration" || return 1
            
            iteration=$((iteration + 1))
        done
    else
        echo "No loop prompts defined - skipping main loop"
    fi
    
    # Execute end prompts
    execute_end_prompts "$config_file" "$runner_index" "$runner_name" "$worktree_path"
    
    echo "Runner $runner_name completed successfully"
    return 0
}