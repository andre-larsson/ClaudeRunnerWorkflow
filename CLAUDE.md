# MultiClaude

Run Claude CLI tasks in parallel with different contexts and compare results.

## Quick Start

```bash
# Simple parallel execution
./multi-simple.sh -p "Create a calculator app" -n 3

# With contexts (different "personalities")  
./generate-contexts.sh my-config.json
./multi-simple.sh my-config.json
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
  "runner_contexts": [
    "security-expert",
    {"name": "beginner", "description": "Patient mentor with clear explanations"},
    {"claudemd_file": "custom/path.md"}
  ]
}
```

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

## Prerequisites

- Claude CLI installed and configured
- `jq` JSON processor (`brew install jq` / `sudo apt-get install jq`)