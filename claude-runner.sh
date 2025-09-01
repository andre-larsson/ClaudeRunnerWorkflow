#!/bin/bash

# claude-runner.sh - Simplified multi-runner for Claude with better defaults and tracking

set -e

# Configuration - easily adjustable by users
DEFAULT_MAX_RETRIES=5          # Max retry attempts for rate limits
DEFAULT_RETRY_DELAY=3600       # Seconds to wait between retries (1 hour)
WORKER_SPAWN_DELAY=3           # Seconds to wait between spawning workers

# Help message
if [ "$1" = "--help" ] || [ "$1" = "-h" ] || [ $# -eq 0 ]; then
    cat << EOF
Usage:  $0 -p "prompt1" ["prompt2" ...] [options]
        $0 [config.json]

Command Line Options:
  -p, --prompts "p1" "p2" ...    Prompts to execute (required)
  -n, --num-runners N            Number of runners (default: 3)
  -m, --max-parallel N           Max parallel runners (default: num_runners)
  -t, --task-name NAME           Task name for output directory
  -b, --base-directory PATH      Base output directory (default: ./results)
  --template-directory PATH      Template directory to copy
  -c, --runner-context "name:path"  Runner context (can repeat)
  -e, --execution-mode MODE      parallel|sequential (default: parallel)

Examples:
  # Single prompt via CLI:
  $0 -p "Create a calculator app" -n 3
  
  # Multiple prompts via CLI:
  $0 -p "Create HTML" "Add CSS" "Add JavaScript" -n 2 -m 1
  
  # With contexts:
  $0 -p "Build auth system" -n 3 -c "security:runner-contexts/security-focused/CLAUDE.md"
  
  # Config file mode:
  $0 config.json
  

Config File Format:
  {
    "prompts": ["Prompt 1", "Prompt 2"],
    "num_runners": 3,
    "max_parallel": 2,
    "runner_contexts": [
      {"name": "security", "claudemd_file": "runner-contexts/security/CLAUDE.md"}
    ]
  }

Output: results/TASK_NAME/00001_<context_name>/
EOF
    exit 0
fi

# Parse arguments - support CLI flags, config file, and positional args
if [[ "$1" == -* ]]; then
    # CLI mode - parse command line arguments
    PROMPTS_ARRAY=()
    CONTEXTS_ARRAY=()
    NUM_RUNNERS=3
    MAX_PARALLEL=""
    TASK_NAME_ARG=""
    BASE_DIR="./results"
    TEMPLATE_DIR=""
    EXEC_MODE="parallel"
    CONFIG_FILE=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--prompts)
                shift  # Skip the -p flag
                # Collect all non-flag arguments as prompts
                while [[ $# -gt 0 ]] && [[ "$1" != -* ]]; do
                    PROMPTS_ARRAY+=("$1")
                    shift
                done
                ;;
            -n|--num-runners)
                NUM_RUNNERS="$2"
                shift 2
                ;;
            -m|--max-parallel)
                MAX_PARALLEL="$2"
                shift 2
                ;;
            -t|--task-name)
                TASK_NAME_ARG="$2"
                shift 2
                ;;
            -b|--base-directory)
                BASE_DIR="$2"
                shift 2
                ;;
            --template-directory)
                TEMPLATE_DIR="$2"
                shift 2
                ;;
            -c|--runner-context)
                CONTEXTS_ARRAY+=("$2")
                shift 2
                ;;
            -e|--execution-mode)
                EXEC_MODE="$2"
                shift 2
                ;;
            *)
                echo "ERROR: Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Convert prompts array to JSON
    if [ ${#PROMPTS_ARRAY[@]} -gt 0 ]; then
        PROMPTS="["
        for prompt in "${PROMPTS_ARRAY[@]}"; do
            # Escape quotes in prompt for JSON
            escaped_prompt=$(echo "$prompt" | sed 's/"/\\"/g')
            PROMPTS+="\"$escaped_prompt\","
        done
        PROMPTS="${PROMPTS%,}]"  # Remove trailing comma and close bracket
    else
        PROMPTS="[]"
    fi
    
    # Convert contexts array to JSON  
    if [ ${#CONTEXTS_ARRAY[@]} -gt 0 ]; then
        RUNNER_CONTEXTS="["
        for context in "${CONTEXTS_ARRAY[@]}"; do
            if [[ "$context" == *":"* ]]; then
                name="${context%%:*}"     # Everything before first :
                path="${context#*:}"      # Everything after first :
                RUNNER_CONTEXTS+="{\"name\":\"$name\",\"claudemd_file\":\"$path\"},"
            else
                echo "ERROR: Context format should be 'name:path', got: $context"
                exit 1
            fi
        done
        RUNNER_CONTEXTS="${RUNNER_CONTEXTS%,}]"  # Remove trailing comma and close bracket
    else
        RUNNER_CONTEXTS="[]"
    fi
    
    # Set defaults
    if [ -z "$MAX_PARALLEL" ]; then
        MAX_PARALLEL=$NUM_RUNNERS
    fi
    CONFIG_TASK_NAME=""

elif [ -f "$1" ]; then
    # Config file mode
    CONFIG_FILE="$1"
    
    # Only support prompts array
    PROMPTS=$(jq -c '.prompts // []' "$CONFIG_FILE")
    
    # Check if prompts array exists and is not empty
    if [ "$PROMPTS" = "[]" ] || [ "$PROMPTS" = "null" ]; then
        PROMPTS=""
    fi
    NUM_RUNNERS=$(jq -r '.num_runners // 3' "$CONFIG_FILE")
    # Auto-scale parallelism - default to num_runners unless specified
    MAX_PARALLEL=$(jq -r '.max_parallel // '$NUM_RUNNERS "$CONFIG_FILE")
    TEMPLATE_DIR=$(jq -r '.project_template // ""' "$CONFIG_FILE")
    EXEC_MODE=$(jq -r '.execution_mode // "parallel"' "$CONFIG_FILE")
    CONFIG_TASK_NAME=$(jq -r '.task_name // ""' "$CONFIG_FILE")
    BASE_DIR=$(jq -r '.base_directory // "./results"' "$CONFIG_FILE")
    RUNNER_CONTEXTS=$(jq -c '.runner_contexts // []' "$CONFIG_FILE")
    TASK_NAME_ARG=""

else
    # Invalid usage - neither CLI flag nor config file
    echo "ERROR: Invalid usage. First argument must be a flag (-p, -n, etc.) or a config file."
    echo "Usage: $0 -p \"prompt1\" [\"prompt2\" ...] [options]"
    echo "   or: $0 config.json"
    echo "Use --help for detailed usage information"
    exit 1
fi

# Set base directory to "./results" if not set
if [ -z "$BASE_DIR" ]; then
    BASE_DIR="./results"
fi

# Validate prompts
if [ -z "$PROMPTS" ] || [ "$PROMPTS" = "[]" ]; then
    echo "ERROR: No prompts provided"
    echo "Usage: $0 -p \"prompt1\" [\"prompt2\" ...] [options]"
    echo "   or: $0 config.json (with 'prompts' array)"
    echo "Use --help for detailed usage information"
    exit 1
fi

# Filter out contexts with missing/invalid claudemd_file to avoid confusion
filter_valid_contexts() {
    if [ "$RUNNER_CONTEXTS" = "[]" ] || [ "$RUNNER_CONTEXTS" = "null" ]; then
        return 0
    fi
    
    local contexts_count=$(echo "$RUNNER_CONTEXTS" | jq 'length')
    if [ "$contexts_count" -eq 0 ]; then
        return 0
    fi
    
    echo "[Manager] Filtering contexts with valid CLAUDE.md files..." >&2
    
    local valid_contexts="[]"
    local filtered_count=0
    
    for ((i=0; i<contexts_count; i++)); do
        local context_name=$(echo "$RUNNER_CONTEXTS" | jq -r ".[$i].name // \"context_$i\"")
        local claudemd_file=$(echo "$RUNNER_CONTEXTS" | jq -r ".[$i].claudemd_file // \"\"")
        
        if [ -n "$claudemd_file" ] && [ "$claudemd_file" != "null" ] && [ -f "$claudemd_file" ]; then
            # Valid context - add to filtered list
            local context_obj=$(echo "$RUNNER_CONTEXTS" | jq ".[$i]")
            valid_contexts=$(echo "$valid_contexts" | jq ". += [$context_obj]")
        else
            # Invalid context - log and skip
            echo "[Manager] Filtering out context '$context_name': CLAUDE.md file missing or invalid ($claudemd_file)" >&2
            ((filtered_count++))
        fi
    done
    
    local valid_count=$(echo "$valid_contexts" | jq 'length')
    
    if [ "$valid_count" -eq 0 ]; then
        echo "[Manager] Warning: All contexts filtered out due to missing CLAUDE.md files. Runners will use default behavior." >&2
        RUNNER_CONTEXTS="[]"
    else
        RUNNER_CONTEXTS="$valid_contexts"
        if [ "$filtered_count" -gt 0 ]; then
            echo "[Manager] Using $valid_count valid contexts (filtered out $filtered_count invalid)" >&2
        fi
    fi
}

# Apply context filtering
filter_valid_contexts

# Determine run name (priority: CLI arg > config > generated)
TASK_NAME="${TASK_NAME_ARG:-$CONFIG_TASK_NAME}"
if [ -z "$TASK_NAME" ] || [ "$TASK_NAME" = "null" ]; then
    # Generate descriptive name from first prompt (first 30 chars, sanitized)
    FIRST_PROMPT=$(echo "$PROMPTS" | jq -r '.[0] // ""')
    TASK_NAME=$(echo "$FIRST_PROMPT" | tr -d '\n' | cut -c1-30 | tr -c '[:alnum:]' '-' | tr -s '-' | sed 's/^-//;s/-$//')
fi

# Create timestamp and full run directory name
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RUN_DIR="${BASE_DIR}/${TASK_NAME}_${TIMESTAMP}"

# Cleanup flag for interrupting sleeps
CLEANUP_DONE=false

# Interruptible sleep function
interruptible_sleep() {
    local duration="$1"
    local elapsed=0
    
    while [ $elapsed -lt $duration ]; do
        sleep 1
        elapsed=$((elapsed + 1))
        # Check for interrupt signal
        if [ "${CLEANUP_DONE}" = "true" ]; then
            return 1
        fi
    done
    return 0
}

# Execute Claude command with retry logic for rate limits
run_claude_with_retry() {
    local prompt="$1"
    local log_file="$2"
    local runner_num="$3"
    local max_attempts="${4:-5}"
    local retry_delay="${5:-3600}"
    
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        echo "=== ATTEMPT $attempt ===" >> "$log_file"
        echo "$(date): Starting attempt $attempt" >> "$log_file"
        echo "[Runner $runner_num] Attempt $attempt/$max_attempts"
        
        # Execute Claude with timeout
        local output
        local exit_code
        if command -v timeout >/dev/null 2>&1; then
            output=$(timeout 7200 claude --allowedTools "Read,Edit,Write,MultiEdit,Bash,TodoWrite,Glob,Grep" -p "$prompt" 2>&1)
            exit_code=$?
            if [ $exit_code -eq 124 ]; then
                echo "=== TIMEOUT ===" >> "$log_file"
                return 124  # Return timeout immediately, don't retry
            fi
        else
            output=$(claude --allowedTools "Read,Edit,Write,MultiEdit,Bash,TodoWrite,Glob,Grep" -p "$prompt" 2>&1)
            exit_code=$?
        fi
        
        echo "$output" >> "$log_file"
        
        # Check for rate limit in output
        if echo "$output" | grep -qi "limit reached\|rate limit\|too many requests"; then
            echo "[Runner $runner_num] Rate limit reached. Waiting $retry_delay seconds before retry..."
            echo "$(date): Rate limit hit, waiting $retry_delay seconds" >> "$log_file"
            interruptible_sleep "$retry_delay" || return 1
            attempt=$((attempt + 1))
        else
            # Either success or non-recoverable failure
            return $exit_code
        fi
    done
    
    echo "[Runner $runner_num] Max retry attempts ($max_attempts) reached"
    echo "$(date): Max retry attempts reached" >> "$log_file"
    return 1
}

# Update summary with runner status
update_summary() {
    echo "" >> "$RUN_DIR/README.md"
    echo "| Runner | Status | Start Time | End Time |" >> "$RUN_DIR/README.md"
    echo "|--------|--------|------------|----------|" >> "$RUN_DIR/README.md"
    
    for i in $(seq 1 "$NUM_RUNNERS"); do
        # Get context name for directory lookup
        local context_name=""
        if [ "$RUNNER_CONTEXTS" != "[]" ] && [ "$RUNNER_CONTEXTS" != "null" ]; then
            local contexts_count=$(echo "$RUNNER_CONTEXTS" | jq 'length')
            if [ "$contexts_count" -gt 0 ]; then
                local context_index=$(( (i - 1) % contexts_count ))
                context_name=$(echo "$RUNNER_CONTEXTS" | jq -r ".[$context_index].name // \"context_$context_index\"")
            else
                context_name="default"
            fi
        else
            context_name="default"
        fi
        
        local runner_padded=$(printf "%05d" $i)
        local runner_dir_name="${runner_padded}_${context_name}"
        local status_file="$RUN_DIR/$runner_dir_name/status.txt"
        local timing_file="$RUN_DIR/$runner_dir_name/timing.log"
        
        if [ -f "$status_file" ]; then
            local status=$(cat "$status_file")
            local start_time=$(grep "Started" "$timing_file" 2>/dev/null | cut -d: -f2- || echo "-")
            local end_time=$(grep "Completed" "$timing_file" 2>/dev/null | cut -d: -f2- || echo "-")
            echo "| $runner_dir_name | $status | $start_time | $end_time |" >> "$RUN_DIR/README.md"
        else
            echo "| $runner_dir_name | not started | - | - |" >> "$RUN_DIR/README.md"
        fi
    done
}

echo "========================================="
echo "Multi-Claude Simple Runner v2"
echo "========================================="
echo "Run Name: $TASK_NAME"
echo "Runners: $NUM_RUNNERS"
echo "Max Parallel: $MAX_PARALLEL"
echo "Output: $RUN_DIR"
echo "Template: ${TEMPLATE_DIR:-none}"
echo "========================================="

# Setup runner directory
setup_runner() {
    local runner_num=$1
    
    # Get context name for directory naming
    local context_name=""
    if [ "$RUNNER_CONTEXTS" != "[]" ] && [ "$RUNNER_CONTEXTS" != "null" ]; then
        local contexts_count=$(echo "$RUNNER_CONTEXTS" | jq 'length')
        if [ "$contexts_count" -gt 0 ]; then
            local context_index=$(( (runner_num - 1) % contexts_count ))
            context_name=$(echo "$RUNNER_CONTEXTS" | jq -r ".[$context_index].name // \"context_$context_index\"")
        else
            context_name="default"
        fi
    else
        context_name="default"
    fi
    
    # Format runner number with leading zeros and append context name
    local runner_padded=$(printf "%05d" $runner_num)
    local runner_dir="$RUN_DIR/${runner_padded}_${context_name}"
    
    mkdir -p "$runner_dir"
    
    # Copy template if specified (includes any project_template/CLAUDE.md as base)
    if [ -n "$TEMPLATE_DIR" ] && [ "$TEMPLATE_DIR" != "null" ] && [ -d "$TEMPLATE_DIR" ]; then
        echo "[Runner $runner_num] Copying template..." >&2
        cp -r "$TEMPLATE_DIR"/. "$runner_dir/" 2>/dev/null || true
    fi
    
    # Copy runner-specific CLAUDE.md context (overwrites template CLAUDE.md if present)
    if [ "$RUNNER_CONTEXTS" != "[]" ] && [ "$RUNNER_CONTEXTS" != "null" ]; then
        local contexts_count=$(echo "$RUNNER_CONTEXTS" | jq 'length')
        if [ "$contexts_count" -gt 0 ]; then
            # Use modulus to cycle through contexts if fewer contexts than runners
            local context_index=$(( (runner_num - 1) % contexts_count ))
            local context_name=$(echo "$RUNNER_CONTEXTS" | jq -r ".[$context_index].name // \"context_$context_index\"")
            local claudemd_file=$(echo "$RUNNER_CONTEXTS" | jq -r ".[$context_index].claudemd_file // \"\"")
            
            if [ -n "$claudemd_file" ] && [ "$claudemd_file" != "null" ] && [ -f "$claudemd_file" ]; then
                echo "[Runner $runner_num] Using context: $context_name ($claudemd_file)" >&2
                cp "$claudemd_file" "$runner_dir/CLAUDE.md" 2>/dev/null || true
            elif [ -n "$claudemd_file" ] && [ "$claudemd_file" != "null" ]; then
                echo "[Runner $runner_num] Warning: Context file not found: $claudemd_file" >&2
            fi
        fi
    fi
    
    # Create runner info file with context info
    local context_info="none"
    if [ "$RUNNER_CONTEXTS" != "[]" ] && [ "$RUNNER_CONTEXTS" != "null" ]; then
        local contexts_count=$(echo "$RUNNER_CONTEXTS" | jq 'length')
        if [ "$contexts_count" -gt 0 ]; then
            local context_index=$(( (runner_num - 1) % contexts_count ))
            local context_name=$(echo "$RUNNER_CONTEXTS" | jq -r ".[$context_index].name // \"context_$context_index\"")
            context_info="$context_name (index: $context_index)"
        fi
    fi
    
    # Create prompt info for info.txt
    local prompt_count=$(echo "$PROMPTS" | jq 'length')
    local prompt_info="Sequence of $prompt_count prompts (see prompt_*.log files)"
    
    cat > "$runner_dir/info.txt" << EOF
Runner: $runner_num
Context: $context_info
Prompt Count: $prompt_count
Started: $(date)
EOF
    
    echo "$runner_dir"
}

# Run Claude for a single runner
run_claude() {
    local runner_num=$1
    local runner_dir=$(setup_runner "$runner_num")
    
    echo "[Runner $runner_num] Starting in $runner_dir"
    
    # Create status file
    echo "running" > "$runner_dir/status.txt"
    echo "$(date): Started" > "$runner_dir/timing.log"
    
    # Execute prompt sequence
    (
        cd "$runner_dir"
        
        local overall_exit_code=0
        local prompt_count=$(echo "$PROMPTS" | jq 'length')
        echo "[Runner $runner_num] Executing sequence of $prompt_count prompts..."
        
        for i in $(seq 0 $((prompt_count-1))); do
            local current_prompt=$(echo "$PROMPTS" | jq -r ".[$i]")
            local prompt_num=$((i+1))
            local log_file="prompt_${prompt_num}.log"
            
            echo "[Runner $runner_num] Executing prompt $prompt_num/$prompt_count"
            echo "=== PROMPT $prompt_num ===" >> "$log_file"
            echo "$current_prompt" >> "$log_file"
            echo "=== OUTPUT ===" >> "$log_file"
            
            # Run Claude for this prompt with retry logic
            run_claude_with_retry "$current_prompt" "$log_file" "$runner_num" "$DEFAULT_MAX_RETRIES" "$DEFAULT_RETRY_DELAY"
            exit_code=$?
            
            echo "$(date): Prompt $prompt_num completed (exit: $exit_code)" >> timing.log
            
            if [ $exit_code -ne 0 ]; then
                echo "[Runner $runner_num] Prompt $prompt_num failed (exit: $exit_code)"
                echo "=== FAILED ===" >> "$log_file"
                overall_exit_code=$exit_code
                break
            else
                echo "[Runner $runner_num] Prompt $prompt_num completed successfully"
            fi
        done
        
        # Update final status
        echo "$(date): Overall completed (exit: $overall_exit_code)" >> timing.log
        if [ $overall_exit_code -eq 0 ]; then
            echo "completed" > status.txt
            echo "[Runner $runner_num] All prompts completed successfully"
        elif [ $overall_exit_code -eq 124 ]; then
            echo "timeout" > status.txt
            echo "[Runner $runner_num] Timed out"
        else
            echo "failed" > status.txt
            echo "[Runner $runner_num] Failed (exit: $overall_exit_code)"
        fi
    )
}

# Parallel execution with limit
run_parallel() {
    local pids=()
    local active_count=0
    
    for i in $(seq 1 "$NUM_RUNNERS"); do
        # Wait if we're at max parallel
        while true; do
            active_count=0
            for pid in "${pids[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    active_count=$((active_count + 1))
                fi
            done
            
            if [ $active_count -lt "$MAX_PARALLEL" ]; then
                break
            fi
            #echo -e "\r[Manager] Waiting for slot (${active_count}/${MAX_PARALLEL} running)..."
            sleep 5
        done
        
        # Start new job
        run_claude $i &
        local new_pid=$!
        pids+=($new_pid)
        echo "[Manager] Started runner $i (PID: $new_pid)"
        
        # Wait between spawning workers to avoid overwhelming the system
        sleep $WORKER_SPAWN_DELAY
    done
    
    # Wait for all remaining jobs with progress
    echo "[Manager] All runners started. Waiting for completion..."
    echo "[Manager] Tip: Check progress with: tail -f $RUN_DIR/*/prompt_*.log"
    
    local completed=0
    for pid in "${pids[@]}"; do
        wait "$pid"
        completed=$((completed + 1))
        echo "[Manager] Progress: $completed/$NUM_RUNNERS completed"
    done
}

# Sequential execution  
run_sequential() {
    for i in $(seq 1 "$NUM_RUNNERS"); do
        run_claude $i
    done
}

# Main execution
mkdir -p "$RUN_DIR"

# Save config for reference
if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$RUN_DIR/config.json"
else
    # Create config from arguments
    cat > "$RUN_DIR/config.json" << EOF
{
  "prompts": $PROMPTS,
  "num_runners": $NUM_RUNNERS,
  "max_parallel": $MAX_PARALLEL,
  "task_name": "$TASK_NAME",
  "base_directory": "$BASE_DIR",
  "project_template": "$TEMPLATE_DIR",
  "execution_mode": "$EXEC_MODE",
  "runner_contexts": $RUNNER_CONTEXTS
}
EOF
fi


# Record start time
echo "Start time: $(date)" | tee "$RUN_DIR/execution.log"

# Execute based on mode
if [ "$EXEC_MODE" = "parallel" ]; then
    echo "Running in parallel mode (max $MAX_PARALLEL concurrent)"
    run_parallel
else
    echo "Running in sequential mode"
    run_sequential
fi

# Record end time
echo "End time: $(date)" | tee -a "$RUN_DIR/execution.log"

# Update summary with final status
update_summary

# Create index if it doesn't exist
INDEX_FILE="${BASE_DIR}/index.md"
if [ ! -f "$INDEX_FILE" ]; then
    echo "# Run Index" > "$INDEX_FILE"
    echo "" >> "$INDEX_FILE"
    echo "| Timestamp | Name | Runners | Status | Directory |" >> "$INDEX_FILE"
    echo "|-----------|------|---------|--------|-----------|" >> "$INDEX_FILE"
fi

# Count completed runners
COMPLETED=$(grep -l "completed" "$RUN_DIR"/*/status.txt 2>/dev/null | wc -l)
FAILED=$(grep -l "failed" "$RUN_DIR"/*/status.txt 2>/dev/null | wc -l)
STATUS="${COMPLETED}✓"
[ $FAILED -gt 0 ] && STATUS="$STATUS ${FAILED}✗"

# Add to index
echo "| $TIMESTAMP | $TASK_NAME | $NUM_RUNNERS | $STATUS | $RUN_DIR |" >> "$INDEX_FILE"

# Summary
echo ""
echo "========================================="
echo "Execution Complete"
echo "========================================="
echo ""
echo "Runner Status:"
for i in $(seq 1 "$NUM_RUNNERS"); do
    # Get context name for directory lookup
    context_name=""
    if [ "$RUNNER_CONTEXTS" != "[]" ] && [ "$RUNNER_CONTEXTS" != "null" ]; then
        contexts_count=$(echo "$RUNNER_CONTEXTS" | jq 'length')
        if [ "$contexts_count" -gt 0 ]; then
            context_index=$(( (i - 1) % contexts_count ))
            context_name=$(echo "$RUNNER_CONTEXTS" | jq -r ".[$context_index].name // \"context_$context_index\"")
        else
            context_name="default"
        fi
    else
        context_name="default"
    fi
    
    runner_padded=$(printf "%05d" $i)
    runner_dir_name="${runner_padded}_${context_name}"
    status_file="$RUN_DIR/$runner_dir_name/status.txt"
    if [ -f "$status_file" ]; then
        status=$(cat "$status_file")
        echo "  $runner_dir_name: $status"
    else
        echo "  $runner_dir_name: not started"
    fi
done
echo ""
echo "Output Structure:"
echo "$RUN_DIR/"
echo "├── config.json              # Configuration used"
echo "├── execution.log            # Overall timing"
echo "├── 00001_<context_name>/"
echo "│   ├── info.txt             # Runner details"
echo "│   ├── status.txt           # Status"
echo "│   ├── timing.log           # Start/end times"
echo "│   └── prompt_*.log         # Claude output per prompt"
echo "└── README.md                # Run summary with status table"
echo ""
echo "Index updated: $INDEX_FILE"
echo "========================================="