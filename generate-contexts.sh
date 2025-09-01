#!/bin/bash

# generate-contexts.sh - Config-first CLAUDE.md context file generator

set -e

# Default values
DEFAULT_OUTPUT_DIR="runner-contexts"
CONFIG_FILE=""
TEMPLATE_FILE=""
FORCE_REGENERATE=false
DRY_RUN=false

# Colors for output (consistent with multi-simple.sh style)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

show_usage() {
    cat << EOF
generate-contexts.sh - Config-first CLAUDE.md context file generator

USAGE:
  $(basename "$0") CONFIG_FILE [OPTIONS]

OPTIONS:
  --force                     Regenerate existing CLAUDE.md context files even if they exist
  --template FILE             Global template that will be used as basis for generated ones
  --dry-run                   Show what would be generated without creating files
  -h, --help                  Show this help

ABOUT:
    - Generates CLAUDE.md context files from a config file, used when running multi-simple.sh.
    - This is an optional step, run prior to running multi-simple.sh to generate unique instructions for different runners.

CONFIG FORMAT:
{
  "prompts": ["Task prompts for context relevance"], // Task prompt, required
  "task_name": "optional-task-identifier", // Task name, optional
  "num_runners": 3, // Number of runners to generate contexts for, only required if runner_contexts array is not provided
  "runner_contexts": [ // Array of contexts to generate, required if num_runners is not provided
    "context-name",                           // If simple string → claude will generate a name and claudemd_file
    {
      "name": "expert-type",                  // Name of the context, and savedir of context file, included in context generation prompt, required
      "description": "Custom description",    // Additional description of the context, included in context generation prompt
      "claudemd_file": "custom/path.md"       // Path to existing context file
    }
  ]
}

MODES OF OPERATION:
    - if runner_contexts array is not provided
        - num_runners is required and will be used to generate that many contexts
    - if runner_contexts array is provided
        - it will be used to generate the contexts and num_runners will be ignored
    - new config file with name config_name.json.new will be created to be run with multi-simple.sh

EXAMPLES:
  # Generate all missing contexts from config
  $(basename "$0") my-task.json
  
  # Force regenerate all contexts
  $(basename "$0") my-task.json --force
  
  # Use global template
  $(basename "$0") my-task.json --template base-template.md
  
  # See what would be generated
  $(basename "$0") my-task.json --dry-run

OUTPUT:
  - Generates missing CLAUDE.md files based on config
  - Creates config_name.json.new with complete claudemd_file paths
  - Original config remains unchanged
  - Respects existing files unless --force used

EOF
}

log_info() {
    echo -e "${GREEN}[Generator]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[Generator]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[Generator]${NC} $1" >&2
}

log_dry() {
    echo -e "${BLUE}[DRY-RUN]${NC} $1" >&2
}

parse_arguments() {
    if [ $# -eq 0 ]; then
        show_usage
        exit 0
    fi
    
    # First argument should be config file
    if [[ ! "$1" =~ ^- ]]; then
        CONFIG_FILE="$1"
        shift
    else
        log_error "Config file required as first argument"
        show_usage
        exit 1
    fi
    
    # Parse remaining options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_REGENERATE=true
                shift
                ;;
            --template)
                if [[ -z "$2" || "$2" =~ ^- ]]; then
                    log_error "Template file path required after --template"
                    exit 1
                fi
                TEMPLATE_FILE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}


validate_requirements() {
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        log_error "jq not found. Please install jq for JSON processing."
        exit 1
    fi
    
    # Check if Claude CLI is available
    if ! command -v claude &> /dev/null; then
        log_error "Claude CLI not found. Please install and configure Claude CLI first."
        exit 1
    fi
    
    # Config file validation
    if [ -z "$CONFIG_FILE" ]; then
        log_error "Config file required"
        show_usage
        exit 1
    fi
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Config file not found: $CONFIG_FILE"
        exit 1
    fi
    
    if [ ! -r "$CONFIG_FILE" ]; then
        log_error "Config file not readable: $CONFIG_FILE"
        exit 1
    fi
    
    # Validate template file if provided
    if [ -n "$TEMPLATE_FILE" ]; then
        if [ ! -f "$TEMPLATE_FILE" ]; then
            log_error "Template file not found: $TEMPLATE_FILE"
            exit 1
        fi
        if [ ! -r "$TEMPLATE_FILE" ]; then
            log_error "Template file not readable: $TEMPLATE_FILE"
            exit 1
        fi
        log_info "Using global template: $TEMPLATE_FILE"
    fi
}

