#!/bin/bash

# Configuration management library
# Handles JSON config parsing, validation, and runner configuration merging

# Load configuration file
load_config() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        echo "ERROR: Configuration file not found: $config_file"
        return 1
    fi
    
    # Validate it's valid JSON
    if ! jq empty "$config_file" 2>/dev/null; then
        echo "ERROR: Invalid JSON in configuration file: $config_file"
        return 1
    fi
    
    echo "$config_file"
}

# Get a configuration value with default
get_config_value() {
    local config_file="$1"
    local path="$2"
    local default="${3:-}"
    
    local value=$(jq -r "$path // empty" "$config_file" 2>/dev/null)
    if [ -z "$value" ] || [ "$value" = "null" ]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Get task configuration
get_task_name() {
    local config_file="$1"
    get_config_value "$config_file" ".task_name" "untitled_task"
}

get_task_description() {
    local config_file="$1"
    get_config_value "$config_file" ".task_description" "No description provided"
}

get_git_project_path() {
    local config_file="$1"
    get_config_value "$config_file" ".git_project_path" ""
}

get_git_base_branch() {
    local config_file="$1"
    get_config_value "$config_file" ".git_base_branch" "main"
}

get_worktree_base_path() {
    local config_file="$1"
    get_config_value "$config_file" ".worktree_base_path" "worktrees"
}

get_execution_mode() {
    local config_file="$1"
    get_config_value "$config_file" ".execution_mode" "sequential"
}

get_max_loops() {
    local config_file="$1"
    local value=$(get_config_value "$config_file" ".max_loops" "10")
    # Ensure it's a valid integer
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "$value"
    else
        echo "10"
    fi
}

# Get runner count
get_runner_count() {
    local config_file="$1"
    local count=$(jq -r '(.runners // []) | length' "$config_file" 2>/dev/null)
    
    # Handle empty or invalid result
    if [ -z "$count" ] || [ "$count" = "null" ] || ! [[ "$count" =~ ^[0-9]+$ ]]; then
        echo "0"
    else
        echo "$count"
    fi
}

# Get runner name by index
get_runner_name() {
    local config_file="$1"
    local index="$2"
    local name=$(jq -r ".runners[$index].name // empty" "$config_file")
    echo "$name"
}

# Get prompts arrays
get_initial_prompts() {
    local config_file="$1"
    jq -c '.initial_prompts // []' "$config_file"
}

get_loop_prompts() {
    local config_file="$1"
    jq -c '.loop_prompts // []' "$config_file"
}

get_end_prompts() {
    local config_file="$1"
    jq -c '.end_prompts // []' "$config_file"
}

get_loop_break_condition() {
    local config_file="$1"
    jq -c '.loop_break_condition // null' "$config_file"
}

# Get prompt count
get_prompt_count() {
    local prompts_json="$1"
    echo "$prompts_json" | jq 'length'
}

# Get prompt by index
get_prompt_by_index() {
    local prompts_json="$1"
    local index="$2"
    echo "$prompts_json" | jq -r ".[$index]"
}

# Get prompt field
get_prompt_field() {
    local prompt_json="$1"
    local field="$2"
    local default="${3:-}"
    
    local value=$(echo "$prompt_json" | jq -r ".$field // empty")
    if [ -z "$value" ] || [ "$value" = "null" ]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Get runner modifications
get_runner_modifications() {
    local config_file="$1"
    local runner_index="$2"
    local modification_type="$3"
    
    jq -r ".runners[$runner_index].prompt_modifications.$modification_type // \"\"" "$config_file"
}

# Get runner extra prompts
get_runner_extra_prompts() {
    local config_file="$1"
    local runner_index="$2"
    local prompt_type="$3"
    
    jq -c ".runners[$runner_index].extra_prompts.$prompt_type // []" "$config_file"
}

# Merge runner configuration
merge_runner_config() {
    local config_file="$1"
    local runner_index="$2"
    local runner_name="$3"
    
    # Check if we have runners defined
    local runner_count=$(get_runner_count "$config_file")
    
    if [ "$runner_count" -eq 0 ] || [ "$runner_index" -ge "$runner_count" ]; then
        # No runners or invalid index - return base config without modifications
        jq -n \
          --arg runner_name "$runner_name" \
          --slurpfile base_config "$config_file" '
          {
            runner_name: $runner_name,
            max_loops: ($base_config[0].max_loops // 10),
            initial_prompts: ($base_config[0].initial_prompts // []),
            loop_prompts: ($base_config[0].loop_prompts // []),
            loop_break_condition: ($base_config[0].loop_break_condition // null),
            end_prompts: ($base_config[0].end_prompts // [])
          }'
        return
    fi
    
    # Get modifications
    local append_to_all=$(get_runner_modifications "$config_file" "$runner_index" "append_to_all")
    local append_to_initial=$(get_runner_modifications "$config_file" "$runner_index" "append_to_initial")
    local append_to_loop=$(get_runner_modifications "$config_file" "$runner_index" "append_to_loop")
    local append_to_final=$(get_runner_modifications "$config_file" "$runner_index" "append_to_final")
    
    # Create merged config
    jq -n \
      --arg runner_name "$runner_name" \
      --arg append_to_all "$append_to_all" \
      --arg append_to_initial "$append_to_initial" \
      --arg append_to_loop "$append_to_loop" \
      --arg append_to_final "$append_to_final" \
      --slurpfile base_config "$config_file" \
      --argjson runner_index "$runner_index" '
      def merge_prompts($prompts; $append_all; $append_specific):
        ($prompts // [])
        | map(
            . as $p
            | ($p.prompt // "") as $base
            | $p + { prompt: ($base + $append_all + $append_specific) }
          );
      
      {
        runner_name: $runner_name,
        max_loops: ($base_config[0].max_loops // 10),
        initial_prompts:
          ( merge_prompts($base_config[0].initial_prompts; $append_to_all; $append_to_initial)
            + ($base_config[0].runners[$runner_index].extra_prompts.initial_prompts // []) ),
        loop_prompts:
          ( merge_prompts($base_config[0].loop_prompts; $append_to_all; $append_to_loop)
            + ($base_config[0].runners[$runner_index].extra_prompts.loop_prompts // []) ),
        loop_break_condition:
          ( $base_config[0].loop_break_condition // ($base_config[0].runners[$runner_index].extra_prompts.loop_break_condition // null) ),
        end_prompts:
          ( merge_prompts($base_config[0].end_prompts; $append_to_all; $append_to_final)
            + ($base_config[0].runners[$runner_index].extra_prompts.end_prompts // []) )
      }'
}

# Get merged runner config as simple accessor
get_runner_config() {
    local config_file="$1"
    local runner_index="$2"
    local runner_name="$3"
    local query="$4"
    
    local runner_count=$(get_runner_count "$config_file")
    
    if [ "$runner_count" -eq 0 ]; then
        # No runners defined, return base config
        jq -r "$query" "$config_file"
    else
        # Return merged config
        merge_runner_config "$config_file" "$runner_index" "$runner_name" | jq -r "$query"
    fi
}

# Validate required configuration
validate_config() {
    local config_file="$1"
    
    # Check if config file exists
    if [ ! -f "$config_file" ]; then
        echo "ERROR: Configuration file not found: $config_file"
        return 1
    fi
    
    # Check required fields
    local git_project_path=$(get_git_project_path "$config_file")
    if [ -z "$git_project_path" ] || [ "$git_project_path" = "null" ]; then
        echo "ERROR: git_project_path is required in configuration file"
        echo "Please add 'git_project_path' to your config file."
        return 1
    fi
    
    return 0
}

# Generate random ID for unnamed entities
generate_random_id() {
    local length="${1:-6}"
    tr -dc 'a-z0-9' < /dev/urandom | head -c "$length"
}

# Ensure task name exists
ensure_task_name() {
    local config_file="$1"
    local task_name=$(get_task_name "$config_file")
    
    if [ "$task_name" = "untitled_task" ] || [ -z "$task_name" ]; then
        task_name="task_$(generate_random_id)"
        echo "Generated task name: $task_name" >&2
    fi
    
    echo "$task_name"
}

# Ensure runners exist
ensure_runners() {
    local config_file="$1"
    local runner_count=$(get_runner_count "$config_file")
    
    if [ "$runner_count" -eq 0 ]; then
        echo "No runners found - using default runner" >&2
        # Return a default runner configuration
        echo '[{"name": "default"}]'
    else
        jq -c '.runners' "$config_file"
    fi
}