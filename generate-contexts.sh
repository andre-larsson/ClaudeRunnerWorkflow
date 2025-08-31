#!/bin/bash

# generate-contexts.sh - Generate CLAUDE.md context files using Claude CLI

set -e

# Default values
DEFAULT_OUTPUT_DIR="runner-contexts"
CONTEXT_NAME=""
OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
TEMPLATE_FILE=""
PROMPTS=()

# Colors for output (consistent with multi-simple.sh style)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

show_usage() {
    cat << EOF
generate-contexts.sh - Generate CLAUDE.md context files using Claude CLI

USAGE:
  $(basename "$0") [OPTIONS]
  $(basename "$0") -p "Create a security-focused context" -n "security-expert"

OPTIONS:
  -p, --prompts "prompt1" "prompt2" ...  Prompts to send to Claude for context generation (required)
  -n, --name NAME                        Context name for directory and identification (required)
  -d, --directory DIR                    Output base directory (default: $DEFAULT_OUTPUT_DIR)
  -t, --template FILE                    Optional CLAUDE.md template file to provide as context to Claude
  -h, --help                             Show this help

EXAMPLES:
  # Generate security-focused context
  $(basename "$0") -p "Create a CLAUDE.md context for security-focused development with OWASP guidelines" -n "security-expert"
  
  # Generate performance context with custom directory
  $(basename "$0") -p "Performance optimization expert context" -d "my-contexts" -n "performance-guru"
  
  # Multi-prompt context generation
  $(basename "$0") -p "You are a React expert" "Focus on modern hooks and best practices" "Prioritize accessibility" -n "react-a11y"
  
  # Using template file as reference
  $(basename "$0") -p "Create similar context but for Vue.js" -n "vue-expert" -t "runner-contexts/react-expert/CLAUDE.md"

OUTPUT:
  Creates: \$OUTPUT_DIR/\$CONTEXT_NAME/CLAUDE.md
  Example: $DEFAULT_OUTPUT_DIR/security-expert/CLAUDE.md

EOF
}

log_info() {
    echo -e "${GREEN}[Generator]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[Generator]${NC} $1"
}

log_error() {
    echo -e "${RED}[Generator]${NC} $1"
}

