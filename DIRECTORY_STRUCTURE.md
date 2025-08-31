# Multi-Runner Directory Structure

## New Parallel Directory Layout

```
parent-directory/
├── multiclaude/                    # Script location (current working directory)
│   ├── multi-run.sh               # Main orchestrator script
│   ├── run-multi-test.sh          # Test runner script
│   ├── *.json                     # Configuration files
│   └── test scripts
├── git-project/                   # Git repository (parallel to multiclaude)
│   ├── .git/                      # Git metadata
│   ├── main branch                # Main development branch
│   └── task_name/runner_name      # Branches created by multi-runner
└── worktrees/                     # Git worktrees (parallel to multiclaude)
    ├── simple_test_alpha/         # Worktree for alpha runner
    ├── simple_test_beta/          # Worktree for beta runner
    └── ...                        # Additional runner worktrees
```

## Configuration Changes

**Updated config files:**
- `multi-test-config.json`
- `auto-commit-example-config.json` 
- `enhanced-commit-example-config.json`

**Key changes:**
```json
{
  "config": {
    "git_project_path": "../git-project",     // Changed from "./git-project"
    "git_base_branch": "main"                 // Changed from "master"
  },
  "multi_runner_tasks": [{
    "worktree_base_path": "../worktrees"      // Changed from "test_worktrees"
  }]
}
```

## Benefits

1. **Clean separation** - multiclaude scripts don't clutter the git project
2. **Parallel structure** - easy to navigate and understand
3. **Scalable** - multiple git projects can use the same multiclaude scripts
4. **Organized** - worktrees grouped in dedicated directory

## Usage

Run from the `multiclaude/` directory:
```bash
cd multiclaude/
./run-multi-test.sh    # Sets up ../git-project and ../worktrees
./multi-run.sh multi-test-config.json
```

The script automatically handles the parallel directory creation and management.