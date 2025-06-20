#!/bin/bash

# Script to automate feature implementation using AI tools.
# Orchestrates Gemini (via OpenRouter) for planning and Claude Code for implementation.

set -e # Exit immediately if a command exits with a non-zero status.
# set -u # Treat unset variables as an error. # Temporarily disabled for SCRIPT_DIR
# set -o pipefail # Causes a pipeline to return the exit status of the last command in the pipe that failed.

# --- Configuration and Setup ---
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
CONFIG_FILE="${SCRIPT_DIR}/config.sh"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    echo "Please copy ${CONFIG_FILE}.example to $CONFIG_FILE and customize it."
    exit 1
fi
source "$CONFIG_FILE"

# Validate essential configuration
if [[ "${OPENROUTER_API_KEY}" == "YOUR_OPENROUTER_API_KEY_HERE" || -z "${OPENROUTER_API_KEY}" ]]; then
  echo "ERROR: OPENROUTER_API_KEY is not set or is still the default placeholder in $CONFIG_FILE." >&2
  exit 1
fi

# Ensure necessary commands are available
if ! command -v jq &> /dev/null; then
    echo "ERROR: jq is not installed. Please install jq to parse JSON responses."
    exit 1
fi
CLAUDE_EXEC=${CLAUDE_CLI_PATH:-claude}
if ! command -v "$CLAUDE_EXEC" &> /dev/null; then
    echo "ERROR: Claude Code CLI ('$CLAUDE_EXEC') not found. Please install it (e.g., npm install -g @anthropic-ai/claude-code) and ensure it's in your PATH or configured in config.sh."
    exit 1
fi

# Ensure context files exist
if [ ! -f "$PROJECT_CONTEXT_PATH" ]; then
    echo "ERROR: Project context file not found: $PROJECT_CONTEXT_PATH"
    exit 1
fi
if [ ! -f "$REPO_CONTENTS_PATH" ]; then
    echo "ERROR: Repository contents file not found: $REPO_CONTENTS_PATH"
    exit 1
fi
if [ ! -f "$FEATURES_FILE_PATH" ]; then
    echo "ERROR: Features file not found: $FEATURES_FILE_PATH"
    exit 1
fi
if [ ! -f "$CLAUDE_RULES_PATH" ]; then
    echo "ERROR: Claude rules file not found: $CLAUDE_RULES_PATH"
    exit 1
fi

# Create output directories if they don't exist
mkdir -p "$GUIDES_DIR"
mkdir -p "$CLAUDE_TEMP_COMMANDS_DIR"

# --- Helper Functions ---
log_info() {
    echo "[INFO] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

# Function to sanitize feature name for filenames
sanitize_filename() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr -s '[:punct:][:space:]' '_' | sed 's/__*/_/g' | sed 's/^_//;s/_$//'
}

# --- Main Logic ---
log_info "Starting feature implementation process..."

# Read context files
project_context_content=$(<"$PROJECT_CONTEXT_PATH")
repo_contents_content=$(<"$REPO_CONTENTS_PATH")
claude_rules_content=$(<"$CLAUDE_RULES_PATH") # Not directly injected, path is used by claude

# Read and parse features file
features_string=$(<"$FEATURES_FILE_PATH")
# Use awk for robust splitting and handling of the delimiter
IFS=$'\n' read -d '' -r -a features_array < <(awk 'BEGIN{RS="--- FEATURE SEPARATOR ---"} {gsub(/(^[ \t\n]+)|([ \t\n]+$)/, ""); print $0}' "$FEATURES_FILE_PATH" && printf '\0')


