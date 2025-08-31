#!/bin/bash

# Git operations library
# Handles git repository initialization, worktree management, and commits

# Check if directory is a git repository
is_git_repo() {
    local dir="$1"
    (cd "$dir" 2>/dev/null && git rev-parse --git-dir >/dev/null 2>&1)
}

# Check if repository has commits
has_commits() {
    local dir="$1"
    (cd "$dir" 2>/dev/null && git rev-parse HEAD >/dev/null 2>&1)
}

# Get current branch name
get_current_branch() {
    local dir="$1"
    (cd "$dir" 2>/dev/null && git rev-parse --abbrev-ref HEAD 2>/dev/null) || echo ""
}

# Check if branch exists
branch_exists() {
    local dir="$1"
    local branch="$2"
    (cd "$dir" 2>/dev/null && git show-ref --quiet refs/heads/"$branch")
}

# Initialize git repository
init_git_repo() {
    local dir="$1"
    
    echo "Initializing git repository: $dir" >&2
    (cd "$dir" && git init) || {
        echo "ERROR: Failed to initialize git repository" >&2
        return 1
    }
}

# Create initial commit
create_initial_commit() {
    local dir="$1"
    
    echo "Creating initial commit in: $dir" >&2
    (cd "$dir" && {
        echo "# Initial repository" > README.md
        git add README.md
        git commit -m "Initial commit"
    }) || {
        echo "ERROR: Failed to create initial commit" >&2
        return 1
    }
}

# Ensure base branch exists and is checked out
ensure_base_branch() {
    local dir="$1"
    local branch="$2"
    
    cd "$dir" || return 1
    
    local current_branch=$(get_current_branch "$dir")
    
    if [ "$current_branch" != "$branch" ]; then
        if branch_exists "$dir" "$branch"; then
            echo "Checking out existing base branch: $branch" >&2
            git checkout "$branch" >/dev/null 2>&1
        else
            echo "Creating and checking out base branch: $branch" >&2
            git checkout -b "$branch" >/dev/null 2>&1
        fi
    fi
}

# Setup git repository
setup_git_repository() {
    local git_project_path="$1"
    local base_branch="$2"
    
    # Create directory if it doesn't exist
    if [ ! -d "$git_project_path" ]; then
        echo "Creating git project directory: $git_project_path" >&2
        mkdir -p "$git_project_path" || {
            echo "ERROR: Failed to create directory: $git_project_path" >&2
            return 1
        }
    fi
    
    # Initialize git if needed
    if ! is_git_repo "$git_project_path"; then
        init_git_repo "$git_project_path" || return 1
    fi
    
    # Ensure at least one commit exists
    if ! has_commits "$git_project_path"; then
        create_initial_commit "$git_project_path" || return 1
    fi
    
    # Ensure base branch exists
    ensure_base_branch "$git_project_path" "$base_branch" || return 1
    
    echo "Using git project at: $git_project_path (branch: $base_branch)" >&2
    return 0
}

# Clean up existing worktree
cleanup_existing_worktree() {
    local git_dir="$1"
    local branch_name="$2"
    
    cd "$git_dir" || return 1
    
    # Check if worktree exists for this branch
    if git worktree list | grep -q "$branch_name"; then
        echo "Removing existing worktree for branch: $branch_name" >&2
        local worktree_path=$(git worktree list | grep "$branch_name" | awk '{print $1}')
        git worktree remove --force "$worktree_path" 2>/dev/null || true
    fi
}

# Delete branch if it exists
delete_branch_if_exists() {
    local git_dir="$1"
    local branch_name="$2"
    
    cd "$git_dir" || return 1
    
    if branch_exists "$git_dir" "$branch_name"; then
        echo "Deleting existing branch: $branch_name" >&2
        git branch -D "$branch_name" >/dev/null 2>&1
    fi
}

# Create git worktree for runner
create_runner_worktree() {
    local git_project_path="$1"
    local task_name="$2"
    local runner_name="$3"
    local worktree_path="$4"
    local base_branch="$5"
    
    local branch_name="${task_name}/${runner_name}"
    
    echo "Creating worktree for runner: $runner_name" >&2
    echo "  Branch: $branch_name" >&2
    echo "  Path: $worktree_path" >&2
    echo "  Git project: $git_project_path" >&2
    
    # Change to git project directory
    cd "$git_project_path" || {
        echo "ERROR: Failed to cd into git project: $git_project_path" >&2
        return 1
    }
    
    # Checkout base branch
    git checkout "$base_branch" >/dev/null 2>&1 || {
        echo "ERROR: Could not checkout base branch $base_branch" >&2
        return 1
    }
    
    # Clean up any existing worktree for this branch
    cleanup_existing_worktree "$git_project_path" "$branch_name"
    
    # Remove existing directory at worktree path
    if [ -d "$worktree_path" ]; then
        echo "Removing existing directory at $worktree_path" >&2
        rm -rf "$worktree_path"
    fi
    
    # Create parent directory
    mkdir -p "$(dirname "$worktree_path")"
    
    # Delete branch if it exists
    delete_branch_if_exists "$git_project_path" "$branch_name"
    
    # Create new worktree with new branch
    echo "Creating worktree: git worktree add $worktree_path -b $branch_name" >&2
    git worktree add "$worktree_path" -b "$branch_name" >/dev/null 2>&1 || {
        echo "ERROR: Failed to create worktree at $worktree_path" >&2
        return 1
    }
    
    # Switch back to base branch
    git checkout "$base_branch" >/dev/null 2>&1 || {
        echo "Warning: Could not switch back to base branch $base_branch" >&2
    }
    
    return 0
}

# Check for uncommitted changes
has_uncommitted_changes() {
    local dir="$1"
    
    cd "$dir" || return 1
    
    # Check for any changes
    git status --porcelain | grep -q '^[^ ]' || ! git diff --quiet || ! git diff --cached --quiet
}

# Auto-commit changes
auto_commit_changes() {
    local worktree_path="$1"
    local runner_name="$2"
    local iteration="$3"
    local prompt_type="$4"
    local claude_output="$5"
    local original_prompt="$6"
    
    cd "$worktree_path" || return 1
    
    if has_uncommitted_changes "$worktree_path"; then
        # Add all changes
        git add .
        
        # Generate commit message
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local claude_msg="${claude_output:-No description provided}"
        
        local commit_msg="[$prompt_type] $runner_name: $claude_msg

Prompt: $original_prompt
Runner: $runner_name
Iteration: $iteration
Type: $prompt_type
Timestamp: $timestamp"
        
        # Commit changes
        git commit -m "$commit_msg"
        
        echo "Auto-committed changes for $runner_name ($prompt_type): $claude_msg" >&2
    else
        echo "No changes to commit for $runner_name (iteration $iteration)" >&2
    fi
    
    return 0
}

# List all worktrees
list_worktrees() {
    local git_dir="$1"
    
    cd "$git_dir" || return 1
    git worktree list
}

# Remove worktree
remove_worktree() {
    local git_dir="$1"
    local worktree_path="$2"
    
    cd "$git_dir" || return 1
    git worktree remove --force "$worktree_path" 2>/dev/null || true
}

# Prune worktrees
prune_worktrees() {
    local git_dir="$1"
    
    cd "$git_dir" || return 1
    git worktree prune
}