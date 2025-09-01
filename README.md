# ClaudeRunnerWorkflow

Run Claude Code tasks in parallel with different contexts and compare results.

A task can consist of multiple prompts, carried out in sequence.

## Prerequisites

- Claude CLI installed and configured
- `jq` JSON processor


## Security Considerations

- In order for the tool to work, Claude is given a substantial amount of permissions
- Permissions include: internet access, file system access, etc.
- Use at your own risk.
- Better to write your own scripts to run Claude, to know what it is doing.


## Minimal Workflow

### Scenario
Create three ASCII art files with random styles using claude

### Detailed Seps

**1. Config file:**
```bash
cat configs/minimal.json
```
```json
{
  "prompts": ["Create file file1.txt with ASCII art of your choice and exit."],
  "num_runners": 3
}
```

**2. Run it:**
```bash
./generate_and_run.sh configs/minimal.json
```

**3. Check results:**
```bash
ls results/*/
# 00001_ascii-art-designer/  00002_creative-artist/  00003_minimalist-approach/

cat results/*/00001_*/file1.txt
# Shows first approach's ASCII art

cat results/*/00002_*/file1.txt  
# Shows second approach's ASCII art

cat results/*/00003_*/file1.txt
# Shows third approach's ASCII art
```

### What Happens

1. **generate-contexts.sh** auto-generates:
   - Task name: `ascii-art` (from prompt)
   - 3 random contexts: `ascii-art-designer`, `creative-artist`, `minimalist-approach`
   - CLAUDE.md files with different personalities in `runner_contexts/` directory

2. **multi-simple.sh** runs 3 parallel Claude instances:
   - Each gets the same prompt
   - Each uses a different context/personality (CLAUDE.md files)
   - Each produces different results
   - Directory names: `00001_<context-name>/`, `00002_<context-name>/`, etc.


## Specify Your Own Contexts

### Scenario

Build a web calculator, compare results from three different approaches

### Config

```json
{
  "prompts": ["Build a web calculator"],
  "runner_contexts": [
    "security expert",
    "performance optimizer", 
    "accessibility focused"
  ]
}
```

### What Will Happen
- `generate-contexts.sh config.json` will generate 3 CLAUDE.md files based on the provided text strings and create a new config file.
- `multi-simple.sh config.json.new` will run 3 parallel Claude instances, each using a different context/personality (CLAUDE.md file). Reasonable defaults would be used for the rest of the config.
- `multi-simple.sh config.json` would run as above, but with `runner_contexts` ignored as no CLAUDE.md files were provided.

### Notes
- In this example, the three prompts could probably have been combined into one, but sometimes its better to run multiple focused claude instances after each other than one with long instructions. Results may vary.

## Multi-Prompt Workflow

### Scenario

Build a web calculator with additional instructions for error handling and unit tests, compare results from two different approaches. Run several tests of each approach for better sampling.

### Config

```json
{
  "prompts": [
    "Create a calculator function",
    "Add error handling",
    "Write unit tests"
  ],
  "num_runners": 5,
  "task_name": "calculator-development",
  "runner_contexts": ["TDD approach", "defensive programming"]
}
```

### What Will Happen
- `generate-contexts.sh config.json` will generate 2 CLAUDE.md files based on the provided text strings and create a new config file.
- `multi-simple.sh config.json.new` will run 5 parallel Claude instances, each using a different context/personality (CLAUDE.md file) rotating through the two contexts in the order they are provided.
- `multi-simple.sh config.json` would run as above, but with no CLAUDE.md files for context, since no such files were provided.

## Run from existing project
```json
{
  "prompts": ["Review the codebase and look for bugs and security vulnerabilities"], // required
  "execution_mode": "parallel", // optional
  "task_name": "code-review", // optional
  "num_runners": 5, // optional
  "max_parallel": 2, // optional
  "project_template": "./my_project", // optional. Since provided, generate-contexts.sh will look for a CLAUDE.md file in ./my_project/ and use it as a basis for the context
  "base_directory": "./my_results", // optional
  "runner_contexts": [
    // optional
    {
      "name": "security-auditor",
      "description": "Focus on security vulnerabilities and best practices" 
    },
    {
      "name": "performance-reviewer",
      "description": "Focus on performance optimization and efficiency"  
    }
  ]
}
```

### What Will Happen
- `generate-contexts.sh config.json` will generate 2 CLAUDE.md files based on name, description, and the CLAUDE.md file in the project directory, and create a new config file.
- `multi-simple.sh config.json.new` will run a total of 5 Claude instances starting from a full copy of the project directory, only 2 will run simultaneously. Each will use a different context/personality (CLAUDE.md file) rotating through the two contexts in the order they are provided.
- `multi-simple.sh config.json` would run as above, but with default context from project directory, since even if runner_contexts exists, no CLAUDE.md files were provided.

## Start From Simple CLAUDE.md File

### Scenario

I have a project idea defined in my CLAUDE.md file, and want to test the limits of claude for this example.

### CLAUDE.md

Assume file is saved to `project_template/CLAUDE.md`. Keep content general to have claude come up with the ideas for the project.

```md
# Quest Seeker Online

Quest Seeker Online is browser based online game, where the user can join other players to go on quests for fame and glory.
```


### Config

```json
{
  "prompts": [
    "Review the current state of the project and think about possible extensions. Update CLAUDE.md with most important tasks to do next.", 
    // Including 'think' makes claude think harder

    "Look at the most important tasks in CLAUDE.md and implement them.",
    // now we can repeat the two prompts above as much as we want or until our pockets are empty (due to cost of running claude)
    "Review the current state of the project and think about possible extensions. Update CLAUDE.md with most important tasks to do next.",
    "Look at the most important tasks in CLAUDE.md and implement them.",
    "Review the current state of the project and think about possible extensions. Update CLAUDE.md with most important tasks to do next.",
    "Look at the most important tasks in CLAUDE.md and implement them.",
    "<...repeat as many times as needed...>"
  ],
  "execution_mode": "parallel",
  "task_name": "big-game",
  "num_runners": 5,
}
```

### What Will Happen
- `multi-simple.sh config.json` will run 5 parallel Claude instances, each starting from the CLAUDE.md file in the project directory. At the end of the run, you should have five fun(?) and not-crashing(?) web-based RPG games to enjoy.

## Parameters

See `generate-contexts.sh --help` and `multi-simple.sh --help` for available parameters and their defaults.

## Notes
- For long complex instructions, instead of splitting them into multiple prompts, add a TODO list with detailed instructions to CLAUDE.md.
- Repeat prompts to force claude to continue even if it thinks its finished.


## Tools

- **generate_and_run.sh** - One command for the full workflow
- **generate-contexts.sh** - Generate CLAUDE.md context files
- **multi-simple.sh** - Run parallel Claude instancesJSON processor