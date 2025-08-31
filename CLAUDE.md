# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

This project is a JSON-configurable bash script for orchestrating Claude CLI commands to build and develop projects iteratively. The script runs initial setup prompts, then continuously executes loop prompts with configurable periodicity until exit conditions are met.

## Prerequisites

- Claude CLI properly configured with `.claude/settings.json`
- `jq` JSON processor (usually pre-installed, or `brew install jq` / `sudo apt-get install jq`)
- Claude subagents: `story-architect`, `react-code-reviewer`

## Development Commands

- Make the script executable: `chmod +x multi-run.sh`
- Run multi-runner tasks: `./multi-run.sh my-config.json`
- Run single runner: `./multi-run.sh single-runner-config.json`
- Run test configuration: `./test-multi.sh`
- Edit configuration: Modify JSON config files
- View logs: `tail -f design/log.log` or `tail -f design/runner-name-log.log`
- Check errors: `cat design/error.log`

## Architecture

### Core Components

1. **multi-run.sh**: Self-contained orchestration script with integrated Claude execution
2. **Configuration files**: JSON files defining tasks, runners, and prompts
3. **design/**: Output directory for logs, stories, research, and state files
4. **Git worktrees**: Isolated working directories for each runner

### Configuration Structure

The JSON config supports:

- **Task object**: Single `task` object containing task definition and shared prompts
- **Runners array**: Array of `runners` with individual configurations at root level  
- **Global settings**: `max_loops`, `git_project_path`, `git_base_branch` at root level
- **Task-level prompts**: `initial_prompts`, `loop_prompts`, `exit_conditions`, `end_prompts` shared across runners
- **Runner-specific config**: `prompt_modifications` and `extra_prompts` for customization
- **Exit conditions**: File-based conditions with `name` and `file` properties
- **Prompt properties**: `name`, `prompt`, optional `period` for loop prompts, optional `skip_condition` for initial prompts

### Prompt Execution Flow

1. Initial prompts run sequentially (unless skipped)
2. Main loop executes, running prompts based on their period
3. Exit conditions checked after each prompt
4. End prompts run before final exit

### State Management

- Uses file-based state tracking (`design/TASKS_DONE`, `design/GAME_DONE`, etc.)
- Configurable retry logic with rate limit handling
- Comprehensive logging to `design/log.log`

## Multi-Runner System

The project now supports running multiple Claude instances on the same task to compare different approaches.

### Multi-Runner Commands

- Run multi-runner tasks: `./multi-run.sh multi-runner-config.json`
- Test multi-runner system: `./test-multi.sh`
- Cleanup worktrees and branches: `./cleanup-worktrees.sh`

### Multi-Runner Architecture

Each runner gets its own:
- **Git worktree**: Separate working directory
- **Git branch**: Named `task_name/runner_name`
- **Configuration**: Base config + runner-specific instructions
- **Log files**: Separate logs for each runner
- **Claude settings**: Automatic copy of `.claude/settings.json` to each worktree

### Configuration Structure

Multi-runner config supports inline prompt definition:

```json
{
  "task": {
    "name": "task_name",
    "description": "Task description", 
    "execution_mode": "sequential",
    "worktree_base_path": "../worktrees",
    
    "initial_prompts": [
      {
        "name": "setup", 
        "prompt": "Set up project",
        "skip_condition": "[ -f package.json ]"
      }
    ],
    "loop_prompts": [
      {
        "name": "work", 
        "prompt": "Do work", 
        "period": 1
      }
    ],
    "exit_conditions": [
      {
        "name": "exit_condition", 
        "file": "design/DONE"
      }
    ],
    "end_prompts": [
      {
        "name": "finalize", 
        "prompt": "Finalize"
      }
    ]
  },
  
  "runners": [
    {
      "name": "security_focused",
      "prompt_modifications": {
        "append_to_all": " Focus on security best practices.",
        "append_to_initial": " Establish secure foundations.",
        "append_to_loop": " Check for vulnerabilities.", 
        "append_to_final": " Perform security review."
      },
      "extra_prompts": {
        "initial_prompts": [{"name": "security_scan", "prompt": "Scan for issues"}],
        "loop_prompts": [{"name": "audit", "prompt": "Audit code", "period": 3}],
        "end_prompts": [{"name": "security_report", "prompt": "Create report"}]
      }
    }
  ],
  
  "git_project_path": "../my-project",
  "git_base_branch": "main", 
  "max_loops": 10
}
```

**Key Features:**
- **Task-level prompts**: `initial_prompts`, `loop_prompts`, `exit_conditions`, `end_prompts` defined in `task` object and shared across all runners
- **Runner-specific extras**: `extra_prompts` for runner-specific additional prompts  
- **Prompt modifications**: 4 different append options (`append_to_all`, `append_to_initial`, `append_to_loop`, `append_to_final`)
- **Merge behavior**: Task-level prompts + runner extra prompts + append modifications combined
- **Task definition**: Single `task` object with name, description, execution mode, worktree path
- **Execution modes**: `parallel` or `sequential`  
- **Worktree management**: Custom paths via `worktree_base_path` in task object
- **Global settings**: `max_loops`, `git_project_path`, `git_base_branch` at root level
- **Skip conditions**: Bash conditions in `skip_condition` for initial prompts

### Example Workflows

**Multi-Runner (Compare Approaches):**
1. Define task in config file like `configs/test-multi-runner-initial.json`
2. Specify runners with different approaches/focus areas in `runners` array
3. Run `./multi-run.sh configs/test-multi-runner-initial.json` to execute all runners
4. Compare results across different worktrees
5. Analyze branches to see different implementation paths

**Single-Runner (Traditional Usage):**
1. Use config file with single runner like `configs/test-submarine-game.json`
2. Run `./multi-run.sh configs/test-submarine-game.json` 
3. Results appear in single worktree

### Branch and Directory Structure

The multi-runner system supports flexible path configurations for both git projects and worktrees:

**Example with relative paths:**
```
multiclaude/
├── git-project/                    # Your git repository
│   ├── main branch (original)
│   ├── task_name/runner1_name branch
│   └── task_name/runner2_name branch  
├── git-project-worktrees/          # Created parallel to git project
│   ├── task_name_runner1_name/
│   └── task_name_runner2_name/
├── multi-run.sh                    # Multi-runner orchestrator
└── multi-runner-config.json        # Configuration
```

**Example with absolute paths:**
```
/path/to/
├── git-project/                    # Your git repository
│   ├── main branch (original)
│   ├── task_name/runner1_name branch
│   └── task_name/runner2_name branch  
├── git-project-worktrees/          # Created parallel to git project
│   ├── task_name_runner1_name/
│   └── task_name_runner2_name/
└── multiclaude/                    # Script location
    ├── multi-run.sh
    └── multi-runner-config.json
```

### Configuration Options

- **`git_project_path`**: Path to git repository - can be relative or absolute (**required parameter**)
- **`git_base_branch`**: Base branch that all runners will branch off from as their starting point (default: `"main"`)
- **`worktree_base_path`**: Where to create worktrees (default: `"worktrees"`)
  - If absolute path: used as-is
  - If relative path + git project is absolute: creates `{git_parent_dir}/{git_project_name}-{worktree_base_path}`
  - If relative path + git project is relative: uses relative path as-is

**Path Examples:**
- Git project: `/path/to/my-project`, worktree base: `"worktrees"` → `/path/to/my-project-worktrees/`
- Git project: `./my-project`, worktree base: `"worktrees"` → `./worktrees/`
- Git project: `/path/to/project`, worktree base: `"/custom/path"` → `/custom/path/`

### Prerequisites for Multi-Runner

1. Git repository at the path specified in `git_project_path` config (**required parameter**)
2. Initial commit on base branch specified in `git_base_branch` config (default: `"main"`)
3. Clean working directory (no uncommitted changes)
4. Sufficient permissions to create directories at the calculated worktree paths
5. `.claude/settings.json` file in the script directory (automatically copied to each worktree)