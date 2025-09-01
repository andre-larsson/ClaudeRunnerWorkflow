# MultiClaude Workflow Guide

A complete guide for using `generate-contexts.sh` and `multi-simple.sh` together to run parallel Claude instances with different contexts and compare their outputs.

## Quick Start

**Create a simple configuration file:**

**File: `configs/my-test.json`**
```json
{
  "prompts": [
    "Create a simple web page with a text input. When the user presses a button, convert the text to pig latin."
  ],
  "num_runners": 3,
  "runner_contexts": [
    "minimalist approach",
    "security first",
    "numerology expert"
  ]
}
```

**Run the workflow:**
```bash
# 1. Create simple config as above
# 2. Generate the contexts 
# 3. Run parallel tests with multiple Claude instances
./generate-contexts.sh configs/my-test.json
./multi-simple.sh configs/my-test.json.new
```

## Complete Workflow Example

### Step 1: Create Configuration

**File: `configs/calculator.json`**
```json
{
  "prompts": [
    "Create a calculator function that adds two numbers",
    "Add error handling",
    "Add unit tests"
  ],
  "num_runners": 3,
  "runner_contexts": [
    "defensive programmer",
    "minimalist coder",
    "enterprise developer"
  ]
}
```

### Step 2: Generate Contexts

```bash
$ ./generate-contexts.sh configs/calculator.json
```

**What happens during context generation:**

The `generate-contexts.sh` script processes your configuration and:

1. **Validates the config file** and checks for required tools (jq, claude CLI)
2. **Normalizes string contexts** by calling Claude to generate 1 to 3-word kebab-case names (e.g., "defensive programmer" becomes "defensive-programmer-approach")
3. **Creates a new config** file at `configs/calculator.json.new` with complete file paths to generated CLAUDE.md context files
4. **Generates context directories** under `runner-contexts/` for each context name
5. **Creates CLAUDE.md files** by calling Claude with prompts that include:
   - If the context is a string, the string will be included. If the context is an object, name and description will be included
   - The task prompts
   - Instructions to create comprehensive context files with priorities, guidelines, code style, and review checklists
   - Any project template found at `project_template/CLAUDE.md` if it exists (optional)
6. **Summarizes progress** including how many contexts were generated, skipped (if already exist), or failed

**Files created:**
- `configs/calculator.json.new` - New config with complete paths to generated CLAUDE.md context files
- `runner-contexts/{context-name}/CLAUDE.md` - Individual context files for each approach
- Original config file remains unchanged

### Step 3: Run Parallel Claude Instances

```bash
$ ./multi-simple.sh configs/calculator.json.new
```

**What happens during execution:**

The `multi-simple.sh` script orchestrates the parallel execution:

1. **Creates a timestamped run directory** under `./results/` using format `{task-name}_{timestamp}`
2. **Sets up runner directories** for each parallel instance with:
   - Copies of any template directory specified
   - The appropriate CLAUDE.md context file for that runner
   - Info files tracking which context and configuration is being used
3. **Executes prompts sequentially** for each runner, with each prompt building on the previous work
4. **Runs multiple runners in parallel** (up to the max_parallel limit) or sequentially based on execution_mode
5. **Captures all output** to individual log files per prompt per runner
6. **Tracks timing and status** for each runner and prompt
7. **Creates summary files** including a README.md with status tables and an index entry

**Files created:**
- `results/{task-name}_{timestamp}/runner_{N}/` - Individual working directories for each runner
- `results/{task-name}_{timestamp}/runner_{N}/prompt_{N}.log` - Output from each prompt execution
- `results/{task-name}_{timestamp}/runner_{N}/status.txt` - Final status (completed/failed/timeout)
- `results/{task-name}_{timestamp}/runner_{N}/timing.log` - Start and end times
- `results/{task-name}_{timestamp}/runner_{N}/info.txt` - Runner configuration details
- `results/{task-name}_{timestamp}/config.json` - Configuration used for this ensemble of runners
- `results/{task-name}_{timestamp}/execution.log` - Overall timing information
- `results/{task-name}_{timestamp}/README.md` - Summary with status table
- `results/index.md` - Master index of all runs

