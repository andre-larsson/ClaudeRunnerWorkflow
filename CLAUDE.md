# ClaudeRunnerWorkflow (CRW)

**Purpose:** Run Claude Code tasks in parallel with different contexts and compare results.

**For detailed usage instructions, examples, and scenarios, see [README.md](README.md)**

## Project Structure

```
ClaudeRunnerWorkflow/
├── generate-and-run.sh      # Main entry point - full workflow
├── generate-contexts.sh     # Generate CLAUDE.md context files  
├── claude-runner.sh         # Execute parallel Claude instances
├── configs/                 # Example configuration files
├── results/                 # Default output directory
└── runner-contexts/         # Generated CLAUDE.md context files
```

## Core Workflow

1. **Context Generation** (optional): `generate-contexts.sh config.json` → creates CLAUDE.md files
2. **Task Execution**: `claude-runner.sh config.json[.new]` → runs parallel Claude instances
3. **Combined**: `generate-and-run.sh config.json` → runs both steps

## Config File Format

```json
{
  "prompts": ["Create calculator", "Add styling", "Add tests"],
  "num_runners": 3,
  "task_name": "calculator-app",
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

### Parameter Usage by Script

**`generate-contexts.sh`:**
- Uses: `prompts` (required), `task_name`, `num_runners`, `runner_contexts` 
- Ignores: `max_parallel`, `base_directory`
- Auto-generates missing `task_name` and `runner_contexts`
- Outputs to: `./runner-contexts/` (hardcoded)

**`claude-runner.sh`:**
- Uses: `prompts` (required), all other parameters optional
- Defaults: `num_runners=3`, `base_directory=./results`, `max_parallel=num_runners`
- Filters out invalid `runner_contexts` paths
- Outputs to: `{base_directory}/{task_name}_{timestamp}/`

## Key Behaviors

**Context Generation:**
- Creates unique CLAUDE.md files with different AI personalities/approaches
- Uses existing `project_template/CLAUDE.md` as template when available
- Auto-generates creative contexts when `runner_contexts` not provided

**Task Execution:**
- Executes prompts sequentially within each runner
- Runs multiple runners in parallel (respects `max_parallel` limit)
- Auto-retries on rate limits (5 attempts, 1-hour delays)
- Copies `project_template/` contents to each runner workspace

**Output Structure:**
```
results/task-name_timestamp/
├── 00001_context-name/          # Runner workspace
│   ├── CLAUDE.md               # Runner's context
│   ├── status.txt              # completed|failed|running
│   └── logs/
│       ├── prompt_1_response.log
│       └── timing.log
└── config.json                 # Used configuration
```