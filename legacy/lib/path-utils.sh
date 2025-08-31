#!/bin/bash

# Path utilities library
# Handles path resolution, validation, and worktree path calculation

# Resolve path to absolute path
resolve_absolute_path() {
    local base_dir="$1"
    local path="$2"
    
    if [[ "$path" = /* ]]; then
        # Already absolute
        echo "$path"
    else
        # Relative path - resolve from base directory
        echo "$(cd "$base_dir" && realpath -m "$path")"
    fi
}

# Get absolute path for a file/directory
get_absolute_path() {
    local path="$1"
    local base_dir="${2:-$(pwd)}"
    
    if [[ "$path" = /* ]]; then
        # Already absolute
        realpath -m "$path"
    else
        # Relative path
        if [ -e "$path" ]; then
            realpath "$path"
        else
            # Path doesn't exist yet, construct it
            realpath -m "$base_dir/$path"
        fi
    fi
}

# Calculate worktree base path
calculate_worktree_path() {
    local git_project_path="$1"
    local worktree_base_config="$2"
    local script_dir="$3"
    
    local worktree_base_path
    
    if [[ "$worktree_base_config" = /* ]]; then
        # Absolute path provided
        worktree_base_path="$worktree_base_config"
    else
        # Relative path - resolve from script directory
        # Special case: if it's just a simple name (no / or ..), create as sibling to git project
        if [[ "$worktree_base_config" != *"/"* ]] && [[ "$worktree_base_config" != *".."* ]]; then
            # Simple name like "worktrees" - create as sibling to git project
            local git_abs_path=$(resolve_absolute_path "$script_dir" "$git_project_path")
            local git_parent_dir=$(dirname "$git_abs_path")
            worktree_base_path="${git_parent_dir}/${worktree_base_config}"
        else
            # Path with / or .. - resolve relative to script directory
            worktree_base_path=$(resolve_absolute_path "$script_dir" "$worktree_base_config")
        fi
    fi
    
    echo "$worktree_base_path"
}

# Get worktree path for a specific runner
get_runner_worktree_path() {
    local worktree_base_path="$1"
    local task_name="$2"
    local runner_name="$3"
    
    echo "${worktree_base_path}/${task_name}_${runner_name}"
}

# Validate that paths don't create nested git repositories
validate_no_nesting() {
    local script_dir="$1"
    local git_project_path="$2"
    local worktree_path="$3"
    
    local script_abs=$(realpath "$script_dir")
    local git_abs=$(get_absolute_path "$git_project_path" "$script_dir")
    local worktree_abs=$(get_absolute_path "$worktree_path" "$script_dir")
    
    # Check if git_project_path is inside script directory
    case "$git_abs/" in
        "$script_abs"/*)
            echo "ERROR: git_project_path cannot be inside the multiclaude directory"
            echo "git_project_path: $git_abs"
            echo "multiclaude directory: $script_abs"
            return 1
            ;;
    esac
    
    # Check if worktree_path is inside script directory
    case "$worktree_abs/" in
        "$script_abs"/*)
            echo "ERROR: worktree_base_path cannot be inside the multiclaude directory"
            echo "worktree_base_path: $worktree_abs"
            echo "multiclaude directory: $script_abs"
            return 1
            ;;
    esac
    
    return 0
}

# Validate all paths in configuration
validate_paths() {
    local script_dir="$1"
    local git_project_path="$2"
    local worktree_base_config="$3"
    
    # Calculate actual worktree path
    local worktree_path=$(calculate_worktree_path "$git_project_path" "$worktree_base_config" "$script_dir")
    
    # Validate no nesting
    if ! validate_no_nesting "$script_dir" "$git_project_path" "$worktree_path"; then
        echo "Path validation failed. Please use paths outside the multiclaude directory."
        return 1
    fi
    
    echo "✓ Path validation passed"
    echo "  Git project: $(get_absolute_path "$git_project_path" "$script_dir")"
    echo "  Worktrees: $(get_absolute_path "$worktree_path" "$script_dir")"
    echo "  Multiclaude: $(realpath "$script_dir")"
    
    return 0
}

# Create directory if it doesn't exist
ensure_directory() {
    local dir="$1"
    
    if [ ! -d "$dir" ]; then
        echo "Creating directory: $dir"
        mkdir -p "$dir" || {
            echo "ERROR: Failed to create directory: $dir"
            return 1
        }
    fi
    
    return 0
}

# Convert relative path to absolute from worktree perspective
resolve_worktree_path() {
    local worktree_path="$1"
    
    # Convert to absolute path if relative
    if [[ ! "$worktree_path" = /* ]]; then
        # Create parent directory first if it doesn't exist
        local parent_dir=$(dirname "$worktree_path")
        ensure_directory "$parent_dir" >/dev/null 2>&1
        
        # Try to resolve with realpath
        local abs_path=$(realpath -m "$worktree_path" 2>/dev/null)
        if [ -n "$abs_path" ]; then
            echo "$abs_path"
        else
            # Fallback to manual construction
            echo "$(pwd)/$worktree_path"
        fi
    else
        echo "$worktree_path"
    fi
}

# Get parent directory of a path
get_parent_dir() {
    local path="$1"
    dirname "$path"
}

# Get base name of a path
get_base_name() {
    local path="$1"
    basename "$path"
}

# Check if path exists
path_exists() {
    local path="$1"
    [ -e "$path" ]
}

# Check if directory exists
dir_exists() {
    local path="$1"
    [ -d "$path" ]
}

# Check if file exists
file_exists() {
    local path="$1"
    [ -f "$path" ]
}