generate_path() {
    local directory="$1"
    echo "$DEFAULT_OUTPUT_DIR/$directory/CLAUDE.md"
}

generate_name() {
    local string="$1"
    if [ "$DRY_RUN" = true ]; then
        # In dry-run, just sanitize the string to a directory name
        local directory=$(echo "$string" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-zA-Z0-9-]/-/g' | sed 's/-\+/-/g' | sed 's/^-//;s/-$//')
        echo "$directory"
        return
    fi
    # Call Claude and clean up the response
    local name=$(claude --permission-mode "plan" -p "Summarize the following string in 1 to 3 words using kebab-case, return answer only: '$string'" | tr -d '\n' | sed 's/[^a-zA-Z0-9-]/-/g' | sed 's/-\+/-/g' | sed 's/^-//;s/-$//')
    
    # If Claude returns empty or just whitespace, fall back to sanitized original
    if [ -z "$name" ]; then
        name=$(echo "$string" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-zA-Z0-9-]/-/g' | sed 's/-\+/-/g' | sed 's/^-//;s/-$//')
    fi
    
    echo "$name"
}

normalize_runner_contexts() {
    local config_file="$1"
    
    # Test original config file first
    if ! jq . "$config_file" >/dev/null 2>&1; then
        log_error "Invalid JSON in config file: $config_file"
        return 1
    fi
    
    local temp_config=$(mktemp)
    local contexts_updated=false
    
    # Copy original config
    cp "$config_file" "$temp_config"
    
    # Check if task_name exists, if not generate it from prompts
    local task_name=$(jq -r '.task_name // empty' "$temp_config")
    if [ -z "$task_name" ] || [ "$task_name" = "null" ]; then
        local config_prompts=$(jq -r '.prompts[]? // empty' "$temp_config" | paste -sd, -)
        if [ -n "$config_prompts" ]; then
            log_info "No task_name found, generating from prompts"
            if [ "$DRY_RUN" = true ]; then
                task_name="generated-task-name"
            else
                task_name=$(generate_name "$config_prompts")
            fi
            
            # Add task_name to config
            jq ".task_name = \"$task_name\"" "$temp_config" > "${temp_config}.tmp"
            mv "${temp_config}.tmp" "$temp_config"
            contexts_updated=true
            
            log_info "Generated task_name: $task_name"
        fi
    fi
    
    # Check if runner_contexts exists and is an array
    if ! jq -e '.runner_contexts | type == "array"' "$config_file" >/dev/null 2>&1; then
        # runner_contexts doesn't exist, generate from num_runners
        local num_runners=$(jq -r '.num_runners // empty' "$config_file")
        
        if [ -z "$num_runners" ] || [ "$num_runners" = "null" ]; then
            log_error "No runner_contexts found and num_runners not specified"
            rm "$temp_config"
            return 1
        fi
        
        if ! [[ "$num_runners" =~ ^[0-9]+$ ]] || [ "$num_runners" -lt 1 ]; then
            log_error "num_runners must be a positive integer"
            rm "$temp_config"
            return 1
        fi
        
        log_info "No runner_contexts found, generating $num_runners random contexts"
        
        # Get prompts and task_name for context generation
        local config_prompts=$(jq -r '.prompts[]? // empty' "$temp_config" | paste -sd, -)
        local task_name=$(jq -r '.task_name // empty' "$temp_config")
        
        # Generate random contexts array
        local contexts_json="["
        for ((i=0; i<num_runners; i++)); do
            if [ $i -gt 0 ]; then
                contexts_json+=","
            fi
            
            # Generate random description and name
            local description
            if [ "$DRY_RUN" = true ]; then
                description="Random context description $((i+1))"
            else
                description=$(context_description_from_prompts "$config_prompts" "$task_name")
            fi
            
            local name=$(generate_name "$description")
            local path=$(generate_path "$name")
            
            contexts_json+="{\"name\":\"$name\",\"description\":\"$description\",\"claudemd_file\":\"$path\"}"
        done
        contexts_json+="]"
        
        # Add runner_contexts to config
        jq ".runner_contexts = $contexts_json" "$temp_config" > "${temp_config}.tmp"
        mv "${temp_config}.tmp" "$temp_config"
        contexts_updated=true
        
        log_info "Generated $num_runners random contexts"
    fi
    
    # Process each context
    local length=$(jq '.runner_contexts | length' "$temp_config")
    for ((i=0; i<length; i++)); do
        # Get the type directly from the JSON structure
        local context_type=$(jq -r ".runner_contexts[$i] | type" "$temp_config")
        
        # Now get the actual value
        local context=$(jq -r ".runner_contexts[$i]" "$temp_config")

        log_info "Context type: $context_type"
        log_info "Context: $context"
        
        if [ "$context_type" = "string" ]; then
            # Convert string to object with auto-path
            local name=$(generate_name "$context")
            log_info "Normalized string context '$context' → '$name'"
            
            local path=$(generate_path "$name")
            
            local new_context=$(jq -n \
                --arg name "$name" \
                --arg path "$path" \
                '{name: $name, claudemd_file: $path}')
            
            # Update config
            temp_config2=$(mktemp)
            jq ".runner_contexts[$i] = $new_context" "$temp_config" > "$temp_config2"
            mv "$temp_config2" "$temp_config"
            contexts_updated=true
            
            
        elif [ "$context_type" = "object" ]; then
            # Check if object needs claudemd_file
            local has_path=$(jq -r ".runner_contexts[$i] | has(\"claudemd_file\")" "$temp_config")
            
            if [ "$has_path" = "false" ]; then
                # Generate auto-path from name
                local name=$(jq -r ".runner_contexts[$i].name // empty" "$temp_config")
                
                if [ -n "$name" ]; then
                    local path=$(generate_path "$name")
                    
                    # Add claudemd_file to object
                    temp_config2=$(mktemp)
                    jq ".runner_contexts[$i].claudemd_file = \"$path\"" "$temp_config" > "$temp_config2"
                    mv "$temp_config2" "$temp_config"
                    contexts_updated=true
                    
                    log_info "Added auto-path to context '$name' → '$path'"
                else
                    log_error "Context object missing both 'name' and 'claudemd_file' at index $i"
                    rm "$temp_config"
                    exit 1
                fi
            fi
        else
            log_error "Invalid context type at index $i: expected string or object"
            rm "$temp_config"
            exit 1
        fi
    done
    
    # Update original config if changes were made
    if [ "$contexts_updated" = true ]; then
        if [ "$DRY_RUN" = false ]; then
            # Save the normalized config to a new file
            local config_dir=$(dirname "$config_file")
            local config_name=$(basename "$config_file" .json)
            local new_config_file="$config_dir/$config_name.json.new"
            
            cp "$temp_config" "$new_config_file"
            log_info "Created normalized config: $new_config_file"
            log_info "Original config unchanged: $config_file"
        else
            log_dry "Would create normalized config: $(dirname "$config_file")/$(basename "$config_file" .json).json.new"
            log_dry "Original config would remain unchanged"
        fi
    fi
    
    # Return the normalized config content
    cat "$temp_config"
    rm "$temp_config"
}

