Okay, I'll simplify the `launch_aiders_zellij.sh` script to more directly use AppleScript and Zellij commands, removing the need for complex temporary script files written via heredocs. We'll focus on making it work robustly for macOS, as per your request.

The core idea is to construct a single command string that will be executed by `Terminal.app`. This command string will:
1.  Launch Zellij with a unique session name.
2.  Tell Zellij to execute `bash -c "..."`.
3.  The payload for `bash -c` will include:
    *   `cd` to the project root.
    *   The fully constructed Aider command (with model, guide, prompt, etc.).
    *   Commands to keep the bash session alive after Aider finishes for review.

**Assumptions:**
*   Running on macOS.
*   `osascript`, `jq`, `zellij`, `aider` are installed and in PATH.
*   `OPENROUTER_API_KEY` is available in the environment from which Terminal.app is launched (e.g., sourced in `.zshrc`/`.bashrc`). The tool's `.env` file is primarily for the Python orchestrator's use of the API key.
*   Aider is configured to use OpenRouter (e.g. via `~/.config/aider/config.yaml` or global environment variables like `OPENAI_API_BASE` for OpenRouter).

Here are the changes:

**1. Updated `feature_symphony_tool/bin/launch_aiders_zellij.sh`**
This script will be significantly simplified.

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "--- Aider Launch Script (Zellij - New Window Per Task for macOS) ---"

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

ZELLIJ_SESSION_BASE_PREFIX_FROM_JSON=$(jq -r '.zellij_session_prefix // "symphony_aider"' "$TASKS_JSON_FILE")
TASK_COUNT=$(jq '.tasks | length' "$TASKS_JSON_FILE")
echo "Found $TASK_COUNT tasks to launch."

for (( i=0; i<$TASK_COUNT; i++ ))
do
    TASK_INFO=$(jq -c ".tasks[$i]" "$TASKS_JSON_FILE")
    GUIDE_FILE=$(echo "$TASK_INFO" | jq -r '.guide_file')
    PROMPT_RAW=$(echo "$TASK_INFO" | jq -r '.prompt')
    DESCRIPTION_RAW=$(echo "$TASK_INFO" | jq -r '.description')
    AIDER_TASK_MODEL=$(echo "$TASK_INFO" | jq -r '.aider_model // empty') # From orchestrator.py (config.yaml)

    GLOBAL_FILES_ARGS_STR=""
    # Read global_files array and build a space-separated string of q-escaped paths
    jq -r '.global_files[]? // empty' <<< "$TASK_INFO" | while IFS= read -r file_path; do
        if [ -n "$file_path" ]; then # Only add if file_path is not empty
            GLOBAL_FILES_ARGS_STR+=" $(printf %q "$file_path")"
        fi
    done

    WINDOW_NUM=$((i+1))
    UNIQUE_ZELLIJ_SESSION_NAME="${ZELLIJ_SESSION_BASE_PREFIX_FROM_JSON}_${RUN_ID}_task${WINDOW_NUM}"

    echo ""
    echo "Preparing task $WINDOW_NUM: $DESCRIPTION_RAW"
    echo "  Guide: $GUIDE_FILE"
    echo "  Zellij Session: $UNIQUE_ZELLIJ_SESSION_NAME"

    # 1. Construct the full Aider command
    # This command will be part of the BASH_C_PAYLOAD executed by Zellij.
    AIDER_ENV_PREFIX=""
    if [ -n "$AIDER_TASK_MODEL" ]; then
        AIDER_ENV_PREFIX="AIDER_MODEL=$(printf %q "$AIDER_TASK_MODEL") "
    fi
    # Ensure all parts of the Aider command are properly quoted for shell execution
    FULL_AIDER_COMMAND="${AIDER_ENV_PREFIX}aider $(printf %q "$GUIDE_FILE")${GLOBAL_FILES_ARGS_STR} --message $(printf %q "$PROMPT_RAW") --yes"

    # 2. Construct the payload for `bash -c` which Zellij will execute
    # This payload changes directory, runs Aider, then keeps bash open for review.
    CD_COMMAND="cd $(printf %q "$PROJECT_ROOT_ABS_PATH")"
    POST_AIDER_ECHO_1="echo -e '\\n--- Aider Task Finished ---'" # Use echo -e for newline
    POST_AIDER_ECHO_2="echo 'This Zellij session will remain. Type \"exit\" or Ctrl+D to close this pane/window.'"
    KEEP_BASH_OPEN="exec bash" # Keeps the pane interactive

    BASH_C_PAYLOAD="${CD_COMMAND}; ${FULL_AIDER_COMMAND}; ${POST_AIDER_ECHO_1}; ${POST_AIDER_ECHO_2}; ${KEEP_BASH_OPEN}"

    # 3. Construct the command that will be run in the new Terminal window's shell
    # This command launches Zellij, which in turn runs the BASH_C_PAYLOAD.
    # `printf %q` is used to ensure session name and bash payload are safely passed as arguments.
    COMMAND_FOR_TERMINAL="zellij --session $(printf %q "$UNIQUE_ZELLIJ_SESSION_NAME") -- bash -c $(printf %q "$BASH_C_PAYLOAD")"

    # 4. Escape the command for AppleScript's `do script "..."` context
    # Basic escaping: replace " with \"
    ESCAPED_COMMAND_FOR_APPLESCRIPT=$(echo "$COMMAND_FOR_TERMINAL" | sed 's/"/\\"/g')

    APPLESCRIPT_CMD="tell application \"Terminal\" to do script \"${ESCAPED_COMMAND_FOR_APPLESCRIPT}\""

    echo "  Full Aider command (to run inside Zellij's bash -c):"
    echo "    ${FULL_AIDER_COMMAND}"
    echo "  Executing AppleScript to open new Terminal for task $WINDOW_NUM (Zellij Session: $UNIQUE_ZELLIJ_SESSION_NAME)"
    
    osascript -e "$APPLESCRIPT_CMD"

    # Brief pause to allow Terminal window to open and script to start
    # Adjust if necessary, or consider more robust checks if Zellij takes time to init.
    sleep 3
