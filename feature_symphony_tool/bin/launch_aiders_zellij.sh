#!/usr/bin/env bash
set -euo pipefail

echo "--- Aider Launch Script (macOS - New Terminal Window Per Task) ---"

if ! command -v osascript >/dev/null 2>&1; then
  echo "Error: 'osascript' command not found. This script is designed for macOS."
  exit 1
fi

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <RUN_ID> <tasks_json_file_path>"
  exit 1
fi

RUN_ID="$1"
TASKS_JSON_FILE="$2"
PROJECT_ROOT_ABS_PATH="$(pwd)" # Script is run from project root

echo "RUN_ID: $RUN_ID"
echo "Tasks JSON File: $TASKS_JSON_FILE"
echo "Project Root (for new Terminals): $PROJECT_ROOT_ABS_PATH"

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: Required command 'jq' not found."
    exit 1
fi
if [ ! -f "$TASKS_JSON_FILE" ]; then
    echo "Error: Tasks JSON file not found at $TASKS_JSON_FILE"
    exit 1
fi

TASK_COUNT=$(jq '.tasks | length' "$TASKS_JSON_FILE")
echo "Found $TASK_COUNT tasks to launch."

# Create a temporary directory for our script files
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

for (( i=0; i<$TASK_COUNT; i++ ))
do
    TASK_INFO=$(jq -c ".tasks[$i]" "$TASKS_JSON_FILE")
    GUIDE_FILE=$(echo "$TASK_INFO" | jq -r '.guide_file')
    PROMPT_RAW=$(echo "$TASK_INFO" | jq -r '.prompt')
    DESCRIPTION_RAW=$(echo "$TASK_INFO" | jq -r '.description')
    AIDER_TASK_MODEL=$(echo "$TASK_INFO" | jq -r '.aider_model // empty') 

    # Process global files with proper quoting
    GLOBAL_FILES=""
    jq -r '.global_files[]? // empty' <<< "$TASK_INFO" | while IFS= read -r file_path; do
        if [ -n "$file_path" ]; then 
            GLOBAL_FILES="$GLOBAL_FILES \"$file_path\""
        fi
    done

    WINDOW_NUM=$((i+1))
    TASK_ID="task${WINDOW_NUM}_${RUN_ID}"

    echo ""
    echo "Preparing task $WINDOW_NUM: $DESCRIPTION_RAW"
    echo "  Guide: $GUIDE_FILE"
    echo "  Task ID: $TASK_ID"

    # Create a shell script that will be executed directly in the new Terminal window
    TERMINAL_SCRIPT="${TEMP_DIR}/terminal_cmd_${WINDOW_NUM}.sh"
    
    cat > "$TERMINAL_SCRIPT" << 'EOSCRIPT'
#!/bin/bash
set -euo pipefail

# Terminal window title will be set to the task ID
EOSCRIPT

    # Add configuration and command to the script with minimal escaping
    echo "cd \"$PROJECT_ROOT_ABS_PATH\"" >> "$TERMINAL_SCRIPT"
    echo "TASK_ID=\"$TASK_ID\"" >> "$TERMINAL_SCRIPT"
    
    # Add model environment variable if specified
    if [ -n "$AIDER_TASK_MODEL" ]; then
        echo "export AIDER_MODEL=\"$AIDER_TASK_MODEL\"" >> "$TERMINAL_SCRIPT"
    fi

    # Add environment setup - optional, depending on your needs
    cat >> "$TERMINAL_SCRIPT" << 'EOSCRIPT'
# Optional: load environment variables if needed
if [ -f ".env" ]; then
    echo "Loading environment from .env file"
    set -o allexport
    source .env
    set +o allexport
fi

# Set terminal title to the task ID
echo -ne "\033]0;${TASK_ID}\007"

# Check if aider is installed
if ! command -v aider &> /dev/null; then
    echo "Error: Aider is not installed. Please install it first."
    echo "You can install it with: pip install aider-chat"
    exit 1
fi

echo "======================================"
echo "  Feature Symphony Aider Task"
echo "======================================"
echo "Task ID: ${TASK_ID}"
echo "Working directory: $(pwd)"
echo "Starting Aider..."
echo "--------------------------------------"
EOSCRIPT

    # Add the actual aider command with proper quoting
    echo "aider \"$GUIDE_FILE\" $GLOBAL_FILES --message \"$PROMPT_RAW\" --yes --no-auto-commits" >> "$TERMINAL_SCRIPT"
    
    # Add the post-command text
    cat >> "$TERMINAL_SCRIPT" << 'EOSCRIPT'
echo -e "\n======================================"
echo "Aider Task Finished"
echo "This terminal window will remain open for review."
echo "Type \"exit\" or press Ctrl+D to close when done."
echo "======================================"
exec bash
EOSCRIPT

    chmod +x "$TERMINAL_SCRIPT"

    # Create a simple AppleScript file that just runs our terminal script
    APPLESCRIPT_FILE="${TEMP_DIR}/task_${WINDOW_NUM}.scpt"
    
    cat > "$APPLESCRIPT_FILE" << EOF
tell application "Terminal"
    do script "${TERMINAL_SCRIPT}"
end tell
EOF

    echo "  Executing AppleScript to open new Terminal window for task $WINDOW_NUM (ID: $TASK_ID)"
    
    # Run the AppleScript file
    osascript "$APPLESCRIPT_FILE"
    
    # Brief pause to allow Terminal window to open and script to start
    sleep 1
done

echo ""
echo "--- All Aider Tasks Launched in Separate Terminal Windows ---"
echo "Each task runs in its own Terminal window."
echo "Look for the new Terminal windows with titles matching the task IDs."
echo "The temporary scripts will be cleaned up automatically." 