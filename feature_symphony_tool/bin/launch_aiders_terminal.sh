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

# Terminal window positioning configuration
WINDOW_WIDTH=800
WINDOW_HEIGHT=600
WINDOWS_PER_COLUMN=6
COLUMN_WIDTH=$((WINDOW_WIDTH + 50)) # Add some gap between columns
WINDOW_VERTICAL_OFFSET=30  # Slightly overlap windows vertically (title bar height)
SCREEN_TOP_MARGIN=25       # Start near the top of the screen
SCREEN_LEFT_MARGIN=10      # Start near the left edge
MAX_COLUMNS=2              # Maximum number of columns before wrapping back to the left side
COLUMN_GROUP_OFFSET=200    # Larger vertical offset for each group of columns when wrapping

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
    echo "aider \"$GUIDE_FILE\" $GLOBAL_FILES --message \"$PROMPT_RAW\" --yes" >> "$TERMINAL_SCRIPT"
    
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
    
    # Calculate window position with wrap-around for many windows
    BASE_COLUMN_INDEX=$((i / WINDOWS_PER_COLUMN))
    ROW_INDEX=$((i % WINDOWS_PER_COLUMN))
    
    # When exceeding MAX_COLUMNS, wrap back to left side with vertical offset
    GROUP_INDEX=$((BASE_COLUMN_INDEX / MAX_COLUMNS))  # Which group of columns (0, 1, 2, etc.)
    COLUMN_INDEX=$((BASE_COLUMN_INDEX % MAX_COLUMNS)) # Column within the group (0 to MAX_COLUMNS-1)
    
    LEFT=$((SCREEN_LEFT_MARGIN + COLUMN_INDEX * COLUMN_WIDTH))
    
    # Apply vertical offset for each group and add row position within the group
    VERTICAL_GROUP_OFFSET=$((GROUP_INDEX * COLUMN_GROUP_OFFSET))
    TOP=$((SCREEN_TOP_MARGIN + VERTICAL_GROUP_OFFSET + ROW_INDEX * WINDOW_VERTICAL_OFFSET))
    
    RIGHT=$((LEFT + WINDOW_WIDTH))
    BOTTOM=$((TOP + WINDOW_HEIGHT))
    
    cat > "$APPLESCRIPT_FILE" << EOF
tell application "Terminal"
    set newWindow to do script "${TERMINAL_SCRIPT}"
    delay 0.5
    set bounds of front window to {$LEFT, $TOP, $RIGHT, $BOTTOM}
    set custom title of front window to "${TASK_ID}"
end tell
EOF

    echo "  Executing AppleScript to open new Terminal window for task $WINDOW_NUM (ID: $TASK_ID)"
    echo "  Window position: {$LEFT, $TOP, $RIGHT, $BOTTOM}"
    
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