### Step 4: Compare Results

The results are organized in a structured directory tree where you can compare the different approaches:

```bash
$ tree results/calculator_20241231_143022/
```

**Directory structure created:**
```
results/calculator_20241231_143022/
├── config.json              # Configuration used
├── execution.log            # Overall timing
├── README.md                # Run summary with status table
├── runner_1/                # Defensive programmer approach
│   ├── info.txt             # Runner details
│   ├── status.txt           # completed/failed/timeout
│   ├── timing.log           # Start/end times
│   ├── prompt_1.log         # Calculator creation output
│   ├── prompt_2.log         # Error handling added
│   ├── prompt_3.log         # Tests added
│   └── [generated files]    # Actual code created
├── runner_2/                # Minimalist coder approach
│   └── [same structure]
└── runner_3/                # Enterprise developer approach
    └── [same structure]
```

## Configuration Examples

### 1. Simple String Contexts (Fastest Setup)

**File: `configs/quick-test.json`**
```json
{
  "prompts": ["Write a Python calculator function"],
  "num_runners": 3,
  "runner_contexts": [
    "security focused",
    "performance optimized", 
    "beginner friendly"
  ]
}
```

**What happens when you run:**
```bash
$ ./generate-contexts.sh configs/quick-test.json
```

**Process description:**
1. **Context name generation**: Claude converts each string into a 1 to 3-word kebab-case directory name:
   - "security focused" becomes something like "secure-code-practices"
   - "performance optimized" becomes something like "fast-efficient-algorithms"
   - "beginner friendly" becomes something like "simple-clear-explanations"

2. **File structure created**:
   - `runner-contexts/{generated-name}/CLAUDE.md` for each context
   - `configs/quick-test.json.new` with normalized context paths
   - Original config file remains unchanged

3. **Context content**: Each CLAUDE.md file contains detailed guidance tailored to the string description, including priorities, coding style, and review checklists specific to that approach.

### 2. Mixed String and Object Contexts

**File: `configs/mixed-contexts.json`**
```json
{
  "prompts": [
    "Create a REST API endpoint",
    "Add input validation",
    "Write unit tests"
  ],
  "num_runners": 3,
  "task_name": "api-development",
  "runner_contexts": [
    "enterprise architect",
    {
      "name": "startup-dev",
      "description": "Move fast, ship quickly, iterate based on feedback"
    },
    {
      "name": "tdd-expert", 
      "description": "Test-driven development with 100% coverage"
    }
  ]
}
```

**Processing behavior:**
- **String contexts** (like "enterprise architect") get auto-generated directory names via Claude and basic context files
- **Object contexts with descriptions** get custom-tailored CLAUDE.md files based on their specific descriptions
- **Object contexts with names only** get auto-paths like `runner-contexts/{name}/CLAUDE.md`
- All contexts reference the task prompts for relevance and the task_name for specialization

**Generated structure:**
```
runner-contexts/
├── {generated-name-for-enterprise-architect}/CLAUDE.md
├── startup-dev/CLAUDE.md
└── tdd-expert/CLAUDE.md
```

### 3. Using a Base Template

**File: `project_template/CLAUDE.md`**
```markdown
# Project Context

## Core Principles
- Write clean, maintainable code
- Follow project conventions
- Include error handling

## Output Format
- Use clear variable names
- Add minimal comments
- Structure code logically
```

**Template behavior:**
```bash
# Template automatically detected and used for all contexts
$ ./generate-contexts.sh configs/my-config.json

# Or specify a custom template
$ ./generate-contexts.sh configs/my-config.json --template templates/strict.md
```

**How templates work:**
- If `project_template/CLAUDE.md` exists, it's automatically used as the base for all generated contexts
- Custom templates can be specified with `--template` flag
- Generated contexts inherit the template's structure and adapt the content to match their specific role
- Template provides consistency across all contexts while maintaining their unique characteristics

### 4. Fast Iteration Workflow

**File: `configs/iterate-fast.json`**
```json
{
  "prompts": ["Build a todo app component"],
  "num_runners": 3,
  "runner_contexts": [
    "react hooks only",
    "class components", 
    "vanilla javascript"
  ]
}
```

