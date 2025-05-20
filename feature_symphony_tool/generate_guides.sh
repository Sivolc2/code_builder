#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR_GUIDES="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
TOOL_ROOT="$SCRIPT_DIR_GUIDES" # Assuming this script is in feature_symphony_tool/

echo "--- Feature Symphony Guide Generator ---"

# Show usage if no parameters or --help
if [[ $# -lt 1 || "$1" == "--help" ]]; then
  echo "Usage: $0 <path_to_feature_symphony_file> [options]"
  echo ""
  echo "Required:"
  echo "  <path_to_feature_symphony_file>    Path to the feature symphony file"
  echo ""
  echo "Options:"
  echo "  --threads N                       Number of threads for parallel guide generation (default: 1)"
  echo "  --output-dir DIR                  Directory to save guides (overrides config)"
  echo "  --model MODEL                     OpenRouter model to use (overrides config)"
  echo "  --context-files FILE1 [FILE2...]  Additional context files (space-separated list)"
  echo ""
  echo "Examples:"
  echo "  $0 docs/my_feature_plan.txt"
  echo "  $0 docs/my_feature_plan.txt --threads 4"
  echo "  $0 docs/my_feature_plan.txt --output-dir custom/guides --model anthropic/claude-3-opus"
  echo "  $0 docs/my_feature_plan.txt --context-files docs/architecture.md src/main.py"
  echo ""
  echo "This script should be run from your main project's root directory."
  exit 1
fi

SYMPHONY_FILE_REL_PATH="$1" # Path relative to current PWD (project root)
SYMPHONY_FILE_ABS_PATH="$(pwd)/$SYMPHONY_FILE_REL_PATH"
shift # Remove the first argument

# Initialize variables with default values
THREADS=1
OUTPUT_DIR=""
MODEL=""
declare -a CONTEXT_FILES=()

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --threads)
      if [[ $# -lt 2 ]]; then
        echo "Error: --threads requires a value"
        exit 1
      fi
      THREADS="$2"
      # Validate that THREADS is a number
      if ! [[ "$THREADS" =~ ^[0-9]+$ ]]; then
        echo "Error: Threads value must be a positive integer"
        exit 1
      fi
      shift 2
      ;;
    --output-dir)
      if [[ $# -lt 2 ]]; then
        echo "Error: --output-dir requires a directory path"
        exit 1
      fi
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --model)
      if [[ $# -lt 2 ]]; then
        echo "Error: --model requires a model name"
        exit 1
      fi
      MODEL="$2"
      shift 2
      ;;
    --context-files)
      shift # Remove --context-files
      # Collect all files until next option or end of arguments
      while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
        CONTEXT_FILES+=("$1")
        shift
      done
      if [[ ${#CONTEXT_FILES[@]-0} -eq 0 ]]; then
        echo "Error: --context-files requires at least one file"
        exit 1
      fi
      ;;
    *)
      echo "Error: Unknown option: $1"
      exit 1
      ;;
  esac
done

# Prepare additional args for Python script
ADDITIONAL_ARGS=()

# Add threads
ADDITIONAL_ARGS+=("--threads" "$THREADS")

# Add output directory if specified
if [[ -n "$OUTPUT_DIR" ]]; then
  ADDITIONAL_ARGS+=("--guides-output-dir" "$OUTPUT_DIR")
  echo "Using custom output directory: $OUTPUT_DIR"
fi

# Add model if specified
if [[ -n "$MODEL" ]]; then
  ADDITIONAL_ARGS+=("--model" "$MODEL")
  echo "Using custom model: $MODEL"
fi

# Add context files if any
if [[ ${#CONTEXT_FILES[@]-0} -gt 0 ]]; then
  for file in "${CONTEXT_FILES[@]}"; do
    ADDITIONAL_ARGS+=("--additional-context-files" "$file")
  done
  echo "Using ${#CONTEXT_FILES[@]} additional context file(s)"
fi

CONFIG_FILE_PATH="$TOOL_ROOT/config/config.yaml"
PYTHON_SCRIPT_PATH="$TOOL_ROOT/src/orchestrator.py"
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

# Check if SYMPHONY_FILE exists
if [ ! -f "$SYMPHONY_FILE_ABS_PATH" ]; then
  echo "Error: Symphony file not found at $SYMPHONY_FILE_ABS_PATH"
  exit 1
fi

# Get TOOL_RUN_ARTIFACTS_DIR_NAME from config
TOOL_RUN_ARTIFACTS_DIR_NAME=$(grep -E "^tool_run_artifacts_dir:" "$CONFIG_FILE_PATH" | cut -d ":" -f2- | tr -d " \"'" || echo "runs")
TOOL_RUN_ARTIFACTS_DIR="$TOOL_ROOT/$TOOL_RUN_ARTIFACTS_DIR_NAME"

# Create a timestamped run ID
RUN_ID="guides_$(date +"%Y%m%d_%H%M%S")"
echo "Run ID: $RUN_ID"

# Create run directory
if [ -n "$TOOL_RUN_ARTIFACTS_DIR_NAME" ]; then
  mkdir -p "$TOOL_RUN_ARTIFACTS_DIR/$RUN_ID"
  AIDER_TASKS_JSON_PATH="$TOOL_RUN_ARTIFACTS_DIR/$RUN_ID/guides_info.json"
else
  AIDER_TASKS_JSON_PATH="$TOOL_ROOT/guides_info_$RUN_ID.json"
fi

# Read guides output directory from config
GUIDES_OUTPUT_DIR_REL=$(grep -E "^guides_output_directory:" "$CONFIG_FILE_PATH" | cut -d ":" -f2- | tr -d " \"'" || echo "docs/feature_guides")
GUIDES_OUTPUT_DIR_ABS="$(pwd)/$GUIDES_OUTPUT_DIR_REL"

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
echo "Symphony File: $SYMPHONY_FILE_ABS_PATH"
echo "Output JSON will be saved to: $AIDER_TASKS_JSON_PATH"
echo "Guides will be saved to: $GUIDES_OUTPUT_DIR_ABS"

# Create guides directory if it doesn't exist
mkdir -p "$GUIDES_OUTPUT_DIR_ABS"

echo "Running Python orchestrator to generate slice guides..."
# CWD for orchestrator.py will be the project root.
python3 "$PYTHON_SCRIPT_PATH" \
    --tool-root "$TOOL_ROOT" \
    --symphony-xml "$SYMPHONY_FILE_ABS_PATH" \
    --config-file "$CONFIG_FILE_PATH" \
    --run-id "$RUN_ID" \
    --output-json-file "$AIDER_TASKS_JSON_PATH" \
    --project-root "$(pwd)" \
    --repo-context-file "repo_contents.txt" \
    "${ADDITIONAL_ARGS[@]}"

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

echo "-----------------------------------"
echo "Feature Symphony Guide Generation Complete!"
echo "Feature guides have been generated in: $GUIDES_OUTPUT_DIR_ABS"
echo "NOTE: Aider tasks will NOT be launched - this script only generates guides."
echo "-----------------------------------" 