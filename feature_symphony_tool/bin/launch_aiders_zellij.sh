#!/usr/bin/env bash
set -euo pipefail

echo "--- Aider Launch Script (Zellij) ---"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <RUN_ID> <tasks_json_file_path>"
  echo "Example: $0 myrun123 /path/to/feature_symphony_tool/runs/myrun123/aider_tasks.json"
  exit 1
fi

RUN_ID="$1"
TASKS_JSON_FILE="$2"

echo "RUN_ID: $RUN_ID"
echo "Tasks JSON File: $TASKS_JSON_FILE"

# Check for required commands
for cmd in jq zellij aider; do
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

# Load Zellij session name from JSON or default to a pattern
ZELLIJ_SESSION_NAME=$(jq -r '.zellij_session_name // empty' "$TASKS_JSON_FILE")
if [ -z "$ZELLIJ_SESSION_NAME" ]; then
    ZELLIJ_SESSION_PREFIX=$(jq -r '.zellij_session_prefix // "symphony_aider"' "$TASKS_JSON_FILE")
    ZELLIJ_SESSION_NAME="${ZELLIJ_SESSION_PREFIX}_${RUN_ID}"
fi

# Get the number of tasks
TASK_COUNT=$(jq '.tasks | length' "$TASKS_JSON_FILE")

# Create the Zellij session if it doesn't exist
if ! zellij list-sessions 2>/dev/null | grep -q "$ZELLIJ_SESSION_NAME"; then
    echo "Creating new Zellij session: $ZELLIJ_SESSION_NAME"
    # Create a new session with the -s flag and immediately detach
    zellij -s "$ZELLIJ_SESSION_NAME" options --on-force-close "detach"
    sleep 1
fi

# Process each task
for (( i=0; i<$TASK_COUNT; i++ ))
do
    # Get task info from JSON
    TASK_INFO=$(jq -c ".tasks[$i]" "$TASKS_JSON_FILE")
    GUIDE_FILE=$(echo "$TASK_INFO" | jq -r '.guide_file')
    PROMPT=$(echo "$TASK_INFO" | jq -r '.prompt')
    DESCRIPTION=$(echo "$TASK_INFO" | jq -r '.description')
    # Convert global_files array to a space-separated string
    GLOBAL_FILES=$(echo "$TASK_INFO" | jq -r '.global_files | join(" ")')
    
    # Create a safe window name
    WINDOW_NUM=$((i+1))
    WINDOW_NAME="task_${WINDOW_NUM}_$(echo "$DESCRIPTION" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]_-' | cut -c1-20)"
    
    # Build the Aider command
    # The --yes flag prevents Aider from asking for confirmation
    AIDER_CMD="aider $GUIDE_FILE $GLOBAL_FILES --message \"$PROMPT\" --yes"
    
    # Launch the task in a new Zellij pane
    echo "Launching task $WINDOW_NUM: $DESCRIPTION"
    
    # First attach to the session
    ZELLIJ_SESSION="$ZELLIJ_SESSION_NAME" zellij action new-pane --name "$WINDOW_NAME" --cwd "$(pwd)" -- bash -c "echo 'Task $WINDOW_NUM: $DESCRIPTION'; echo 'Guide: $GUIDE_FILE'; echo 'Running Aider...'; $AIDER_CMD; echo 'Aider finished. Press Ctrl+P then X to close this pane.'; exec bash"
    
    # Allow a brief moment for the pane to be created before launching the next one
    sleep 1
done

echo "All Aider tasks launched in Zellij session: $ZELLIJ_SESSION_NAME"
echo "To attach to the session, run: 'zellij attach $ZELLIJ_SESSION_NAME'"
echo "To switch between panes once attached: Ctrl+P then arrow keys"
echo "To close a pane: Ctrl+P then X" 