**Iteration workflow process:**
```bash
# 1. Dry run to preview what will be created
./generate-contexts.sh configs/iterate-fast.json --dry-run

# 2. Generate contexts
./generate-contexts.sh configs/iterate-fast.json

# 3. Run tests
./multi-simple.sh configs/iterate-fast.json.new

# 4. Modify and regenerate specific contexts
# <manual edit of configs/iterate-fast.json>
./generate-contexts.sh configs/iterate-fast.json --force

# 5. Run again with new contexts
./multi-simple.sh configs/iterate-fast.json.new
```

**Workflow benefits:**
- **Dry run** shows you what contexts and files would be created without actually calling Claude
- **Force regeneration** allows you to update contexts after modifying your config
- **Reuse existing contexts** that haven't changed to save time
- **Iterative refinement** lets you improve your contexts based on results

## Different Config Scenarios & Results

### Scenario 1: ASCII Art Generation

**Config: `configs/ascii-art.json`**
```json
{
  "prompts": [
    "Create ASCII art of a cat",
    "Add animation frames"
  ],
  "num_runners": 1,
  "runner_contexts": [
    "minimalist artist",
    "detailed designer",
    "emoji lover"
  ]
}
```

**Expected results:**
```bash
$ ./generate-contexts.sh configs/ascii-art.json && ./multi-simple.sh configs/ascii-art.json.new
```

**What each context produces:**
- **Minimalist artist context**: Creates simple, clean ASCII art with minimal lines and basic shapes
- **Detailed designer context**: Produces complex, elaborate ASCII art with intricate details and shading
- **Emoji lover context**: Uses Unicode characters, emojis, and creative symbols to represent the subject

**Output structure:**
```
results/ascii-art_20241231_143022/
├── runner_1/  # minimalist-artist approach
├── runner_2/  # detailed-designer approach
└── runner_3/  # emoji-lover approach
```

Each runner directory contains the generated art files, animation frames, and execution logs showing the creative process.

### Scenario 2: Bug Fix Approaches

**Config: `configs/bugfix.json`**
```json
{
  "prompts": ["Fix: User login fails after password reset"],
  "num_runners": 3,
  "execution_mode": "parallel",
  "runner_contexts": [
    "database expert",
    "frontend developer", 
    "security analyst"
  ]
}
```

**Investigation process:**
```bash
$ ./multi-simple.sh configs/bugfix.json.new
```

**What each context investigates:**
- **Database expert context**: Examines session tables, password hash storage, database constraints, and transaction integrity
- **Frontend developer context**: Reviews form validation, cookie handling, API request flow, and user interface state management  
- **Security analyst context**: Analyzes token expiration, CSRF protection, authentication workflows, and potential security vulnerabilities

**Parallel execution benefits:**
- Each runner approaches the problem from their domain expertise
- Different root causes and solutions are identified simultaneously
- Results provide a comprehensive view of potential issues
- Time-efficient compared to sequential investigation

**Output analysis:**
Each runner's logs reveal different aspects of the problem, allowing you to compare diagnostic approaches and potentially discover multiple contributing factors to the login failure.

### Scenario 3: Sequential Development

**Config: `configs/sequential-build.json`**
```json
{
  "prompts": [
    "Create a React component for user profile",
    "Add state management",
    "Connect to API",
    "Add loading and error states"
  ],
  "num_runners": 1,
  "execution_mode": "sequential",
  "runner_contexts": [
    {"name": "react-expert", "description": "Modern React with hooks and TypeScript"}
  ]
}
```

**Sequential development process:**
```bash
$ ./multi-simple.sh configs/sequential-build.json.new
```

**How sequential execution works:**
1. **Single runner processes all prompts** in order within the same working directory
2. **Each prompt builds on previous work**, allowing iterative development
3. **Files are modified and extended** rather than created from scratch each time
4. **Context is preserved** between prompts, maintaining consistency

