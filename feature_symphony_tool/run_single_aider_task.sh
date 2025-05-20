#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR_SINGLE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
TOOL_ROOT="$SCRIPT_DIR_SINGLE"

echo "--- Standalone Aider Task Runner ---"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <path_to_feature_slice_guide.md>"
  echo "Example: $0 docs/feature_guides/my_slice_guide.md"
  echo "This script should be run from your main project's root directory."
  exit 1
fi

FEATURE_SLICE_GUIDE_REL_PATH="$1"
FEATURE_SLICE_GUIDE_ABS_PATH="$(pwd)/$FEATURE_SLICE_GUIDE_REL_PATH"

CONFIG_FILE_PATH="$TOOL_ROOT/config/config.yaml"
LAUNCH_AIDERS_SCRIPT_PATH="$TOOL_ROOT/bin/launch_aiders_terminal.sh"
PYTHON_SCRIPT_PATH="$TOOL_ROOT/src/orchestrator.py"
TOOL_RUN_ARTIFACTS_DIR_NAME="" # Will be read from config

# Check if running from project root
if [ ! -d ".git" ]; then
  echo "Warning: This doesn't appear to be a git repository root."
  echo "The feature_symphony_tool should be run from your project's root directory (where .git/ is)."
  read -p "Continue anyway? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

# Check if Python script exists
if [ ! -f "$PYTHON_SCRIPT_PATH" ]; then
  echo "Error: Python script not found at $PYTHON_SCRIPT_PATH"
  exit 1
fi

# Check if guide file exists
if [ ! -f "$FEATURE_SLICE_GUIDE_ABS_PATH" ]; then
  echo "Error: Guide file not found at $FEATURE_SLICE_GUIDE_ABS_PATH"
  exit 1
fi

# Check for Python
if ! command -v python3 &> /dev/null; then
  echo "Error: python3 could not be found. Please install Python 3."
  exit 1
fi

# Get TOOL_RUN_ARTIFACTS_DIR_NAME from config
TOOL_RUN_ARTIFACTS_DIR_NAME=$(grep -E "^tool_run_artifacts_dir:" "$CONFIG_FILE_PATH" | cut -d ":" -f2- | tr -d " \"'" || echo "runs")
TOOL_RUN_ARTIFACTS_DIR="$TOOL_ROOT/$TOOL_RUN_ARTIFACTS_DIR_NAME"

# Create a timestamped run ID
RUN_ID="single_$(date +"%Y%m%d_%H%M%S")"
echo "Run ID: $RUN_ID"

# Create run directory
if [ -n "$TOOL_RUN_ARTIFACTS_DIR_NAME" ]; then
  mkdir -p "$TOOL_RUN_ARTIFACTS_DIR/$RUN_ID"
  SINGLE_TASK_JSON="$TOOL_RUN_ARTIFACTS_DIR/$RUN_ID/aider_tasks.json"
else
  SINGLE_TASK_JSON="$TOOL_ROOT/aider_tasks_$RUN_ID.json"
fi

# Setup environment (load .env if exists)
ENV_FILE="$TOOL_ROOT/.env"
if [ -f "$ENV_FILE" ]; then
  echo "Loading environment variables from $ENV_FILE"
  set -o allexport
  source "$ENV_FILE"
  set +o allexport
fi

# Setup Python virtual environment if it exists
VENV_DIR="$TOOL_ROOT/.venv"
if [ -d "$VENV_DIR" ] && [ -f "$VENV_DIR/bin/activate" ]; then
  echo "Activating Python virtual environment at $VENV_DIR"
  source "$VENV_DIR/bin/activate"
fi

# Print working directory for clarity
echo "Project Root (where you ran the script): $(pwd)"
echo "Tool Root: $TOOL_ROOT"
echo "Feature Slice Guide: $FEATURE_SLICE_GUIDE_ABS_PATH"
echo "Output JSON will be saved to: $SINGLE_TASK_JSON"

echo "Calling Python orchestrator in single-guide mode..."
python3 "$PYTHON_SCRIPT_PATH" \
    --tool-root "$TOOL_ROOT" \
    --single-guide "$FEATURE_SLICE_GUIDE_ABS_PATH" \
    --config-file "$CONFIG_FILE_PATH" \
    --run-id "$RUN_ID" \
    --output-json-file "$SINGLE_TASK_JSON" \
    --project-root "$(pwd)"

exit_code=$?
if [ $exit_code -ne 0 ]; then
  echo "Error: Python orchestrator failed with exit code $exit_code"
  exit $exit_code
fi

# Check if the output file exists and is not empty
if [ ! -s "$SINGLE_TASK_JSON" ]; then
  echo "Error: The output JSON file is empty or was not created."
  exit 1
fi

echo "Launching Aider task..."
bash "$LAUNCH_AIDERS_SCRIPT_PATH" "$RUN_ID" "$SINGLE_TASK_JSON"

exit_code=$?
if [ $exit_code -ne 0 ]; then
  echo "Error: Aider launch script failed with exit code $exit_code"
  exit $exit_code
fi

echo "------------------------------------"
echo "Standalone Aider Task Completed"

# Check if we're on macOS
if command -v osascript >/dev/null 2>&1; then
  echo "On macOS: A new Terminal window should have opened with the Aider task."
  echo "Task ID: task1_${RUN_ID}"
  echo ""
  echo "You can interact with Aider directly in that Terminal window."
  echo "The window will remain open after Aider completes for your review."
  echo "When you're done, you can close the window or type 'exit'."
else
  echo "Error: This script is designed for macOS with AppleScript support."
  echo "On other platforms, you should run Aider directly:"
  echo "  cd $(pwd)"
  echo "  aider docs/feature_guides/your_guide.md --message \"Your prompt\" --no-auto-commits"
fi
echo "------------------------------------" 