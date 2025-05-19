#!/usr/bin/env bash
set -euo pipefail

echo "--- Aider Launch Script (Zellij - New Window Per Task for macOS) ---"

if ! command -v osascript >/dev/null 2>&1; then
  echo "Error: 'osascript' command not found. This script is designed for macOS."
  echo "If you are not on macOS, this launch method will not work."
  exit 1
fi

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <RUN_ID> <tasks_json_file_path>"
  echo "Example: $0 myrun123 /path/to/feature_symphony_tool/runs/myrun123/aider_tasks.json"
  exit 1
fi

RUN_ID="$1"
TASKS_JSON_FILE="$2"
PROJECT_ROOT_ABS_PATH="$(pwd)" # Script is run from project root

echo "RUN_ID: $RUN_ID"
echo "Tasks JSON File: $TASKS_JSON_FILE"
echo "Project Root (for new Terminals): $PROJECT_ROOT_ABS_PATH"
echo "DEBUG: This script will open a new Terminal window for each Aider task."

# Check for required commands (jq, zellij, aider are checked by the temp script)
for cmd in jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: Required command '$cmd' not found."
    echo "Please install $cmd and try again."
    exit 1
  fi
done

if [ ! -f "$TASKS_JSON_FILE" ]; then
    echo "Error: Tasks JSON file not found at $TASKS_JSON_FILE"
    exit 1
fi

# Get Zellij session prefix from JSON (set in config.yaml)
# This prefix is used to form unique session names for each task window.
ZELLIJ_SESSION_BASE_PREFIX=$(jq -r '.zellij_session_prefix // "symphony_aider"' "$TASKS_JSON_FILE")

TASK_COUNT=$(jq '.tasks | length' "$TASKS_JSON_FILE")
echo "Found $TASK_COUNT tasks to launch."

TEMP_SCRIPTS_TO_CLEAN=()

# Process each task
for (( i=0; i<$TASK_COUNT; i++ ))
do
    TASK_INFO=$(jq -c ".tasks[$i]" "$TASKS_JSON_FILE")
    GUIDE_FILE=$(echo "$TASK_INFO" | jq -r '.guide_file')
    PROMPT_RAW=$(echo "$TASK_INFO" | jq -r '.prompt')
    DESCRIPTION_RAW=$(echo "$TASK_INFO" | jq -r '.description')
    AIDER_TASK_MODEL=$(echo "$TASK_INFO" | jq -r '.aider_model // empty') # Get aider_model from task or empty string

    # Prepare global files arguments string for the Aider command
    # Each file path needs to be individually quoted using printf %q.
    GLOBAL_FILES_ARGS_STR=""
    jq -r '.global_files[]' <<< "$TASK_INFO" | while IFS= read -r file_path; do
        GLOBAL_FILES_ARGS_STR+=" $(printf %q "$file_path")"
    done

    WINDOW_NUM=$((i+1))
    # Create a simpler session name format
    UNIQUE_ZELLIJ_SESSION_NAME="fs_${RUN_ID}_${WINDOW_NUM}"
    
    # Debug output for session name
    echo "DEBUG: Generated Zellij session name: '$UNIQUE_ZELLIJ_SESSION_NAME'"
    echo "DEBUG: Session name length: ${#UNIQUE_ZELLIJ_SESSION_NAME}"

    TEMP_SCRIPT_PATH="/tmp/fs_task_runner_${RUN_ID}_${WINDOW_NUM}.sh"
    TEMP_SCRIPTS_TO_CLEAN+=("$TEMP_SCRIPT_PATH")

    echo "Preparing task $WINDOW_NUM: $DESCRIPTION_RAW"
    echo "  Guide: $GUIDE_FILE"
    echo "  Zellij Session: $UNIQUE_ZELLIJ_SESSION_NAME"
    echo "  Temp Script: $TEMP_SCRIPT_PATH"

    # Create the temporary shell script that will be run in the new Terminal window
    cat > "$TEMP_SCRIPT_PATH" <<EOF
#!/bin/bash
# Feature Symphony Task Runner (macOS New Window Mode)
# Run ID: ${RUN_ID}, Task: ${WINDOW_NUM}

# Exit on error, treat unset variables as an error
set -euo pipefail

# --- Configuration (embedded from parent script) ---
PROJECT_ROOT_ABS_PATH_TASK="${PROJECT_ROOT_ABS_PATH}"
GUIDE_FILE_TASK="${GUIDE_FILE}"
GLOBAL_FILES_ARGS_STR_TASK="${GLOBAL_FILES_ARGS_STR}" # Already %q escaped
PROMPT_TASK_RAW="${PROMPT_RAW}" # Raw prompt string
AIDER_TASK_MODEL_TASK="${AIDER_TASK_MODEL}"
DESCRIPTION_TASK_RAW="${DESCRIPTION_RAW}"
UNIQUE_ZELLIJ_SESSION_NAME_TASK="${UNIQUE_ZELLIJ_SESSION_NAME}"
# --- End Configuration ---