build_generation_prompt() {
    local name="$1"
    local description="$2" 
    local config_prompts="$3"
    local task_name="$4"
    
    local generation_prompt="I need you to create a CLAUDE.md context file. This file will be used to influence how Claude behaves when loaded as context for specific tasks.

Context requirements:
"
    
    if [ -n "$description" ]; then
        generation_prompt+="DESCRIPTION: $description
"
    elif [ -n "$name" ]; then
        generation_prompt+="ROLE: Create a context for a '$name' approach/personality
"
    else
        generation_prompt+="CREATIVE: Generate a unique, creative context approach
"
    fi
    
    if [ -n "$config_prompts" ]; then
        generation_prompt+="TASK RELEVANCE: This context will be used for tasks like: $config_prompts
"
    fi
    
    if [ -n "$task_name" ]; then
        generation_prompt+="SPECIALIZATION: Focus on approaches suitable for '$task_name' workflows
"
    fi
    
    # Add template reference if provided
    if [ -n "$TEMPLATE_FILE" ]; then
        generation_prompt+="
TEMPLATE REFERENCE: Use the CLAUDE.md template provided as context to understand the desired format, structure, and style. Follow similar patterns but adapt the content to meet the specific requirements above.
"
    fi

    generation_prompt+="
Please create a comprehensive CLAUDE.md file that includes:

1. **Context Title**: Clear header describing the project
2. **Primary Priorities**: 3-4 main focus areas
3. **Guidelines**: Specific rules and approaches to follow  
4. **Code Style**: Preferred coding patterns and practices
5. **Review Checklist**: Key items to verify in completed work

Format the output as proper markdown with clear sections. The content should be detailed enough to meaningfully influence Claude's behavior but concise enough to be practical.

Return ONLY the CLAUDE.md file content - no explanations, no wrapper text, just the markdown content that should be saved as CLAUDE.md."

    echo "$generation_prompt"
}

