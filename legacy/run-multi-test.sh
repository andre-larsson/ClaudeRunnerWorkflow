#!/bin/bash

# Complete setup and test script for multi-runner system

set -e  # Exit on any error

echo "Multi-Runner Test Setup and Execution"
echo "===================================="

# Set directories parallel to current directory
CURRENT_DIR="$(pwd)"
PARENT_DIR="$(dirname "$CURRENT_DIR")"
GIT_PROJECT_DIR="$PARENT_DIR/git-project"
WORKTREE_BASE_DIR="$PARENT_DIR/worktrees"

echo "Current directory: $CURRENT_DIR"
echo "Git project will be at: $GIT_PROJECT_DIR"
echo "Worktrees will be at: $WORKTREE_BASE_DIR"

# Step 1: Create and initialize git project
echo "Step 1: Setting up git project..."

if [ ! -d "$GIT_PROJECT_DIR" ]; then
    echo "Creating git project directory: $GIT_PROJECT_DIR"
    mkdir -p "$GIT_PROJECT_DIR"
fi

# change to git project directory
cd "$GIT_PROJECT_DIR"

if [ ! -d ".git" ]; then
    echo "Initializing git repository..."
    git init
    git config user.name "Multi-Runner Test" 2>/dev/null || true
    git config user.email "test@multirunner.local" 2>/dev/null || true
    
    # Create initial file
    echo "# Test Project for Multi-Runner System" > README.md
    echo "" >> README.md
    echo "This is a test repository for testing the multi-runner system." >> README.md
    echo "Created at: $(date)" >> README.md
    
    git add README.md
    git commit -m "Initial commit for multi-runner testing"
    echo "Git repository initialized successfully!"
else
    echo "Git repository already exists"
fi

# Ensure we're on main branch
git checkout main 2>/dev/null || git checkout -b main 2>/dev/null || true

echo "Git status:"
echo "  Current branch: $(git branch --show-current 2>/dev/null || echo 'unknown')"
echo "  Commit count: $(git rev-list --count HEAD 2>/dev/null || echo '0')"

# Step 2: Clean up any previous test runs
# change to current directory
cd "$CURRENT_DIR"
echo ""
echo "Step 2: Cleaning up previous test runs..."
chmod +x ./cleanup-worktrees.sh
./cleanup-worktrees.sh "$WORKTREE_BASE_DIR"

# Step 3: Run the multi-runner test
echo ""
echo "Step 3: Running multi-runner test..."
./multi-run.sh multi-test-config.json

# Step 4: Show results
echo ""
echo "Step 4: Test Results"
echo "==================="

if [ -d "$WORKTREE_BASE_DIR" ]; then
    echo "Worktrees created:"
    for dir in "$WORKTREE_BASE_DIR"/*; do
        if [ -d "$dir" ]; then
            echo "  - $(basename "$dir")"
            if [ -f "$dir/logs/test-result.txt" ]; then
                echo "    Result: $(cat "$dir/logs/test-result.txt")"
            else
                echo "    Result file not found"
            fi
        fi
    done
else
    echo "No test worktrees found!"
fi

echo ""
echo "Git branches:"
cd "$GIT_PROJECT_DIR"
git branch --list | grep -E "(simple_test|main)" || echo "No relevant branches found"
cd "$CURRENT_DIR"

echo ""
echo "Git worktrees:"
cd "$GIT_PROJECT_DIR"
git worktree list 2>/dev/null || echo "No worktrees found"
cd "$CURRENT_DIR"

echo ""
echo "Multi-runner test completed!"