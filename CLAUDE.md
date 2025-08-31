# CLAUDE.md

Multi-runner orchestration system for Claude CLI tasks using JSON configuration.

## Two Versions Available

### 1. **Full Version** (`multi-run.sh`)
Complete orchestration with git worktrees, branches, looping, and prompt modifications.

### 2. **Simple Version** (`multi-simple.sh`)  
Lightweight runner for testing multiple Claude approaches without git complexity.

---

# Simple Version (`multi-simple.sh`)

## Purpose
Run the same prompt multiple times in parallel to compare different Claude approaches. No git, no loops, just parallel execution with optional template directories.

## Quick Start

```bash
# Make executable
chmod +x multi-simple.sh

# Run with config
./multi-simple.sh configs/simple/basic.json

# Check progress
watch "grep -H . runs/*/runner_*/status.txt"
```

## Simple Configuration

```json
{
  "prompt": "Build a calculator web application",
  "num_runners": 5,
  "max_parallel": 3,
  "base_directory": "./runs",
  "template_directory": "./starter-app",
  "execution_mode": "parallel"
}
```

### Configuration Properties
- `prompt` (required): The Claude prompt to execute
- `num_runners`: Number of times to run (default: 3)
- `max_parallel`: Max concurrent runs (default: 5)
- `base_directory`: Output location (default: "./runs")
- `template_directory`: Optional starter code to copy
- `execution_mode`: "parallel" or "sequential" (default: "sequential")

## Output Structure

```
runs/
└── 20241125_143022/        # Timestamped run
    ├── config.json          # Config used
    ├── execution.log        # Overall timing
    ├── runner_1/
    │   ├── status.txt       # running/completed/failed
    │   ├── timing.log       # Start/end times
    │   ├── output.log       # Claude output
    │   └── [template files] # If template used
    └── runner_2/
        └── ...
```

## Use Cases
- **Compare approaches**: See how Claude solves the same problem differently
- **Test consistency**: Verify response reliability
- **Refactoring tests**: Start from template, compare refactoring strategies
- **Bug fix approaches**: Multiple solutions to the same bug
- **Performance testing**: Run many instances with controlled parallelism

---

# Full Version (`multi-run.sh`)

## Purpose
Complete orchestration with git worktrees, branches, looping, and runner-specific prompt modifications for complex multi-agent workflows.

## Prerequisites

- Claude CLI installed and configured
- `jq` JSON processor (`brew install jq` / `sudo apt-get install jq`)
- Git repository for target project

## Quick Start

```bash
# Make executable
chmod +x multi-run.sh

# Run with config
./multi-run.sh configs/my-config.json

# View logs  
tail -f logs/runner-name-log.log
```

## Full Configuration Structure

```json
{
  "task_name": "my_task",
  "task_description": "Task description",
  "git_project_path": "../my-project",
  "git_base_branch": "main",
  "worktree_base_path": "worktrees", 
  "execution_mode": "sequential",
  "max_loops": 10,
  
  "initial_prompts": [
    {
      "name": "setup",
      "prompt": "Initialize the project",
      "skip_condition": "[ -f package.json ]"
    }
  ],
  "loop_prompts": [
    {
      "name": "develop",
      "prompt": "Continue development",
      "period": 1
    }
  ],
  "loop_break_condition": {
    "name": "done", 
    "file": "COMPLETE.flag"
  },
  "end_prompts": [
    {
      "name": "finalize",
      "prompt": "Clean up and summarize"
    }
  ],
  
  "runners": [
    {
      "name": "approach_one",
      "prompt_modifications": {
        "append_to_all": " Focus on maintainability.",
        "append_to_initial": " Use best practices.",
        "append_to_loop": " Refactor as needed.",
        "append_to_final": " Document changes."
      },
      "extra_prompts": {
        "initial_prompts": [],
        "loop_prompts": [],
        "end_prompts": []
      }
    }
  ]
}
```

## Configuration Properties

### Required
- `git_project_path`: Path to target git repository

### Optional
- `task_name`: Unique identifier (auto-generated if missing)
- `task_description`: Description (default: "No description provided")
- `git_base_branch`: Starting branch (default: "main") 
- `worktree_base_path`: Worktree directory (default: "worktrees")
- `execution_mode`: "sequential" or "parallel" (default: "sequential")
- `max_loops`: Maximum iterations (default: 10)
- `runners`: Array of runner configs (default: single "default" runner)

### Prompts
- `initial_prompts`: Run once at start (supports `skip_condition`)
- `loop_prompts`: Run repeatedly (supports `period` for frequency)
- `loop_break_condition`: File-based exit trigger
- `end_prompts`: Run once before completion

### Runner Customization
- `prompt_modifications`: Append text to prompts
- `extra_prompts`: Add runner-specific prompts

## Architecture

```
multiclaude/
├── multi-run.sh           # Main orchestrator
├── lib/
│   ├── config.sh          # Configuration parsing
│   ├── path-utils.sh      # Path utilities
│   ├── git-ops.sh         # Git operations
│   ├── runner-exec.sh     # Claude execution
│   └── logging.sh         # Logging utilities
└── configs/               # Configuration files

../my-project/             # Target git repository
../worktrees/              # Runner worktrees
    └── task_runner/       # Individual runner worktree
```

## Execution Flow

1. **Validation**: Check dependencies and configuration
2. **Setup**: Create worktrees and branches for each runner
3. **Initial**: Execute initial prompts (with skip conditions)
4. **Loop**: Run loop prompts based on period (skip if none defined)
5. **End**: Execute end prompts
6. **Commit**: Auto-commit all changes

## Features

- **Parallel/Sequential Execution**: Run multiple approaches simultaneously or one-by-one
- **Git Worktree Isolation**: Each runner works in its own branch
- **Auto-commit**: Changes automatically committed with descriptive messages
- **Prompt Modifications**: Customize prompts per runner
- **Skip Conditions**: Conditionally skip initial prompts
- **Period-based Execution**: Control loop prompt frequency
- **File-based Exit**: Stop execution when marker file appears
- **Rate Limit Handling**: Automatic retry with backoff

## Examples

### Single Runner
```json
{
  "git_project_path": "../my-app",
  "initial_prompts": [
    {"name": "start", "prompt": "Create a React app"}
  ],
  "loop_prompts": [
    {"name": "develop", "prompt": "Add features", "period": 1}
  ],
  "max_loops": 3
}
```

### Multiple Approaches
```json
{
  "git_project_path": "../my-app",
  "execution_mode": "parallel",
  "runners": [
    {
      "name": "typescript",
      "prompt_modifications": {
        "append_to_all": " Use TypeScript."
      }
    },
    {
      "name": "javascript",
      "prompt_modifications": {
        "append_to_all": " Use JavaScript."
      }
    }
  ]
}
```

## Tips

- Keep prompts focused and specific
- Use skip conditions to avoid redundant operations
- Set appropriate max_loops to prevent infinite execution
- Review logs for debugging: `logs/runner-name-log.log`
- Clean up worktrees when done: `git worktree prune`