**Development progression:**
- **Prompt 1**: Creates initial React component structure with basic JSX
- **Prompt 2**: Adds useState hooks and state management logic to existing component
- **Prompt 3**: Integrates API calls using useEffect and creates service files
- **Prompt 4**: Enhances component with loading spinners, error handling, and user feedback

**Final output structure:**
```
results/sequential-build_20241231_143022/
└── runner_1/
    ├── prompt_1.log     # Component creation
    ├── prompt_2.log     # State management added
    ├── prompt_3.log     # API integration
    ├── prompt_4.log     # Error handling added
    ├── UserProfile.tsx  # Final complete component
    └── api/
        └── userService.ts  # API service files
```

**Benefits of sequential mode:**
- Maintains development context across prompts
- Allows for iterative refinement of the same codebase
- Produces a cohesive final result rather than separate implementations

## Interpreting and Comparing Results

### Using diff to compare approaches:
```bash
# Compare two implementations
diff results/calculator_*/prompt_1/defensive-programmer/calculator.py \
     results/calculator_*/prompt_1/minimalist-coder/calc.py

# See all approaches side by side
for dir in results/calculator_*/prompt_1/*/; do
    echo "=== $(basename $dir) ==="
    head -20 $dir/*.py 2>/dev/null || head -20 $dir/*.java 2>/dev/null
done
```

### Finding the best solution:
```bash
# Run tests on all implementations
for dir in results/calculator_*/prompt_3/*/; do
    echo "Testing $(basename $dir)..."
    cd $dir && python -m pytest test_*.py
done

# Check code size
wc -l results/calculator_*/prompt_1/*/*.{py,java} 2>/dev/null
```

### Creating a combined solution:
```bash
# Cherry-pick best parts from each approach
mkdir results/combined
cp results/calculator_*/prompt_1/minimalist-coder/calc.py results/combined/
cp results/calculator_*/prompt_2/defensive-programmer/validation.py results/combined/
cp results/calculator_*/prompt_3/enterprise-developer/tests/* results/combined/tests/
```

## Common Workflows

### Rapid Prototyping
```json
{
  "prompts": ["Create a landing page"],
  "runner_contexts": [
    "minimalist design",
    "conversion optimized",
    "accessibility first"
  ]
}
```

### Code Review Perspectives
```json
{
  "prompts": ["Review this code: {paste code}"],
  "runner_contexts": [
    "security auditor",
    "performance engineer",
    "junior developer"
  ]
}
```

### Algorithm Comparison
```json
{
  "prompts": ["Implement binary search"],
  "runner_contexts": [
    "recursive approach",
    "iterative approach",
    "explain like im five"
  ]
}
```

### Multi-Step Development
```json
{
  "prompts": [
    "Create the data model",
    "Build the API",
    "Add the frontend",
    "Write tests"
  ],
  "runner_contexts": [
    "domain driven design",
    "rapid prototype",
    "production ready"
  ]
}
```

## Speed Tips

### 1. Use String Contexts for Speed
String contexts are fastest to set up:
```json
"runner_contexts": ["fast", "good", "cheap"]
```

### 2. Reuse Generated Contexts
```bash
# First run generates contexts
./generate-contexts.sh config.json

# Subsequent runs reuse them (unless --force)
./generate-contexts.sh config.json  # Skips existing
```

### 3. Use Dry Run for Preview
```bash
# See what will be created without calling Claude
./generate-contexts.sh config.json --dry-run
```

### 4. Create Context Libraries
```bash
# Build a library of contexts
mkdir context-library
cp -r runner-contexts/* context-library/

# Reference in new configs
{
  "runner_contexts": [
    {"name": "security", "claudemd_file": "context-library/security/CLAUDE.md"}
  ]
}
```

### 5. Batch Similar Tests
```json
{
  "prompts": [
    "Fix bug #1",
    "Fix bug #2", 
    "Fix bug #3"
  ],
  "runner_contexts": ["systematic debugger"]
}
```

## Generated File Structure

```
project/
├── configs/
│   ├── my-test.json          # Original config
│   └── my-test.json.new      # Normalized with paths
├── runner-contexts/
│   ├── security-expert/
│   │   └── CLAUDE.md
│   ├── performance-optimizer/
│   │   └── CLAUDE.md
│   └── beginner-friendly/
│       └── CLAUDE.md
└── project_template/
    └── CLAUDE.md              # Optional base template
```

