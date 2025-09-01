# ClaudeRunnerWorkflow (CRW)

Run Claude Code tasks in parallel with different contexts and compare results. See README.md for user instructions. 

## Quick Start

```bash
# Full workflow (one command)
echo '{"prompts": ["Create file file1.txt with ASCII art"], "num_runners": 3}' > minimal.json
./generate-and-run.sh minimal.json

# Manual steps
./generate-contexts.sh my-config.json
./claude-runner.sh my-config.json.new

# Command line mode
./claude-runner.sh -p "Create a calculator app" -n 3
```

## Tools

- **generate-and-run.sh** - One command for the full workflow (start here)
- **claude-runner.sh** - Run parallel Claude instances
- **generate-contexts.sh** - Generate CLAUDE.md context files

## Config File Format

```json
{
  "prompts": ["Create calculator", "Add styling", "Add tests"],
  "num_runners": 3,
  "task_name": "calculator-app",
  "execution_mode": "parallel",
  "max_parallel": 2,
  "project_template": "./my_project",
  "base_directory": "./results", 
  "runner_contexts": [
    "security-expert",
    {"name": "beginner", "description": "Patient mentor with clear explanations"},
    {"claudemd_file": "custom/path.md"}
  ]
}
```

**Required Fields:**
- **`prompts`** - Array of prompts to execute in sequence

**Optional Fields:**
- **`task_name`** - Auto-generated from prompts if not provided
- **`num_runners`** - Number of parallel instances (default: 1)
- **`execution_mode`** - "parallel" or "sequential" (default: parallel)
- **`max_parallel`** - Limit simultaneous runs
- **`project_template`** - Copy from existing directory
- **`base_directory`** - Output directory (default: ./results)
- **`runner_contexts`** - Auto-generated random contexts if not provided

## Usage Examples

### Minimal Example
```bash
echo '{"prompts": ["Create file file1.txt with ASCII art"], "num_runners": 3}' > minimal.json
./generate-and-run.sh minimal.json
ls results/*/  # Check the generated directories
```

### With Custom Contexts
```bash
# Config with specific contexts
echo '{
  "prompts": ["Build a web calculator"],
  "runner_contexts": ["security expert", "performance optimizer", "accessibility focused"]
}' > calculator.json

./generate-and-run.sh calculator.json
```

### Multi-Prompt Workflow
```bash
echo '{
  "prompts": [
    "Create a calculator function",
    "Add error handling", 
    "Write unit tests"
  ],
  "num_runners": 3,
  "runner_contexts": ["TDD approach", "defensive programming"]
}' > multi-step.json

./generate-and-run.sh multi-step.json
```

## How It Works

1. **Context Generation**: `generate-contexts.sh` creates CLAUDE.md files for each runner context
2. **Parallel Execution**: `claude-runner.sh` runs multiple Claude instances simultaneously  
3. **Result Organization**: Each run gets a numbered directory (`00001_context-name/`)

### Auto-Generation
- **Missing `task_name`?** Generated from prompts using Claude
- **Missing `runner_contexts`?** Random contexts generated based on prompts

Example minimal config:
```json
{"prompts": ["Build a REST API"], "num_runners": 3}
```

Results in directories like:
- `00001_api-security-expert/`
- `00002_performance-optimizer/` 
- `00003_documentation-focused/`

## Prerequisites

- Claude CLI installed and configured
- `jq` JSON processor (`brew install jq` / `sudo apt-get install jq`)

## Built-in Resilience Features

The system includes automatic handling for common issues:

**Rate Limit Handling:**
- Detects rate limit messages in Claude output
- Automatically waits 1 hour before retrying (configurable)
- Attempts up to 5 retries per prompt (configurable)
- Tasks eventually complete even with rate limits

**Worker Spawn Management:**
- 3-second delay between spawning workers (configurable)
- Prevents system overload during startup

**Customization:**
Edit the constants at the top of `claude-runner.sh`:
```bash
DEFAULT_MAX_RETRIES=5          # Max retry attempts for rate limits
DEFAULT_RETRY_DELAY=3600       # Seconds to wait between retries (1 hour)
WORKER_SPAWN_DELAY=3           # Seconds to wait between spawning workers
```

## Security Warning

Claude is given substantial permissions including internet access and file system access via `--allowedTools` flag. Use at your own risk. Review scripts before running to understand what they do.