feature_index=0
for feature_block in "${features_array[@]}"; do
    feature_block_trimmed=$(echo "$feature_block" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -z "$feature_block_trimmed" ]; then
        continue # Skip empty blocks
    fi

    feature_index=$((feature_index + 1))

    # Extract Feature Name
    feature_name_line=$(echo "$feature_block_trimmed" | grep -m1 "^Feature:")
    current_feature_name=$(echo "$feature_name_line" | sed 's/^Feature:[[:space:]]*//')

    # Extract Description
    desc_line_num=$(echo "$feature_block_trimmed" | grep -n -m1 "^Description:" | cut -d: -f1)
    if [ -n "$desc_line_num" ]; then
        current_feature_description=$(echo "$feature_block_trimmed" | tail -n "+$((desc_line_num))" | sed '1s/^Description:[[:space:]]*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    else
        log_error "Feature '$current_feature_name' is missing a 'Description:' section. Skipping."
        continue
    fi

    if [[ -z "$current_feature_name" ]]; then
        log_warn "Skipping feature block $feature_index with no parsable name."
        continue
    fi

    log_info "Processing Feature ${feature_index}: ${current_feature_name}"

    # 1. Generate Implementation Document (Gemini via OpenRouter)
    sanitized_name=$(sanitize_filename "$current_feature_name")
    guide_filename="${feature_index}_${sanitized_name}_change.md"
    guide_path="${GUIDES_DIR}/${guide_filename}"

    log_info "Generating implementation guide using ${GEMINI_MODEL}..."
    gemini_prompt="You are an expert software architect. Given the following project context, repository contents, and a specific feature request, generate a detailed step-by-step implementation plan in Markdown format. This plan will be used by an AI coding assistant (Claude Code) to write the actual code. The plan should be clear, actionable, and provide enough detail for the AI to understand the requirements, necessary code changes, new files to create, and expected outcomes.

Feature Request:
Title: ${current_feature_name}
Description:
${current_feature_description}

Project Context:
---
${project_context_content}
---

Repository Contents (structure and key file snippets):
---
${repo_contents_content}
---

Produce only the Markdown implementation plan."

    # Prepare JSON payload for OpenRouter
    json_payload=$(jq -n \
        --arg model "$GEMINI_MODEL" \
        --arg prompt "$gemini_prompt" \
        '{model: $model, messages: [{role: "user", content: $prompt}]}')

    response_file=$(mktemp)
    http_code=$(curl -s -w "%{http_code}" -o "$response_file" \
        -X POST "https://openrouter.ai/api/v1/chat/completions" \
        -H "Authorization: Bearer ${OPENROUTER_API_KEY}" \
        -H "Content-Type: application/json" \
        -H "HTTP-Referer: ${OPENROUTER_SITE_URL}" \
        -H "X-Title: ${OPENROUTER_SITE_NAME}" \
        -d "$json_payload")

    if [[ "$http_code" -ne 200 ]]; then
        log_error "OpenRouter API call failed with HTTP status $http_code. Response:"
        cat "$response_file"
        rm "$response_file"
        continue # Skip to next feature
    fi

    implementation_guide=$(jq -r '.choices[0].message.content' "$response_file")
    rm "$response_file"

    if [[ -z "$implementation_guide" || "$implementation_guide" == "null" ]]; then
        log_error "Failed to generate implementation guide or got empty response from OpenRouter for feature: $current_feature_name"
        continue
    fi

    echo "$implementation_guide" > "$guide_path"
    log_info "Implementation guide saved to: $guide_path"

    # 2. Implement with Claude Code
    temp_claude_command_name="feature_${feature_index}_${sanitized_name}_task"
    # Ensure temp_claude_command_name is valid for claude commands (alphanumeric, -, _)
    temp_claude_command_name_sanitized=$(echo "$temp_claude_command_name" | tr -s '[:punct:][:space:]' '_' | sed 's/__*/_/g' | sed 's/^_//;s/_$//' | tr '[:upper:]' '[:lower:]')
    temp_claude_command_file="${CLAUDE_TEMP_COMMANDS_DIR}/${temp_claude_command_name_sanitized}.md"
    
    # Ensure CLAUDE_RULES_PATH is absolute or relative to PWD
    # If CLAUDE_RULES_PATH is relative, it should be relative to where the script is run (project root)
    # The guide_path is already relative to project root or absolute.

    # Construct the content for the temporary Claude slash command
    # Using real paths for claude-code to read, assuming claude-code runs in PWD (project root)
    cat << EOF > "$temp_claude_command_file"
Your current task is to implement the feature: "${current_feature_name}".

1.  First, carefully read and understand the detailed implementation plan provided in the file: \`${guide_path}\`
    You can use the command: \`/read "${guide_path}"\` to load it.

2.  After understanding the plan, proceed to implement all necessary code changes, create new files, and modify existing ones as described.

3.  While working, you MUST strictly adhere to all guidelines specified in the document located at \`${CLAUDE_RULES_PATH}\`.
    If you are unsure about these rules, you can use \`/read "${CLAUDE_RULES_PATH}"\` to review them.

4.  Key development practices to follow (as per the rules):
    *   Write unit tests for new functionality and ensure all tests pass.
    *   Confirm that the implemented code runs correctly and the feature works as expected.
    *   Clearly state what tests you ran or how you verified the functionality.

5.  Once you have successfully implemented the feature, verified it, and ensured tests pass:
    *   Stage all relevant changes using an appropriate git add command (e.g., \`/git add .\` or list specific files).
    *   Commit the changes with the exact commit message: \`feat: Implement ${current_feature_name}\`
       (Use the command: \`/git commit -m "feat: Implement ${current_feature_name}"\`)

Execute all these steps autonomously and comprehensively. Begin by reading the implementation plan.
EOF

    log_info "Attempting to implement feature '${current_feature_name}' using Claude Code..."
    log_info "Claude Code will use the temporary command: /project:${temp_claude_command_name_sanitized}"
    log_info "Task details written to: ${temp_claude_command_file}"
    
    # Run Claude Code non-interactively with the prepared slash command
    # The --dangerously-skip-permissions flag is crucial for automation
    if "$CLAUDE_EXEC" -p "/project:${temp_claude_command_name_sanitized}" --dangerously-skip-permissions; then
        log_info "Claude Code finished processing for feature: ${current_feature_name}"
    else
        log_error "Claude Code command failed for feature: ${current_feature_name}. Check Claude's output for details."
        # Decide if script should stop or continue
        # For now, it will continue with the next feature if 'set -e' is not active for this block
    fi
    
    # Clean up temporary claude command file
    rm -f "$temp_claude_command_file"
    log_info "Cleaned up temporary Claude command file: $temp_claude_command_file"

    # 3. Human Review (if enabled)
    if [[ "$HUMAN_REVIEW" == "true" ]]; then
        echo ""
        log_info "Feature '${current_feature_name}' implementation attempt complete."
        echo "Please review the changes made by Claude Code."
        echo "Git status:"
        git status -s
        echo "Press Enter to continue to the next feature, or Ctrl+C to abort."
        read -r
    fi

done

log_info "All features processed."
exit 0 