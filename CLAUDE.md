# CLAUDE.md

Multi-runner orchestration system for Claude CLI tasks.

## 🚀 **Quick Start** (Most Users)

```bash
# Simple parallel execution
./multi-simple.sh -p "Create a calculator app" -n 3

# Multiple prompts in sequence  
./multi-simple.sh -p "Create HTML" "Add CSS" "Add JavaScript" -n 2

# With config file
./multi-simple.sh configs/simple/my-task.json
```

## 📊 **Tool Comparison**

| | **multi-simple.sh** | **multi-run.sh** |
|---|---|---|
| **Best For** | Quick experiments, A/B testing | Production workflows, complex automation |
| **Git Integration** | ❌ None | ✅ Worktrees + branches + auto-commit |
| **Complexity** | Simple prompt sequences | Advanced looping + conditions + modifications |
| **Learning Curve** | 5 minutes | 30 minutes |
| **Use Cases** | • Test different approaches<br>• Compare solutions<br>• Quick prototyping | • Multi-step workflows<br>• Branch-based development<br>• Complex orchestration |

## 🎯 **Which Tool Should I Use?**

**Choose `multi-simple.sh` if you want to:**
- Quickly test how Claude handles the same task differently
- Compare multiple approaches side-by-side
- Run simple sequences without git complexity
- Get started immediately

**Choose `multi-run.sh` if you need:**
- Git integration with branches and commits
- Complex multi-step workflows with conditions
- Loop-based execution with break conditions
- Advanced prompt modifications per runner

---

# multi-simple.sh - Quick Parallel Testing

**Perfect for:** Experimenting, comparing approaches, quick prototyping

## Features
- ✅ **CLI or Config**: Use command line flags or JSON config files
- ✅ **Prompt Sequences**: Single prompts or multi-step sequences  
- ✅ **Parallel Control**: Control how many run simultaneously
- ✅ **Context Support**: Different "personalities" per runner
- ✅ **Template Support**: Start from existing code
- ✅ **No Git Required**: Pure directory-based execution

## Usage Modes

### **Command Line (Recommended)**
```bash
# Single prompt, multiple runners
./multi-simple.sh -p "Create a calculator app" -n 3

# Multi-step sequence
./multi-simple.sh -p "Create HTML" "Add CSS" "Add JavaScript" -n 2 -m 1

# With different contexts/personalities
./multi-simple.sh -p "Build auth system" -n 3 \
  -c "security:runner-contexts/security-focused/CLAUDE.md" \
  -c "beginner:runner-contexts/beginner-friendly/CLAUDE.md"
```

### **Config File Mode**
```json
{
  "prompts": ["Create calculator", "Add styling", "Add tests"],
  "num_runners": 3,
  "max_parallel": 2,
  "runner_contexts": [
    {"name": "security", "claudemd_path": "runner-contexts/security-focused/CLAUDE.md"}
  ]
}
```

## CLI Options
- `-p, --prompts "p1" "p2" ...` - Prompts to execute (required)
- `-n, --num-runners N` - Number of runners (default: 3)
- `-m, --max-parallel N` - Max concurrent runners 
- `-t, --task-name NAME` - Custom task name
- `-c, --runner-context "name:path"` - Context files (repeatable)
- `--template-directory PATH` - Starter code to copy

## Output Structure
```
results/task-name/
├── runner_1/
│   ├── CLAUDE.md           # Context (if used)
│   ├── prompt_1.log        # First prompt output
│   ├── prompt_2.log        # Second prompt output
│   ├── timing.log          # Execution timing
│   └── status.txt          # completed/failed
└── index.md               # Summary of all runs
```

---

# multi-run.sh - Advanced Git Workflows

**Perfect for:** Production automation, complex workflows, git-based development

## Features
- ✅ **Git Integration**: Automatic worktrees, branches, and commits
- ✅ **Advanced Looping**: Conditional loops with break conditions
- ✅ **Prompt Modifications**: Runner-specific prompt customization
- ✅ **Skip Conditions**: Conditional execution logic
- ✅ **Rate Limit Handling**: Automatic retry with backoff
- ✅ **Branch Management**: Each runner gets its own git branch

## Prerequisites
- `jq` JSON processor
- Git repository for target project
- More complex setup and configuration

## Quick Start
```bash
./multi-run.sh configs/full/workflow-config.json
```

For detailed documentation of the full version, see the existing configuration files in `configs/` and the library documentation.

---

## 🔧 **Setup & Prerequisites**

### Both Tools Require:
- Claude CLI installed and configured
- `jq` JSON processor (`brew install jq` / `sudo apt-get install jq`)

### Simple Tool Only:
- Just run from any directory
- No additional setup needed

### Full Tool Additionally Needs:
- Git repository for target project  
- Understanding of git worktrees and branches

## 💡 **Tips**

- **Start with `multi-simple.sh`** - Most users find it meets their needs
- **Use contexts** for testing different approaches (security-focused vs beginner-friendly)
- **Check the logs** while running: `tail -f results/*/runner_*/prompt_*.log`
- **Generate contexts** with `./generate-contexts.sh` for common personalities

## 📁 **Project Structure**
```
multiclaude/
├── multi-simple.sh              # 👈 Start here (simple parallel runner)
├── multi-run.sh                 # Advanced git-based workflows
├── generate-contexts.sh         # Create personality contexts
├── configs/
│   └── simple/                  # Simple runner configs
├── runner-contexts/             # Pre-built contexts (security, performance, etc.)
└── examples/                    # Usage examples
```