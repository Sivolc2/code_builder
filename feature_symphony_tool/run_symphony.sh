#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR_SYMPHONY="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
TOOL_ROOT="$SCRIPT_DIR_SYMPHONY" # Assuming this script is in feature_symphony_tool/

echo "--- Feature Symphony Orchestrator ---"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <path_to_symphony_xml_file>"
  echo "Example: $0 docs/my_feature_plan.xml"
  echo "This script should be run from your main project's root directory."
  exit 1
fi

SYMPHONY_XML_FILE_REL_PATH="$1" # Path relative to current PWD (project root)
SYMPHONY_XML_FILE_ABS_PATH="$(pwd)/$SYMPHONY_XML_FILE_REL_PATH"


CONFIG_FILE_PATH="$TOOL_ROOT/config/config.yaml"
PYTHON_SCRIPT_PATH="$TOOL_ROOT/src/orchestrator.py"
LAUNCH_AIDERS_SCRIPT_PATH="$TOOL_ROOT/bin/launch_aiders.sh"
TOOL_RUN_ARTIFACTS_DIR_NAME="" # Will be read from config

# Check if running from project root (heuristic: .git exists)
if [ ! -d ".git" ]; then
    echo "Warning: This script is intended to be run from your main project's root directory."
    # exit 1 # Or allow continuation with a warning
fi


echo "Symphony XML File (Absolute): $SYMPHONY_XML_FILE_ABS_PATH"
echo "Tool Root: $TOOL_ROOT"
echo "Config File: $CONFIG_FILE_PATH"

if [ ! -f "$SYMPHONY_XML_FILE_ABS_PATH" ]; then
    echo "Error: Symphony XML file not found at $SYMPHONY_XML_FILE_ABS_PATH"
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
    # Optionally, you could attempt to create and install here, but that's more complex.
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


RUN_ID=$(date +"%Y%m%d_%H%M%S")
echo "Generated RUN_ID: $RUN_ID"

# Determine tool's internal run artifacts directory from config
# Using a simple grep/awk for now, Python would be more robust for YAML parsing
TOOL_RUN_ARTIFACTS_DIR_NAME=$(grep "tool_run_artifacts_dir:" "$CONFIG_FILE_PATH" | awk '{print $2}' | tr -d '"' | tr -d "'")
if [ -z "$TOOL_RUN_ARTIFACTS_DIR_NAME" ]; then
    echo "Warning: 'tool_run_artifacts_dir' not found or empty in config. Defaulting to no specific artifacts dir."
    # Set a default
    TOOL_RUN_ARTIFACTS_DIR_NAME="runs"
fi

# Define where the orchestrator's JSON output will be stored
ORCHESTRATOR_OUTPUT_JSON=""
if [ -n "$TOOL_RUN_ARTIFACTS_DIR_NAME" ]; then
    # Create run-specific directory inside the tool's structure for its artifacts
    CURRENT_TOOL_RUN_DIR="$TOOL_ROOT/$TOOL_RUN_ARTIFACTS_DIR_NAME/$RUN_ID"
    mkdir -p "$CURRENT_TOOL_RUN_DIR"
    ORCHESTRATOR_OUTPUT_JSON="$CURRENT_TOOL_RUN_DIR/aider_tasks.json"
else
    # Fallback if no artifacts dir, though less ideal. Could use /tmp or project root with .prefix
    ORCHESTRATOR_OUTPUT_JSON="$TOOL_ROOT/aider_tasks_${RUN_ID}.json" # Temporary location
    echo "Warning: Storing orchestrator output JSON in $ORCHESTRATOR_OUTPUT_JSON as tool_run_artifacts_dir is not set."
fi

# Check if repo_contents.txt exists in project root for context
REPO_CONTEXT_FILE="repo_contents.txt"
REPO_CONTEXT_ARG=""
if [ -f "$REPO_CONTEXT_FILE" ]; then
    echo "Found repository content dump at $REPO_CONTEXT_FILE. Will use for additional context."
    REPO_CONTEXT_ARG="--repo-context-file $REPO_CONTEXT_FILE"
else
    echo "No repository content dump found at $REPO_CONTEXT_FILE."
    echo "If you want to provide repository context to Gemini, run: $TOOL_ROOT/bin/dump_repo.sh"
fi

echo "Running Python orchestrator to generate slice guides and Aider tasks..."
# CWD for orchestrator.py will be the project root.
# It needs to know where config.yaml is (relative to TOOL_ROOT)
# and where to output guides (relative to CWD / project root, as per config)
# and where its own output JSON should go.
python3 "$PYTHON_SCRIPT_PATH" \
    --symphony-xml "$SYMPHONY_XML_FILE_ABS_PATH" \
    --config-file "$CONFIG_FILE_PATH" \
    --run-id "$RUN_ID" \
    --output-json-file "$ORCHESTRATOR_OUTPUT_JSON" \
    --project-root "$(pwd)" $REPO_CONTEXT_ARG

if [ $? -ne 0 ]; then
    echo "Error: Python orchestrator script failed."
    exit 1
fi

if [ ! -f "$ORCHESTRATOR_OUTPUT_JSON" ]; then
    echo "Error: Orchestrator did not produce the expected JSON output at $ORCHESTRATOR_OUTPUT_JSON."
    exit 1
fi

echo "Orchestrator finished. Aider tasks defined in: $ORCHESTRATOR_OUTPUT_JSON"
echo "Launching Aider instances via tmux..."

bash "$LAUNCH_AIDERS_SCRIPT_PATH" "$RUN_ID" "$ORCHESTRATOR_OUTPUT_JSON"

if [ $? -ne 0 ]; then
    echo "Error: Aider launch script failed."
    exit 1
fi

echo "--- Feature Symphony Completed ---"
echo "Aider agents should be running in a tmux session."
echo "Attach to session (example): tmux attach-session -t symphony_aider_$RUN_ID"
echo "---------------------------------" 