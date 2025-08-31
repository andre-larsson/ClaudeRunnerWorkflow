#!/bin/bash

# Cleanup script for multi-runner worktrees and branches

WORKTREE_BASE_PATH="${1:-../worktrees}"
GIT_PROJECT_DIR="${1:-../git-project}"

echo "Cleaning up worktrees and branches..."

# Check if git project exists
if [ ! -d "$GIT_PROJECT_DIR" ]; then
    echo "Git project directory not found: $GIT_PROJECT_DIR"
    echo "Nothing to clean up."
    exit 0
fi

# Change to git project directory for git operations
cd "$GIT_PROJECT_DIR" || {
    echo "ERROR: Failed to cd into git project: $GIT_PROJECT_DIR"
    exit 1
}

# Remove all worktrees in the specified directory
if [ -d "$WORKTREE_BASE_PATH" ]; then
    echo "Removing worktrees from: $WORKTREE_BASE_PATH"
    for worktree_dir in "$WORKTREE_BASE_PATH"/*; do
        if [ -d "$worktree_dir" ]; then
            echo "  Removing worktree: $(basename "$worktree_dir")"
            git worktree remove --force "$worktree_dir" 2>/dev/null || true
        fi
    done
    rmdir "$WORKTREE_BASE_PATH" 2>/dev/null || true
fi

# Remove multi-runner branches (branches containing '/')
echo "Cleaning up multi-runner branches..."
git branch --list | grep '/' | while read -r branch; do
    branch=$(echo "$branch" | sed 's/^[* ] //')
    echo "  Deleting branch: $branch"
    COMMAND="git branch -D $branch"
    echo "$COMMAND"
    $COMMAND 2>/dev/null || true
done

# Remove test worktrees directory if it exists  
if [ -d "../test_worktrees" ]; then
    echo "Removing test worktrees..."
    for worktree_dir in ../test_worktrees/*; do
        if [ -d "$worktree_dir" ]; then
            git worktree remove --force "$worktree_dir" 2>/dev/null || true
        fi
    done
    rmdir "../test_worktrees" 2>/dev/null || true
fi

# Return to original directory
cd ..

echo "Cleanup completed!"
echo ""
echo "To see current worktrees: (cd $GIT_PROJECT_DIR && git worktree list)"
echo "To see current branches: (cd $GIT_PROJECT_DIR && git branch --list)"