# Function to display information and run Aider within Zellij
run_aider_in_zellij() {
    echo "---------------------------------------------------------------------"
    echo " Feature Symphony - Aider Task"
    echo "---------------------------------------------------------------------"
    echo " Description : \${DESCRIPTION_TASK_RAW}"
    echo " Guide File  : \${GUIDE_FILE_TASK}"
    echo " Project Root: \${PROJECT_ROOT_ABS_PATH_TASK}"
    echo " Zellij Sess.: \${UNIQUE_ZELLIJ_SESSION_NAME_TASK}"
    echo " Aider Model : \${AIDER_TASK_MODEL_TASK:-\${AIDER_MODEL:-(Aider default)}}"
    echo "---------------------------------------------------------------------"
    echo ""
    echo "DEBUG: Checking for required commands (aider, zellij)..."
    for cmd_check in aider zellij; do
      if ! command -v "\$cmd_check" >/dev/null 2>&1; then
        echo "Error: Required command '\$cmd_check' not found. Please install it."
        exit 1
      fi
    done
    echo "DEBUG: Required commands found."
    echo ""

    cd "\${PROJECT_ROOT_ABS_PATH_TASK}" || { echo "Error: Failed to cd to project root '\${PROJECT_ROOT_ABS_PATH_TASK}'"; exit 1; }
    echo "Changed directory to: \$(pwd)"
    echo ""

    # Set AIDER_MODEL environment variable if provided for the task
    local aider_env_prefix=""
    if [ -n "\${AIDER_TASK_MODEL_TASK}" ]; then
        aider_env_prefix="AIDER_MODEL=\${AIDER_TASK_MODEL_TASK} "
    elif [ -n "\${AIDER_MODEL:-}" ]; then
        aider_env_prefix="AIDER_MODEL=\${AIDER_MODEL} "
    fi

    # Construct the Aider command
    local aider_cmd="\${aider_env_prefix}aider \${GUIDE_FILE_TASK} \${GLOBAL_FILES_ARGS_STR_TASK} --message \"\${PROMPT_TASK_RAW}\" --yes"
    
    echo "Executing Aider command inside Zellij:"
    echo "$ \${aider_cmd}"
    echo "--- Aider Output Starts Below ---"

    # Create a temporary command script
    local temp_cmd_script="/tmp/aider_cmd_\${UNIQUE_ZELLIJ_SESSION_NAME_TASK}.sh"
    
    cat > "\${temp_cmd_script}" << 'CMDSCRIPT'
#!/bin/bash
echo "Launching Aider..."
CMDSCRIPT
    
    # Append the actual command to avoid heredoc variable expansion issues
    echo "\${aider_cmd}" >> "\${temp_cmd_script}"
    
    # Add the rest of the script
    cat >> "\${temp_cmd_script}" << 'CMDSCRIPT'
echo -e "\n--- Aider Task Finished ---"
echo "This Zellij session will remain. Type \"exit\" or Ctrl+D to close this pane/window."
exec bash
CMDSCRIPT
    
    chmod +x "\${temp_cmd_script}"
    
    # Start a new Zellij session
    echo "Starting Zellij session: \${UNIQUE_ZELLIJ_SESSION_NAME_TASK}"
    zellij --session "\${UNIQUE_ZELLIJ_SESSION_NAME_TASK}" options --on-force-close "detach"
    
    # Wait a moment for the session to initialize
    sleep 2
    
    # Run the Aider command in the session
    zellij attach "\${UNIQUE_ZELLIJ_SESSION_NAME_TASK}" -c "\${temp_cmd_script}"
    
    # Clean up temp script
    rm -f "\${temp_cmd_script}"
}

# Execute the main function
run_aider_in_zellij
EOF

    chmod +x "$TEMP_SCRIPT_PATH"

    # Create AppleScript command to open a new Terminal window and run the temp script
    # Escape double quotes in the script path for AppleScript
    APPLESCRIPT_CMD="tell application \"Terminal\" to do script \"${TEMP_SCRIPT_PATH//\"/\\\"}\""

    echo "Executing AppleScript to open new Terminal for task $WINDOW_NUM (Zellij: $UNIQUE_ZELLIJ_SESSION_NAME)"
    osascript -e "$APPLESCRIPT_CMD"

    # Brief pause to allow Terminal window to open and script to start
    sleep 2
done

echo "--- All Aider Tasks Launched in Separate Terminal Windows ---"
echo "Each task runs in its own Terminal window with a unique Zellij session."
echo "Look for new Terminal windows."
echo "Temporary runner scripts were created in /tmp/ and will be cleaned up."

# Clean up temporary scripts
if [ ${#TEMP_SCRIPTS_TO_CLEAN[@]} -gt 0 ]; then
    echo "Cleaning up temporary task runner scripts..."
    for temp_file in "${TEMP_SCRIPTS_TO_CLEAN[@]}"; do
        rm -f "$temp_file"
        echo "  Removed: $temp_file"
    done
    echo "Cleanup complete."
fi 