parse_arguments() {
    if [ $# -eq 0 ]; then
        show_usage
        exit 0
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--prompts)
                shift
                # Collect all prompts until next flag or end
                while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                    PROMPTS+=("$1")
                    shift
                done
                ;;
            -n|--name)
                if [[ -z "$2" || "$2" =~ ^- ]]; then
                    log_error "Context name required after -n/--name"
                    exit 1
                fi
                CONTEXT_NAME="$2"
                shift 2
                ;;
            -d|--directory)
                if [[ -z "$2" || "$2" =~ ^- ]]; then
                    log_error "Directory path required after -d/--directory"
                    exit 1
                fi
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -t|--template)
                if [[ -z "$2" || "$2" =~ ^- ]]; then
                    log_error "Template file path required after -t/--template"
                    exit 1
                fi
                TEMPLATE_FILE="$2"
                shift 2
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
    # Check required arguments
    if [ ${#PROMPTS[@]} -eq 0 ]; then
        log_error "No prompts provided. Use -p to specify prompts for context generation."
        show_usage
        exit 1
    fi
    
    if [ -z "$CONTEXT_NAME" ]; then
        log_error "Context name required. Use -n to specify the context name."
        show_usage
        exit 1
    fi

    # Validate context name (alphanumeric, hyphens, underscores)
    if [[ ! "$CONTEXT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Context name must contain only letters, numbers, hyphens, and underscores"
        exit 1
    fi
    
    # Check if Claude CLI is available
    if ! command -v claude &> /dev/null; then
        log_error "Claude CLI not found. Please install and configure Claude CLI first."
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
        log_info "Using template: $TEMPLATE_FILE"
    fi
}

build_generation_prompt() {
    local generation_prompt="I need you to create a CLAUDE.md context file. This file will be used to influence how Claude behaves when loaded as context for specific tasks.

Requirements based on user input:
"
    
    # Add each user prompt as a requirement
    local i=1
    for prompt in "${PROMPTS[@]}"; do
        generation_prompt+="$i. $prompt
"
        ((i++))
    done

    # Add template reference if provided
    if [ -n "$TEMPLATE_FILE" ]; then
        generation_prompt+="
TEMPLATE REFERENCE: Use the CLAUDE.md template provided as context to understand the desired format, structure, and style. Follow similar patterns but adapt the content to meet the specific requirements above.
"
    fi

    generation_prompt+="
Please create a comprehensive CLAUDE.md file that includes:

1. **Context Title**: Clear header describing the context
2. **Primary Priorities**: 3-4 main focus areas
3. **Guidelines**: Specific rules and approaches to follow  
4. **Code Style**: Preferred coding patterns and practices
5. **Review Checklist**: Key items to verify in completed work

Format the output as proper markdown with clear sections. The content should be detailed enough to meaningfully influence Claude's behavior but concise enough to be practical.

Return ONLY the CLAUDE.md file content - no explanations, no wrapper text, just the markdown content that should be saved as CLAUDE.md."

    echo "$generation_prompt"
}

generate_context() {
    local context_dir="$OUTPUT_DIR/$CONTEXT_NAME"
    
    log_info "Creating context directory: $context_dir"
    mkdir -p "$context_dir"
    
    if [ -f "$context_dir/CLAUDE.md" ]; then
        log_warn "CLAUDE.md already exists in $context_dir"
        read -p "Overwrite existing file? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cancelled by user"
            exit 0
        fi
    fi
    
    log_info "Generating context: $CONTEXT_NAME"
    log_info "Using ${#PROMPTS[@]} prompt(s) for generation"
    
    # Build and run the generation prompt
    local generation_prompt
    generation_prompt=$(build_generation_prompt)
    
    log_info "Sending prompts to Claude CLI..."
    
    # Create temp file for generation prompt
    local temp_prompt=$(mktemp)
    echo "$generation_prompt" > "$temp_prompt"
    
    # Run Claude CLI and capture output
    # If template provided, pipe it as context; otherwise just use the prompt
    if [ -n "$TEMPLATE_FILE" ]; then
        log_info "Piping template file as context to Claude..."
        if cat "$TEMPLATE_FILE" | claude -p "$(cat "$temp_prompt")" > "$context_dir/CLAUDE.md" 2>/dev/null; then
            rm "$temp_prompt"
        else
            rm "$temp_prompt"
            log_error "Failed to generate context using Claude CLI with template"
            return 1
        fi
    else
        if claude < "$temp_prompt" > "$context_dir/CLAUDE.md" 2>/dev/null; then
            rm "$temp_prompt"
        else
            rm "$temp_prompt"
            log_error "Failed to generate context using Claude CLI"
            return 1
        fi
    fi
    
    # Verify output is not empty
    if [ ! -s "$context_dir/CLAUDE.md" ]; then
        log_error "Generated context file is empty"
        return 1
    fi
    
    log_info "✅ Context generated successfully"
    log_info "Location: $context_dir/CLAUDE.md"
    
    # Show usage example
    echo
    echo "========================================="
    echo "Context Usage Example:"
    echo "========================================="
    cat << EOF
In config file:
{
  "prompts": ["Your task here"],
  "runner_contexts": [
    {"name": "$CONTEXT_NAME", "claudemd_path": "$context_dir/CLAUDE.md"}
  ]
}

In CLI:
./multi-simple.sh -p "Your task" -c "$CONTEXT_NAME:$context_dir/CLAUDE.md"
EOF
    echo "========================================="
    
    return 0
}

show_context_preview() {
    local context_dir="$OUTPUT_DIR/$CONTEXT_NAME"
    
    echo
    echo "========================================="
    echo "Generated Context Preview:"
    echo "========================================="
    head -n 20 "$context_dir/CLAUDE.md"
    
    local line_count=$(wc -l < "$context_dir/CLAUDE.md")
    if [ "$line_count" -gt 20 ]; then
        echo "..."
        echo "(showing first 20 lines of $line_count total)"
    fi
    echo "========================================="
}

main() {
    parse_arguments "$@"
    validate_requirements
    
    log_info "Starting context generation"
    log_info "Context name: $CONTEXT_NAME"
    log_info "Output directory: $OUTPUT_DIR"
    log_info "Number of prompts: ${#PROMPTS[@]}"
    if [ -n "$TEMPLATE_FILE" ]; then
        log_info "Template file: $TEMPLATE_FILE"
    fi
    
    if generate_context; then
        show_context_preview
        log_info "Context generation completed successfully"
    else
        log_error "Context generation failed"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"