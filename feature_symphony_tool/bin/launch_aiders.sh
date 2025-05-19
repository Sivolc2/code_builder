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
TMUX_SESSION_NAME=$(jq -r '.tmux_session_name // "symphony_aider_'$RUN_ID'"' "$TASKS_JSON_FILE")
TASK_COUNT=$(jq -r '.tasks | length' "$TASKS_JSON_FILE")

echo "Will launch $TASK_COUNT Aider task(s) in tmux session: $TMUX_SESSION_NAME"

# Check if session already exists
if tmux has-session -t "$TMUX_SESSION_NAME" 2>/dev/null; then
    echo "Error: tmux session '$TMUX_SESSION_NAME' already exists."
    echo "Use 'tmux attach-session -t $TMUX_SESSION_NAME' to connect to it."
    echo "Or kill the session with 'tmux kill-session -t $TMUX_SESSION_NAME' and try again."
    exit 1
fi

# Create tmux session
echo "Creating tmux session: $TMUX_SESSION_NAME"
tmux new-session -d -s "$TMUX_SESSION_NAME" -n "dashboard"

# Add a dashboard window with task information
tmux send-keys -t "$TMUX_SESSION_NAME:dashboard" "echo 'Feature Symphony Dashboard - Run ID: $RUN_ID'" C-m
tmux send-keys -t "$TMUX_SESSION_NAME:dashboard" "echo '----------------------------------------'" C-m
tmux send-keys -t "$TMUX_SESSION_NAME:dashboard" "echo 'Tasks: $TASK_COUNT'" C-m
tmux send-keys -t "$TMUX_SESSION_NAME:dashboard" "echo 'Tasks JSON: $TASKS_JSON_FILE'" C-m
tmux send-keys -t "$TMUX_SESSION_NAME:dashboard" "echo ''" C-m
tmux send-keys -t "$TMUX_SESSION_NAME:dashboard" "echo 'Task List:'" C-m
tmux send-keys -t "$TMUX_SESSION_NAME:dashboard" "jq -r '.tasks[] | \"* \" + .description + \" (\" + .guide_file + \")\"' \"$TASKS_JSON_FILE\"" C-m
tmux send-keys -t "$TMUX_SESSION_NAME:dashboard" "echo ''" C-m
tmux send-keys -t "$TMUX_SESSION_NAME:dashboard" "echo 'Navigate between windows: Ctrl+b <window number>'" C-m
tmux send-keys -t "$TMUX_SESSION_NAME:dashboard" "echo 'Detach from session: Ctrl+b d'" C-m

# Launch each Aider task in its own window
for ((i=0; i<TASK_COUNT; i++)); do
    # Extract info for this task
    TASK_INFO=$(jq -r ".tasks[$i]" "$TASKS_JSON_FILE")
    GUIDE_FILE=$(echo "$TASK_INFO" | jq -r '.guide_file')
    PROMPT=$(echo "$TASK_INFO" | jq -r '.prompt')
    DESCRIPTION=$(echo "$TASK_INFO" | jq -r '.description')
    # Convert global_files array to a space-separated string
    GLOBAL_FILES=$(echo "$TASK_INFO" | jq -r '.global_files | join(" ")')
    
    # Use task number+1 for window index (since dashboard is 0)
    WINDOW_NUM=$((i+1))
    WINDOW_NAME="task-$WINDOW_NUM"
    
    echo "Setting up window $WINDOW_NUM for task: $DESCRIPTION"
    
    # Create a new window for this task
    tmux new-window -t "$TMUX_SESSION_NAME:$WINDOW_NUM" -n "$WINDOW_NAME"
    
    # Build the Aider command
    # The --yes flag prevents Aider from asking for confirmation
    AIDER_CMD="aider $GUIDE_FILE $GLOBAL_FILES --message \"$PROMPT\" --yes"
    
    # Send command to the tmux window
    tmux send-keys -t "$TMUX_SESSION_NAME:$WINDOW_NAME" "echo 'Task $WINDOW_NUM: $DESCRIPTION'" C-m
    tmux send-keys -t "$TMUX_SESSION_NAME:$WINDOW_NAME" "echo 'Guide: $GUIDE_FILE'" C-m
    tmux send-keys -t "$TMUX_SESSION_NAME:$WINDOW_NAME" "echo 'Global Context Files: $GLOBAL_FILES'" C-m
    tmux send-keys -t "$TMUX_SESSION_NAME:$WINDOW_NAME" "echo 'Executing: $AIDER_CMD'" C-m
    tmux send-keys -t "$TMUX_SESSION_NAME:$WINDOW_NAME" "$AIDER_CMD" C-m
done

echo "All Aider tasks launched in tmux session: $TMUX_SESSION_NAME"
echo "To attach to the session, run: tmux attach-session -t $TMUX_SESSION_NAME"
echo "To detach from the session (once attached): Ctrl+b d"
echo "To switch between windows once attached: Ctrl+b <window number>" 