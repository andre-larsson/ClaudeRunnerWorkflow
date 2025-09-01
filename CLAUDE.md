# MultiClaude

Run Claude CLI tasks in parallel with different contexts and compare results.

## Quick Start

```bash
# Simple parallel execution
./multi-simple.sh -p "Create a calculator app" -n 3

# With contexts (different "personalities")  
./generate-contexts.sh my-config.json
./multi-simple.sh my-config.json

# Minimal config (auto-generates everything)
echo '{"prompts": ["Build a web app"], "num_runners": 3}' > minimal.json
./generate-contexts.sh minimal.json
./multi-simple.sh minimal.json.new
```

## Tools

- **multi-simple.sh** - Quick parallel testing (start here)
- **generate-contexts.sh** - Create context files for different approaches
- **multi-run.sh** - Advanced git workflows (complex projects)

## Config File Format

```json
{
  "prompts": ["Create calculator", "Add styling", "Add tests"],
  "num_runners": 3,
  "task_name": "calculator-app",
  "runner_contexts": [
    "security-expert",
    {"name": "beginner", "description": "Patient mentor with clear explanations"},
    {"claudemd_file": "custom/path.md"}
  ]
}
```

**Optional Fields:**
- **`task_name`** - Auto-generated from prompts if not provided
- **`runner_contexts`** - Auto-generated random contexts using `num_runners` if not provided

## CLI Usage

```bash
# Command line mode  
./multi-simple.sh -p "Create a calculator app" -n 3

# Config file mode (recommended for contexts)
./multi-simple.sh my-config.json

# Generate contexts first
./generate-contexts.sh my-config.json
./multi-simple.sh my-config.json
```

## Automatic Generation

**Missing `task_name`?** Auto-generated from prompts using Claude
**Missing `runner_contexts`?** Auto-generated random contexts based on prompts

```json
{
  "prompts": ["Build a REST API"],
  "num_runners": 3
}
```

**Results in directories like:**
- `00001_api-security-expert/`
- `00002_performance-optimizer/` 
- `00003_documentation-focused/`

## Prerequisites

- Claude CLI installed and configured
- `jq` JSON processor (`brew install jq` / `sudo apt-get install jq`)