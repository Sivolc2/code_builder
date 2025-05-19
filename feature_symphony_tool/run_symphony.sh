#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR_SYMPHONY="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
TOOL_ROOT="$SCRIPT_DIR_SYMPHONY" # Assuming this script is in feature_symphony_tool/

echo "--- Feature Symphony Orchestrator ---"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <path_to_symphony_xml_file> [--threads N]"
  echo "Example: $0 docs/my_feature_plan.xml"
  echo "Example with threads: $0 docs/my_feature_plan.xml --threads 4"
  echo "This script should be run from your main project's root directory."
  exit 1
fi

SYMPHONY_XML_FILE_REL_PATH="$1" # Path relative to current PWD (project root)
SYMPHONY_XML_FILE_ABS_PATH="$(pwd)/$SYMPHONY_XML_FILE_REL_PATH"

# Check for --threads option
THREADS=1 # Default to 1 thread
if [[ $# -ge 3 && "$2" == "--threads" ]]; then
  THREADS="$3"
  # Validate that THREADS is a number
  if ! [[ "$THREADS" =~ ^[0-9]+$ ]]; then
    echo "Error: Threads value must be a positive integer"
    exit 1
  fi
  echo "Using $THREADS thread(s) for guide generation"
fi

CONFIG_FILE_PATH="$TOOL_ROOT/config/config.yaml"
PYTHON_SCRIPT_PATH="$TOOL_ROOT/src/orchestrator.py"
LAUNCH_AIDERS_SCRIPT_PATH="$TOOL_ROOT/bin/launch_aiders_terminal.sh"
TOOL_RUN_ARTIFACTS_DIR_NAME="" # Will be read from config

# Ensure we're run from project root
if [ ! -d ".git" ]; then
  echo "Warning: This doesn't appear to be a git repository root."
  echo "The feature_symphony_tool should be run from your project's root directory (where .git/ is)."
  read -p "Continue anyway? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

# Check if config exists
if [ ! -f "$CONFIG_FILE_PATH" ]; then
  echo "Error: Configuration file not found at $CONFIG_FILE_PATH"
  echo "Copy config.yaml.template to config.yaml and edit it with your settings."
  exit 1
fi

# Check if Python script exists
if [ ! -f "$PYTHON_SCRIPT_PATH" ]; then
  echo "Error: Python script not found at $PYTHON_SCRIPT_PATH"
  exit 1
fi

# Check for Python
if ! command -v python3 &> /dev/null; then
  echo "Error: python3 could not be found. Please install Python 3."
  exit 1
fi

# Check if SYMPHONY_XML_FILE exists
if [ ! -f "$SYMPHONY_XML_FILE_ABS_PATH" ]; then
  echo "Error: Symphony XML file not found at $SYMPHONY_XML_FILE_ABS_PATH"
  exit 1
fi

# Get TOOL_RUN_ARTIFACTS_DIR_NAME from config
TOOL_RUN_ARTIFACTS_DIR_NAME=$(grep -E "^tool_run_artifacts_dir:" "$CONFIG_FILE_PATH" | cut -d ":" -f2- | tr -d " \"'" || echo "runs")
TOOL_RUN_ARTIFACTS_DIR="$TOOL_ROOT/$TOOL_RUN_ARTIFACTS_DIR_NAME"

# Create a timestamped run ID
RUN_ID=$(date +"%Y%m%d_%H%M%S")
echo "Run ID: $RUN_ID"

# Create run directory
if [ -n "$TOOL_RUN_ARTIFACTS_DIR_NAME" ]; then
  mkdir -p "$TOOL_RUN_ARTIFACTS_DIR/$RUN_ID"
  AIDER_TASKS_JSON_PATH="$TOOL_RUN_ARTIFACTS_DIR/$RUN_ID/aider_tasks.json"
else
  AIDER_TASKS_JSON_PATH="$TOOL_ROOT/aider_tasks_$RUN_ID.json"
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
echo "Symphony XML File: $SYMPHONY_XML_FILE_ABS_PATH"
echo "Output JSON will be saved to: $AIDER_TASKS_JSON_PATH"

echo "Running Python orchestrator to generate slice guides and Aider tasks..."
# CWD for orchestrator.py will be the project root.
python3 "$PYTHON_SCRIPT_PATH" \
    --tool-root "$TOOL_ROOT" \
    --symphony-xml "$SYMPHONY_XML_FILE_ABS_PATH" \
    --config-file "$CONFIG_FILE_PATH" \
    --run-id "$RUN_ID" \
    --output-json-file "$AIDER_TASKS_JSON_PATH" \
    --project-root "$(pwd)" \
    --repo-context-file "repo_contents.txt" \
    --threads "$THREADS"

exit_code=$?
if [ $exit_code -ne 0 ]; then
  echo "Error: Python orchestrator failed with exit code $exit_code"
  exit $exit_code
fi

# Check if the output file exists and is not empty
if [ ! -s "$AIDER_TASKS_JSON_PATH" ]; then
  echo "Error: The output JSON file is empty or was not created."
  exit 1
fi

echo "Launching Aider tasks..."
bash "$LAUNCH_AIDERS_SCRIPT_PATH" "$RUN_ID" "$AIDER_TASKS_JSON_PATH"

echo "-----------------------------------"
echo "Feature Symphony Orchestration Complete!"
echo "Aider agents are now running in separate Terminal windows."
echo "Look for the new Terminal windows with task IDs related to run: $RUN_ID"
echo "Each window will remain open after its task completes for your review."
echo "-----------------------------------" 