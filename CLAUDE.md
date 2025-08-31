# CLAUDE.md

Multi-runner orchestration system for Claude CLI tasks using JSON configuration.

## Project Purpose

JSON-configurable bash script that orchestrates Claude CLI commands for iterative development. Supports multiple runners working on the same task with different approaches for comparison.

## Prerequisites

- Claude CLI configured with `.claude/settings.json`
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

## Configuration Structure

All config files should be saved in `configs/` directory. The JSON uses a flattened structure:

```json
{
  "task_name": "my_task",
  "task_description": "Description of what this task does",
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
  "exit_conditions": [
    {
      "name": "done", 
      "file": "design/COMPLETE"
    }
  ],
  "end_prompts": [
    {
      "name": "finalize",
      "prompt": "Clean up and summarize"
    }
  ],
  
  "runners": [
    {
      "name": "main_approach",
      "prompt_modifications": {
        "append_to_all": " Focus on maintainability."
      }
    }
  ]
}
```

### Configuration Properties

**Required:**
- `task_name`: Unique task identifier
- `git_project_path`: Path to target git repository
- `runners`: Array of runner configurations

**Optional:**
- `task_description`: Task description (default: "No description provided")
- `git_base_branch`: Base branch for runners (default: "main") 
- `worktree_base_path`: Worktree directory (default: "worktrees")
- `execution_mode`: "sequential" or "parallel" (default: "sequential")
- `max_loops`: Maximum loop iterations (default: 10)

### Prompts

**Prompt Types:**
- `initial_prompts`: Run once at start (supports `skip_condition`)
- `loop_prompts`: Run repeatedly (supports `period` for frequency)
- `exit_conditions`: File-based exit triggers (`name`, `file`)  
- `end_prompts`: Run once before exit

**Runner Customization:**
- `prompt_modifications`: Append text to prompts (`append_to_all`, `append_to_initial`, `append_to_loop`, `append_to_final`)
- `extra_prompts`: Add runner-specific prompts

## Example Configs

**Single Runner:**
```bash
./multi-run.sh configs/single-runner-config.json
```

**Multiple Runners (Compare Approaches):**
```bash  
./multi-run.sh configs/multi-runner-config.json
```

**Parallel Execution:**
```bash
./multi-run.sh configs/parallel-runners-config.json
```

## Architecture

**Each runner gets:**
- Separate git worktree and branch (`task_name/runner_name`)
- Individual log files (`logs/runner-name-log.log`)
- Merged configuration (shared + runner-specific prompts)

**Directory Structure:**
```
project/
├── multiclaude/
│   ├── multi-run.sh
│   └── configs/
├── my-project/                    # Target git repo
│   ├── main (original)
│   └── task_name/runner_name      # Runner branches
└── my-project-worktrees/          # Runner worktrees  
    └── task_name_runner_name/
```

## Execution Flow

1. **Setup**: Create worktrees and branches for each runner
2. **Initial**: Run initial prompts (with skip conditions)
3. **Loop**: Execute loop prompts based on period until max_loops or exit condition
4. **Exit**: Run end prompts and cleanup
5. **Commit**: Auto-commit all changes with descriptive messages

## Advanced Features

- **Skip conditions**: Bash conditions for initial prompts
- **Period-based execution**: Loop prompts run every N iterations
- **Rate limit handling**: Automatic retry with backoff
- **Parallel/sequential modes**: Run runners simultaneously or one-by-one
- **Flexible paths**: Relative/absolute paths for projects and worktrees
- **Auto-commit**: Changes committed with context-rich messages