## Context Name Generation

**How string contexts get converted to directory names:**

When you provide string contexts like "security expert" or "make it fast!", the generator:

1. **Calls Claude** with a prompt to summarize the string in three kebab-case words
2. **Sanitizes the result** to ensure valid directory names (alphanumeric and hyphens only)
3. **Falls back to normalized input** if Claude doesn't respond or returns invalid text
4. **Ensures uniqueness** by avoiding name collisions

**Examples of the transformation process:**
- Descriptive strings get converted to professional, relevant directory names
- Special characters and spaces are normalized to hyphens
- Names are shortened to be practical for filesystem use
- The generated names reflect the essence of the original string

**Fallback behavior:**
If Claude is unavailable or returns unusable text, the generator creates directory names by:
- Converting to lowercase
- Replacing non-alphanumeric characters with hyphens
- Removing duplicate hyphens
- Trimming leading/trailing hyphens

This ensures the process always succeeds even without Claude's creative naming.

## Debugging

### Check what contexts will be created:
```bash
./generate-contexts.sh config.json --dry-run
```

### Force regenerate all contexts:
```bash
./generate-contexts.sh config.json --force
```

### View generated config:
```bash
cat configs/my-config.json.new | jq .
```

### Manually edit a context:
```bash
vim runner-contexts/security-expert/CLAUDE.md
```

## Best Practices

1. **Start simple**: Use string contexts for initial exploration
2. **Iterate quickly**: Use --dry-run to preview changes
3. **Save good contexts**: Build a library of effective contexts
4. **Be specific**: "Python type hints expert" > "Python developer"
5. **Test extremes**: Include opposing viewpoints for comparison
6. **Use templates**: Create a base template for consistency

## Example: Full Development Cycle

**Complete workflow from concept to multiple implementations:**

```bash
# 1. Create initial config
cat > configs/feature.json << 'EOF'
{
  "prompts": ["Build user authentication"],
  "num_runners": 3,
  "runner_contexts": [
    "oauth specialist",
    "security first",
    "simple password"
  ]
}
EOF

# 2. Preview what will be created
./generate-contexts.sh configs/feature.json --dry-run

# 3. Generate contexts
./generate-contexts.sh configs/feature.json

# 4. Run parallel implementation
./multi-simple.sh configs/feature.json.new

# 5. Add more contexts based on results
cat > configs/feature-v2.json << 'EOF'
{
  "prompts": ["Build user authentication"],  
  "num_runners": 4,
  "runner_contexts": [
    "oauth specialist",
    "jwt tokens",
    "session based",
    "passwordless"
  ]
}
EOF

# 6. Generate and run expanded test
./generate-contexts.sh configs/feature-v2.json
./multi-simple.sh configs/feature-v2.json.new

# 7. Pick best approach and continue
```

**Development cycle benefits:**
1. **Start with a broad stroke** where you let Claude generate both the heuristics and resulting code for you
2. **Analyze initial results** to identify promising directions
3. **Expand with more specific contexts** based on what you learned
4. **Compare multiple authentication strategies** side by side
5. **Find the best approach** or draw insights from elements of different implementations
6. **Add more runners to increase sample size**: Results will be different each time due to the non-deterministic nature of Claude

**Result analysis:**
- Compare OAuth vs JWT vs session-based implementations
- Evaluate potential security insights from the "security first" context
- Review simplicity from the "simple password" approach
- Use findings to make informed architectural decisions

**Iteration strategy:**
- Keep successful contexts for reuse in future projects
- Refine context descriptions based on output quality
- Build a library of effective contexts for common development patterns

## Tips

- **Use descriptive strings**: Claude will generate better context names
- **Keep configs small**: Test one thing at a time (e.g. one prompt)
- **Run in parallel**: Use `execution_mode: "parallel"` for speed
- **Version control**: Commit good `.json.new` files for reproducibility
- **Use templates**: Create a base CLAUDE.md in `project_template/` for consistency