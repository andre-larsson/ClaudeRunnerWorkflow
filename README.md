# ClaudeRunnerWorkflow (CRW)

Run Claude Code tasks in parallel with different contexts and compare results.

A task can consist of multiple prompts, carried out in sequence.

## Prerequisites

- Claude CLI installed and configured
- `jq` JSON processor


## Overview

- **generate-contexts.sh** - Generate CLAUDE.md context files for runners from config file
- **claude-runner.sh** - Run parallel Claude instances from config file
- **generate-and-run.sh** - Chain the two tools above into one command

## Security Considerations

- In order for the tool to work, Claude is given a substantial amount of permissions
- Permissions include: internet access, file system access, etc.
- Permissions are sent to claude via --allowedTools flag, which overrides ./claude/settings.json. Run at your own risk.
- Better to write your own scripts to run Claude, to know what it is doing.

## Run as command line tool

You can run claude-runner.sh directly from command line:

```bash
# Single prompt, 3 parallel runners
./claude-runner.sh -p "Create a calculator app" -n 3

# Multiple prompts in sequence, two runners run sequentially  
./claude-runner.sh -p "Create HTML" "Add CSS" "Add JavaScript" -n 2 -m 1

# With custom output directory
./claude-runner.sh -p "Build a web app" -n 5 -b ./my-results

# With project template
./claude-runner.sh -p "Refactor this code" -n 3 --template-directory ./my-project

# Print available options
./claude-runner.sh --help
```

For more control over contexts and behavior, use config files instead.

## With config file

### Minimal Workflow

#### Scenario
Create three ASCII art files with random styles using claude

#### Detailed Steps

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
./generate-and-run.sh configs/minimal.json
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

#### What Happens

1. **generate-contexts.sh** auto-generates:
   - Task name: `ascii-art` (from prompt)
   - 3 random contexts: `ascii-art-designer`, `creative-artist`, `minimalist-approach`
   - CLAUDE.md files with different personalities in `runner_contexts/` directory

2. **claude-runner.sh** runs 3 parallel Claude instances:
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

#### What Will Happen
- `generate-contexts.sh config.json` will generate 3 CLAUDE.md files based on the provided text strings and create a new config file.
- `claude-runner.sh config.json.new` will run 3 parallel Claude instances, each using a different context/personality (CLAUDE.md file). Reasonable defaults would be used for the rest of the config.
- `claude-runner.sh config.json` would run as above, but with `runner_contexts` ignored as no CLAUDE.md files were provided.


### Multi-Prompt Workflow

#### Scenario

Build a web calculator with additional instructions for error handling and unit tests, compare results from two different approaches. Run several tests of each approach for better sampling.

#### Config

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

#### What Will Happen
- `generate-contexts.sh config.json` will generate 2 CLAUDE.md files based on the provided text strings and create a new config file.
- `claude-runner.sh config.json.new` will run 5 parallel Claude instances, each executing the three prompts in sequence, each using a different context/personality (CLAUDE.md file) rotating through the two contexts in the order they are provided.
- `claude-runner.sh config.json` would run as above, but with no CLAUDE.md files for context, since no such files were provided.

#### Notes
- In this example, the three prompts could have been combined into one. However, results may vary.

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

#### What Will Happen
- `generate-contexts.sh config.json` will generate 2 CLAUDE.md files based on name, description, and the CLAUDE.md file in the project directory, and create a new config file.
- `claude-runner.sh config.json.new` will run a total of 5 Claude instances starting from a full copy of the project directory, only 2 will run simultaneously. Each will use a different context/personality (CLAUDE.md file) rotating through the two contexts in the order they are provided.
- `claude-runner.sh config.json` would run as above, but with default context from project directory, since even if runner_contexts exists, no CLAUDE.md files were provided.

### Start From Simple CLAUDE.md File

#### Scenario

A project idea is defined in a CLAUDE.md file, and we want to see how far claude can take this project.

#### Project idea in CLAUDE.md

Assume below file is saved to `./project_template/CLAUDE.md`. For the sake of this example, we keep content general and short to have claude come up with the ideas for the project.

```md
# Quest Seeker Online

Quest Seeker Online is a browser-based online game, where the user can join other players to go on quests for fame and glory.
```


#### Config

```json
{
  "prompts": [
    "Review the current state of the project and think about possible extensions. Update CLAUDE.md with most important tasks to do next.",// Including 'think' makes claude use thinking
    "Look at the most important tasks in CLAUDE.md and implement them.",
    // repeat the two prompts above ad infinitum, or until we run out of compute/money for running claude...
    "Review the current state of the project and think about possible extensions. Update CLAUDE.md with most important tasks to do next.",
    "Look at the most important tasks in CLAUDE.md and implement them.",
    "Review the current state of the project and think about possible extensions. Update CLAUDE.md with most important tasks to do next.",
    "<...repeat as many times as needed...>"
  ],
  "execution_mode": "parallel",
  "task_name": "big-game",
  "num_runners": 5,
}
```

#### What Will Happen
- `claude-runner.sh config.json` will run 5 parallel Claude instances, each starting from the CLAUDE.md file in the project directory, each running all prompts in sequence. At the end of the run, you should have five different,  fun(?) and not-crashing(?) web-based RPG games to enjoy.

### Parameters

See `generate-contexts.sh --help` and `claude-runner.sh --help` for available parameters.


## Notes

- If you have Claude Code with a subscription, you will of course eventually run into the rate-limit if you spawn enough runners.
- If this happens, claude-runner will wait for one hour and try again, five times, for each prompt, meaning your task should eventually complete, even if it takes a while.
- I'm not using git for version control of the runs, even though I imagine it would have been very useful. Unfortunately I found git+claude to be very buggy both in interactive and non-interactive mode. Permissions seem to be ignored, with claude just refusing to call git, when they work fine for other tools. Could be that claude code has their own git integration and github actions app, and this clashes with standard git in terminal window, or other way around? Pure speculation, might just be my configuration is wrong somewhere.
- This project was of course written with the help of claude code, guided by a human hand (promise).
- claude-runner.sh can start claude instances either in parallel or sequential, while generate-contexts.sh runs everything after each other.
