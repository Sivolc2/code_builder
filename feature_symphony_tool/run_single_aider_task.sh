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
LAUNCH_AIDERS_SCRIPT_PATH="$TOOL_ROOT/bin/launch_aiders.sh"
PYTHON_SCRIPT_PATH="$TOOL_ROOT/src/orchestrator.py"
TOOL_RUN_ARTIFACTS_DIR_NAME="" # Will be read from config

# Check if running from project root
if [ ! -d ".git" ]; then
    echo "Warning: This script is intended to be run from your main project's root directory."
fi

echo "Feature Slice Guide (Absolute): $FEATURE_SLICE_GUIDE_ABS_PATH"
echo "Tool Root: $TOOL_ROOT"
echo "Config File: $CONFIG_FILE_PATH"

if [ ! -f "$FEATURE_SLICE_GUIDE_ABS_PATH" ]; then
    echo "Error: Feature slice guide file not found at $FEATURE_SLICE_GUIDE_ABS_PATH"
    exit 1
fi
if [ ! -f "$CONFIG_FILE_PATH" ]; then
    echo "Error: Tool configuration file not found at $CONFIG_FILE_PATH"
    echo "Please ensure 'config/config.yaml' exists in $TOOL_ROOT."
    echo "You can copy 'config/config.yaml.template' to 'config/config.yaml' and edit it."
    exit 1
fi

# Activate Python virtual environment if it exists within the tool directory
VENV_PATH="$TOOL_ROOT/.venv"
if [ -d "$VENV_PATH" ]; then
    echo "Activating Python virtual environment from $VENV_PATH..."
    # shellcheck source=/dev/null
    source "$VENV_PATH/bin/activate"
else
    echo "Warning: Python virtual environment not found at $VENV_PATH."
    echo "Attempting to use system Python. Ensure dependencies from requirements.txt are installed."
fi

# Source .env file from tool directory if it exists
ENV_FILE_PATH="$TOOL_ROOT/.env"
if [ -f "$ENV_FILE_PATH" ]; then
    echo "Sourcing environment variables from $ENV_FILE_PATH..."
    set -a # Automatically export all variables
    # shellcheck source=/dev/null
    source "$ENV_FILE_PATH"
    set +a
else
    echo "Info: .env file not found at $ENV_FILE_PATH. Relying on pre-set environment variables."
fi

RUN_ID="single_task_$(date +"%Y%m%d_%H%M%S")"
echo "Generated RUN_ID for single task: $RUN_ID"

# Determine tool's internal run artifacts directory from config
# Using a simple grep/awk for now, Python would be more robust for YAML parsing
TOOL_RUN_ARTIFACTS_DIR_NAME=$(grep "tool_run_artifacts_dir:" "$CONFIG_FILE_PATH" | awk '{print $2}' | tr -d '"' | tr -d "'")
if [ -z "$TOOL_RUN_ARTIFACTS_DIR_NAME" ]; then
    echo "Warning: 'tool_run_artifacts_dir' not found or empty in config. Defaulting to 'runs'."
    TOOL_RUN_ARTIFACTS_DIR_NAME="runs"
fi

# Define where the orchestrator's JSON output will be stored
SINGLE_TASK_JSON=""
if [ -n "$TOOL_RUN_ARTIFACTS_DIR_NAME" ]; then
    CURRENT_TOOL_RUN_DIR="$TOOL_ROOT/$TOOL_RUN_ARTIFACTS_DIR_NAME/$RUN_ID"
    mkdir -p "$CURRENT_TOOL_RUN_DIR"
    SINGLE_TASK_JSON="$CURRENT_TOOL_RUN_DIR/single_aider_task.json"
else
    SINGLE_TASK_JSON="$TOOL_ROOT/single_aider_task_${RUN_ID}.json"
    echo "Warning: Storing orchestrator output JSON in $SINGLE_TASK_JSON as tool_run_artifacts_dir is not set."
fi

echo "Calling Python orchestrator in single-guide mode..."
python3 "$PYTHON_SCRIPT_PATH" \
    --single-guide "$FEATURE_SLICE_GUIDE_ABS_PATH" \
    --config-file "$CONFIG_FILE_PATH" \
    --run-id "$RUN_ID" \
    --output-json-file "$SINGLE_TASK_JSON" \
    --project-root "$(pwd)"

if [ $? -ne 0 ]; then
    echo "Error: Python orchestrator script (single-guide mode) failed."
    exit 1
fi
if [ ! -f "$SINGLE_TASK_JSON" ]; then
    echo "Error: Orchestrator (single-guide mode) did not produce JSON output at $SINGLE_TASK_JSON."
    exit 1
fi

echo "Orchestrator finished. Single Aider task defined in: $SINGLE_TASK_JSON"
echo "Launching Aider via tmux..."

bash "$LAUNCH_AIDERS_SCRIPT_PATH" "$RUN_ID" "$SINGLE_TASK_JSON"

if [ $? -ne 0 ]; then
    echo "Error: Aider launch script failed."
    exit 1
fi

TMUX_SESSION_PREFIX=$(grep "tmux_session_prefix:" "$CONFIG_FILE_PATH" | awk '{print $2}' | tr -d '"' | tr -d "'")
if [ -z "$TMUX_SESSION_PREFIX" ]; then 
    TMUX_SESSION_PREFIX="symphony_aider" 
fi

echo "--- Standalone Aider Task Completed ---"
echo "Aider agent should be running in a tmux session."
echo "Attach to session (example): tmux attach-session -t ${TMUX_SESSION_PREFIX}_${RUN_ID}"
echo "------------------------------------" 