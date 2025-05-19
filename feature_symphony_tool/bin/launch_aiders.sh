#!/usr/bin/env bash
set -euo pipefail

echo "--- Aider Launch Script ---"

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
for cmd in jq tmux aider; do
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

# Load tmux session name from JSON or default to a pattern
TMUX_SESSION_NAME=$(jq -r '.tmux_session_name // empty' "$TASKS_JSON_FILE")
if [ -z "$TMUX_SESSION_NAME" ]; then
    TMUX_SESSION_PREFIX=$(jq -r '.tmux_session_prefix // "symphony_aider"' "$TASKS_JSON_FILE")
    TMUX_SESSION_NAME="${TMUX_SESSION_PREFIX}_${RUN_ID}"
fi

# Create a new tmux session without attaching to it
tmux new-session -d -s "$TMUX_SESSION_NAME" -n "control" 2>/dev/null || {
  echo "Session $TMUX_SESSION_NAME already exists. Using existing session."
}

# Get the number of tasks
TASK_COUNT=$(jq '.tasks | length' "$TASKS_JSON_FILE")

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
    
    # Incrementally create new tmux windows for each task
    WINDOW_NUM=$((i+1))
    WINDOW_NAME="task_$WINDOW_NUM"
    
    # Create a new window for this task
    tmux new-window -t "$TMUX_SESSION_NAME:$WINDOW_NUM" -n "$WINDOW_NAME"
    
    # Build the Aider command
    # The --yes flag prevents Aider from asking for confirmation
    AIDER_CMD="aider $GUIDE_FILE $GLOBAL_FILES --message \"$PROMPT\" --yes"
    
    # Send command to the tmux window
    tmux send-keys -t "$TMUX_SESSION_NAME:$WINDOW_NUM" "echo 'Task $WINDOW_NUM: $DESCRIPTION'" C-m
    tmux send-keys -t "$TMUX_SESSION_NAME:$WINDOW_NUM" "echo 'Guide: $GUIDE_FILE'" C-m
    tmux send-keys -t "$TMUX_SESSION_NAME:$WINDOW_NUM" "echo 'Running Aider...'" C-m
    tmux send-keys -t "$TMUX_SESSION_NAME:$WINDOW_NUM" "$AIDER_CMD" C-m
done

echo "All Aider tasks launched in tmux session: $TMUX_SESSION_NAME"
echo "To attach to the session, run: 'tmux attach-session -t $TMUX_SESSION_NAME'"
echo "To detach from the session (once attached): Ctrl+b d"
echo "To switch between windows once attached: Ctrl+b <window number>" 