# Description that will be sent to Claude instead of runner_contexts.description
# if task prompts are provided
context_description_from_prompts() {
    local config_prompts="$1"
    local task_name="$2"
    
    # Use Claude to generate a creative context idea
    local meta_prompt="Generate a short description (1-3 sentences) that would bring a new or old perspective to tasks like, make it unpredictable and unique: $config_prompts"
    
    if [ -n "$task_name" ]; then
        meta_prompt+="\n\nName of workflow: '$task_name'"
    else
        # Add randomness when no specific task_name is provided
        local randomizers=(
            "Draw inspiration from an unexpected domain (art, psychology, biology, etc.)"
            "Combine two different expertise areas in an unusual way"
            "Think from a contrarian or unconventional perspective" 
            "Focus on an overlooked or niche specialization"
            "Adopt a historical or futuristic approach to modern problems"
            "Consider cross-cultural or interdisciplinary methodologies"
            "Be traditional and conservatival but with a twist"
            "Be nerdy and deeply technical, valuing esoteric knowledge"
            "Choose a programming paradigm or concept to focus on"
            "Draw inspiration from the occult, mysticism, numerology or astrology"
            "Emphasize an extreme position (minimalism, maximalism, paranoia, optimism)"
        )
        
        # Pick a random approach (using process substitution for randomness)
        local random_index=$((RANDOM % ${#randomizers[@]}))
        meta_prompt+="\n\nRandomization hint: ${randomizers[$random_index]}"
    fi
    
    meta_prompt+="\n\nFocus on a specific expertise, personality, or approach that would be genuinely different and valuable. Examples: 'Accessibility-first developer', 'Performance optimization expert', 'Minimalist coder', 'Security-paranoid architect', 'Chaos engineer', 'Documentation obsessive', 'Legacy system archaeologist'. Return only the description."
    
    echo "$meta_prompt" | claude 2>/dev/null || echo "Creative problem-solving expert with unconventional approaches"
}

generate_single_context() {
    local name="$1"
    local description="$2"
    local claudemd_file="$3"
    local config_prompts="$4"
    local task_name="$5"
    
    local context_dir=$(dirname "$claudemd_file")

    echo "DEBUG: Checking '$claudemd_file' - exists: $(test -f "$claudemd_file" && echo YES || echo NO), force: $FORCE_REGENERATE"
    
    # Check if file exists and should be skipped
    log_info "DEBUG: Checking '$claudemd_file' - exists: $(test -f "$claudemd_file" && echo YES || echo NO), force: $FORCE_REGENERATE"
    if [ -f "$claudemd_file" ] && [ "$FORCE_REGENERATE" = false ]; then
        log_info "Context exists, skipping: $claudemd_file"
        return 0
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_dry "Would generate context: $claudemd_file"
        if [ -n "$name" ]; then
            log_dry "  Name: $name"
        fi
        if [ -n "$description" ]; then
            log_dry "  Description: $description"
        else
            log_dry "  Type: Auto-generated from name"
        fi
        return 0
    fi
    
    # Generate random description if neither name nor description provided
    if [ -z "$name" ] && [ -z "$description" ]; then
        if [ "$DRY_RUN" = true ]; then
            description="[Random context would be generated]"
        else
            log_info "Generating random context description..."
            description=$(context_description_from_prompts "$config_prompts" "$task_name")
            log_info "Generated description: $description"
        fi
    fi
    
    log_info "Creating context directory: $context_dir"
    mkdir -p "$context_dir"
    
    if [ -f "$claudemd_file" ]; then
        log_warn "Overwriting existing context: $claudemd_file"
    fi
    
    log_info "Generating context: ${name:-random} → $claudemd_file"
    
    # Build generation prompt
    local generation_prompt
    generation_prompt=$(build_generation_prompt "$name" "$description" "$config_prompts" "$task_name")
    
    # Create temp file for generation prompt
    local temp_prompt=$(mktemp)
    echo "$generation_prompt" > "$temp_prompt"
    
    # Look for template in project_template/CLAUDE.md
    local effective_template="$TEMPLATE_FILE"
    if [ -f "project_template/CLAUDE.md" ]; then
        effective_template="project_template/CLAUDE.md"
        log_info "Using project template: project_template/CLAUDE.md"
    fi
    
    # Run Claude CLI and capture output
    if [ -n "$effective_template" ]; then
        log_info "Using template: $effective_template"
        if cat "$effective_template" | claude -p "$(cat "$temp_prompt")" > "$claudemd_file" 2>/dev/null; then
            rm "$temp_prompt"
        else
            rm "$temp_prompt"
            log_error "Failed to generate context using Claude CLI with template"
            return 1
        fi
    else
        if claude < "$temp_prompt" > "$claudemd_file" 2>/dev/null; then
            rm "$temp_prompt"
        else
            rm "$temp_prompt"
            log_error "Failed to generate context using Claude CLI"
            return 1
        fi
    fi
    
    # Verify output is not empty
    if [ ! -s "$claudemd_file" ]; then
        log_error "Generated context file is empty: $claudemd_file"
        return 1
    fi
    
    log_info "✅ Context generated successfully: $claudemd_file"
    return 0
}

process_config_contexts() {
    local config_content="$1"
    
    # Extract config data
    local config_prompts=$(echo "$config_content" | jq -r '.prompts[]? // empty' | paste -sd, -)
    local task_name=$(echo "$config_content" | jq -r '.task_name // empty')
    local contexts_count=$(echo "$config_content" | jq '.runner_contexts | length')
    
    log_info "Processing $contexts_count context(s)"
    if [ -n "$config_prompts" ]; then
        log_info "Task prompts: $config_prompts"
    fi
    if [ -n "$task_name" ]; then
        log_info "Task name: $task_name"
    fi
    
    # Process each context
    local success_count=0
    local skip_count=0
    local error_count=0
    
    for ((i=0; i<contexts_count; i++)); do
        # Get values directly from the JSON rather than parsing extracted values
        local name=$(echo "$config_content" | jq -r ".runner_contexts[$i].name // empty")
        local description=$(echo "$config_content" | jq -r ".runner_contexts[$i].description // empty")
        local claudemd_file=$(echo "$config_content" | jq -r ".runner_contexts[$i].claudemd_file // empty")
        
        # If it's a string context, the claudemd_file will be empty and name will be empty
        # In that case, get the string value itself
        if [ -z "$claudemd_file" ] && [ -z "$name" ]; then
            local context_type=$(echo "$config_content" | jq -r ".runner_contexts[$i] | type")
            if [ "$context_type" = "string" ]; then
                # This shouldn't happen after normalization, but handle it anyway
                log_error "String context at index $i was not normalized"
                continue
            fi
        fi
        
        log_info "Processing context $(($i + 1))/$contexts_count..."
        
        if generate_single_context "$name" "$description" "$claudemd_file" "$config_prompts" "$task_name"; then
            if [ -f "$claudemd_file" ]; then
                ((success_count++))
            else
                ((skip_count++))
            fi
        else
            ((error_count++))
        fi
    done
    
    # Summary
    echo
    echo "========================================="
    echo "Generation Summary:"
    echo "========================================="
    log_info "Generated: $success_count contexts"
    if [ $skip_count -gt 0 ]; then
        log_info "Skipped: $skip_count existing contexts"
    fi
    if [ $error_count -gt 0 ]; then
        log_error "Failed: $error_count contexts"
    fi
    echo "========================================="
    
    return $([ $error_count -eq 0 ] && echo 0 || echo 1)
}

run_main() {
    log_info "Config file: $CONFIG_FILE"
    
    # Normalize runner contexts and get updated config
    local normalized_config
    normalized_config=$(normalize_runner_contexts "$CONFIG_FILE")
    
    # Process all contexts
    if process_config_contexts "$normalized_config"; then
        log_info "✅ All contexts processed successfully"
        
        if [ "$DRY_RUN" = false ]; then
            # Check if a .new file was created
            local config_dir=$(dirname "$CONFIG_FILE")
            local config_name=$(basename "$CONFIG_FILE" .json)
            local new_config_file="$config_dir/$config_name.json.new"
            
            if [ -f "$new_config_file" ]; then
                echo
                echo "Ready to run: ./multi-simple.sh $new_config_file"
            else
                echo
                echo "Ready to run: ./multi-simple.sh $CONFIG_FILE"
            fi
        fi
        return 0
    else
        log_error "❌ Some contexts failed to generate"
        return 1
    fi
}


main() {
    parse_arguments "$@"
    validate_requirements
    run_main
}

# Run main function with all arguments
main "$@"