done

echo ""
echo "--- All Aider Tasks Launched in Separate Terminal Windows (macOS) ---"
echo "Each task runs in its own Terminal window with a dedicated Zellij session."
echo "Check your open Terminal windows."
```

**2. Updated `feature_symphony_tool/config/config.yaml`** (and ensure `config.yaml.template` matches)

The key `tmux_session_prefix` needs to be `zellij_session_prefix`.

```yaml
# feature_symphony_tool/config/config.yaml
# Copy this to config.yaml and fill in your values.

# OpenRouter Configuration
# Your OpenRouter API Key.
# IMPORTANT: It's highly recommended to set this via the OPENROUTER_API_KEY environment variable
# (e.g., in an .env file) instead of hardcoding it here for security.
# The tool will ONLY use the OPENROUTER_API_KEY environment variable.
openrouter_api_key_required: true # Reminder that API key is needed via env

# OpenRouter model to use for generating feature slice guides.
# Available models: "anthropic/claude-3-7-sonnet", "openai/gpt-4o", "google/gemini-1.5-pro", etc.
openrouter_model_guide_generation: "anthropic/claude-3-7-sonnet"

# OpenRouter model for Aider tasks. Aider will use OPENROUTER_API_KEY (from env) and this model.
aider_model: "anthropic/claude-3-7-sonnet"

# Aider Configuration
# List of global context files to always include with Aider.
# These paths are relative to the root of the project where you run the symphony tool.
aider_global_context_files:
  - "README.md"
  # - "src/core_logic.py"
  # - "docs/architecture.md"

# Output Configuration
# Directory where the generated feature_slice_guide_*.md files will be saved.
# This path is relative to the root of the project where you run the symphony tool.
guides_output_directory: "docs/feature_guides" # Example: "project_docs/generated_guides"

# Zellij session name prefix for Aider runs
# The actual session name will be: {zellij_session_prefix}_{RUN_ID}_task{N}
zellij_session_prefix: "symphony_aider" # Changed from tmux_session_prefix

# --- Advanced ---
# Optional: Directory within feature_symphony_tool to store logs and intermediate files for each run.
# If empty, no run-specific subdirectories are created by the tool for its own artifacts.
# Tool's internal run artifacts directory (relative to feature_symphony_tool location)
# Example: "runs" will create feature_symphony_tool/runs/RUN_ID/...
tool_run_artifacts_dir: "runs"
```
I will also update `feature_symphony_tool/config/config.yaml.template` to reflect this change from `tmux_session_prefix` to `zellij_session_prefix`.

**3. `feature_symphony_tool/README.md`**

The README already describes the new multi-window behavior for macOS and mentions Zellij. The section on "Configure Aider for OpenRouter" is helpful. No significant changes needed here unless testing reveals issues with the Zellij session naming or attachment instructions. The current `README.md` seems largely compatible with this simplified launcher.

**Explanation of `launch_aiders_zellij.sh` Simplification:**

*   **No Temporary Script Files**: The script no longer writes temporary `.sh` files to `/tmp/`. Instead, it constructs the entire command string that needs to be run in the new terminal.
*   **Direct Zellij Invocation**: It uses `zellij --session <session_name> -- bash -c <payload>` to launch Zellij. Zellij creates the session if it doesn't exist and runs the specified command (`bash -c ...`) in the initial pane.
*   **Quoting Strategy**: `printf %q` is used consistently to ensure that file paths, prompts, model names, session names, and the entire bash payload are correctly quoted and escaped for each layer of shell interpretation (local shell, AppleScript string, Terminal shell, `bash -c` execution). This is critical for robustness.
*   **Aider Execution**: Aider is launched with `--yes`, so it should proceed non-interactively for the initial prompt and file loading. The `exec bash` at the end of the `BASH_C_PAYLOAD` ensures the Zellij pane (and thus the Terminal window) remains open after Aider exits, allowing the user to review output or interact further.

This revised script should be more straightforward and less prone to issues related to temporary file management, while still achieving the goal of opening each Aider task in a new, dedicated Terminal window with its own Zellij session on macOS.