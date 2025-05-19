Okay, this is a significant change to the execution model, moving from panes in a single Zellij session to individual Terminal windows, each with its own Zellij session, for every Aider task. This approach is macOS-specific due to the use of AppleScript.

Here's how we'll update the `feature_symphony_tool`:

**Key Changes:**

1.  **`launch_aiders_zellij.sh`**: This script will be heavily modified. Instead of managing panes within a single Zellij session, it will:
    *   Iterate through each Aider task.
    *   For each task, generate a temporary shell script.
    *   This temporary script will `cd` to the project root and then launch a new, unique Zellij session running the specific Aider command.
    *   Use AppleScript (`osascript`) to open a new Terminal window that executes this temporary shell script.
2.  **`README.md`**: Will be updated to reflect this new macOS-specific behavior, explaining that each task runs in a new Terminal window.
3.  **Configuration (`config.yaml.template`, `config.yaml`)**: The `zellij_session_prefix` will be used as a base for the *unique session name* created for each new Terminal window/Zellij instance.
4.  **Environment Variables**: `OPENROUTER_API_KEY` and `AIDER_MODEL` (if set in `.env`) are expected to be inherited by the new Terminal windows. The script will also explicitly pass `AIDER_MODEL` if defined per task in the JSON.

**No changes are needed for:**
*   `dump_repo.sh`
*   `src/orchestrator.py` (its output JSON structure is fine)
*   `src/utils.py`
*   `run_symphony.sh` (it calls `launch_aiders_zellij.sh` which handles the new logic)
*   `run_single_aider_task.sh` (similarly, relies on `launch_aiders_zellij.sh`)

Let's proceed with the modifications.

**1. `feature_symphony_tool/bin/launch_aiders_zellij.sh`**

This script will now create a new Terminal window for each task.

```bash
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
    # Sanitize description for use in filenames or session names if needed
    DESCRIPTION_SANITIZED=$(echo "$DESCRIPTION_RAW" | tr -cd '[:alnum:]_-' | cut -c1-30)
    UNIQUE_ZELLIJ_SESSION_NAME="${ZELLIJ_SESSION_BASE_PREFIX}_${RUN_ID}_task${WINDOW_NUM}_${DESCRIPTION_SANITIZED}"

    TEMP_SCRIPT_PATH="/tmp/fs_task_runner_${RUN_ID}_${WINDOW_NUM}.sh"
    TEMP_SCRIPTS_TO_CLEAN+=("$TEMP_SCRIPT_PATH")

    echo "Preparing task $WINDOW_NUM: $DESCRIPTION_RAW"
    echo "  Guide: $GUIDE_FILE"
    echo "  Zellij Session: $UNIQUE_ZELLIJ_SESSION_NAME"
    echo "  Temp Script: $TEMP_SCRIPT_PATH"

    # Create the temporary shell script that will be run in the new Terminal window
    # Variables are expanded at the time of heredoc creation.
    # Ensure variables like PROMPT_RAW are handled carefully if they contain special characters
    # that might interact with the heredoc itself or the shell commands inside.
    # Using printf %q for dynamic parts of commands is generally robust.

    cat > "$TEMP_SCRIPT_PATH" <<HEREDOC
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
    # The main OPENROUTER_API_KEY should be inherited from the environment
    # of the shell that ran launch_aiders_zellij.sh
    local aider_env_prefix=""
    if [ -n "\${AIDER_TASK_MODEL_TASK}" ]; then
        # Use printf %q to safely quote the model name for the environment variable
        aider_env_prefix="AIDER_MODEL=\$(printf %q \"\${AIDER_TASK_MODEL_TASK}\") "
    elif [ -n "\${AIDER_MODEL:-}" ]; then # Check for AIDER_MODEL from parent .env
        aider_env_prefix="AIDER_MODEL=\$(printf %q \"\${AIDER_MODEL}\") "
    fi

    # Construct the Aider command. Guide and global files are already q-escaped.
    # Prompt needs to be q-escaped for --message.
    # The GLOBAL_FILES_ARGS_STR_TASK is a string of already q-escaped paths.
    local aider_command_args="\$(printf %q \"\${GUIDE_FILE_TASK}\")\${GLOBAL_FILES_ARGS_STR_TASK} --message \$(printf %q \"\${PROMPT_TASK_RAW}\") --yes"
    local full_aider_command="\${aider_env_prefix}aider \${aider_command_args}"

    echo "Executing Aider command inside Zellij:"
    echo "\$ Zellij Command: zellij --session \"\${UNIQUE_ZELLIJ_SESSION_NAME_TASK}\" -- bash -c \"..."
    echo "\$ Aider Command (inside bash -c): \${full_aider_command}"
    echo "--- Aider Output Starts Below ---"

    # The command string to be run by 'bash -c' inside Zellij
    # This string itself must be valid for 'bash -c'. Single quotes are good if no single quotes inside.
    # The eval is used to correctly parse the command string with its quoted arguments.
    local zellij_bash_c_payload="echo 'Launching Aider...'; eval \"\${full_aider_command}\"; echo -e '\\n--- Aider Task Finished ---'; echo 'This Zellij session will remain. Type \"exit\" or Ctrl+D to close this pane/window.'; exec bash"

    # Launch Zellij, which will create/attach to the session and run the command
    # The `zellij_bash_c_payload` must not contain raw single quotes if we delimit with single quotes for bash -c
    # Since `full_aider_command` uses `printf %q`, it should be safe from breaking out.
    # Using double quotes for bash -c payload to allow variable expansion, but must escape internal double quotes and $
    zellij --session "\${UNIQUE_ZELLIJ_SESSION_NAME_TASK}" -- bash -c "\${zellij_bash_c_payload//\"/\\\"}" # Escape internal double quotes for bash -c "..."
}

# Execute the main function
run_aider_in_zellij

# Optional: self-delete this script (use with caution)
# rm -- "\$0"
HEREDOC

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
```

**2. `feature_symphony_tool/README.md`**

Update the Zellij usage section:

```diff
--- a/feature_symphony_tool/README.md
+++ b/feature_symphony_tool/README.md
@@ -59,7 +59,7 @@
     path/to/feature_symphony_tool/run_symphony.sh path/to/my_feature_breakdown.xml
     ```
 
-3.  **Work with Aider**:
-    Once the Aider instances are launched in Zellij:
-    *   Attach to the Zellij session: `zellij attach symphony_aider_20230615_123456`.
-    *   Switch between panes: `Ctrl+P` then arrow keys.
-    *   Close a pane: `Ctrl+P` then `X`.
+3.  **Monitor Aider Tasks (macOS)**:
+    *   This tool will open a **new Terminal window for each Aider task** when running on macOS.
+    *   Each Terminal window will contain its own dedicated Zellij session running one Aider instance.
+    *   You can interact with each Aider instance in its respective window.
+    *   To close a specific Aider task, you can type `exit` or `Ctrl+D` in its Zellij pane, or simply close the Terminal window.
+    *   Zellij sessions are named like `symphony_aider_RUNID_taskN_description`. You can list them with `zellij list-sessions` and attach manually if needed, e.g., `zellij attach session_name`.
 
 ## Standalone Aider Task
 
@@ -118,18 +118,6 @@
    ./feature_symphony_tool/run_single_aider_task.sh docs/feature_guides/feature_slice_guide_user_authentication.md
    ```
 
-6. **Working with Zellij Sessions**:
-   ```bash
-   # List all Zellij sessions
-   zellij ls
-
-   # Attach to a specific session
-   zellij attach symphony_aider_20240315_123456
-
-   # Switch between panes
-   # Press Ctrl+P, then use arrow keys
-
-   # Close a pane
-   # Press Ctrl+P, then X
-   ```
-
 7. **Environment Setup for Each Run**:
    ```bash
    # Activate the tool's virtual environment

```

**Explanation of Changes in `launch_aiders_zellij.sh`:**

*   **macOS Check**: Added a check for `osascript`.
*   **Project Root**: Captures `PROJECT_ROOT_ABS_PATH="$(pwd)"` as the script is expected to be run from the project root.
*   **Loop per Task**: Iterates through tasks.
*   **Unique Zellij Session Name**: Generates a unique session name for each task (e.g., `symphony_aider_RUNID_taskN_description`).
*   **Temporary Script (`TEMP_SCRIPT_PATH`)**:
    *   A unique temporary shell script is generated for each task in `/tmp/`.
    *   This script contains all necessary variables (paths, prompt, model, etc.) embedded directly.
    *   It defines a function `run_aider_in_zellij` which:
        *   Prints task information.
        *   `cd`s to the project root.
        *   Constructs the full `aider` command, including `AIDER_MODEL` environment variable if specified for the task. Uses `printf %q` for robust quoting of file paths and the prompt message.
        *   Launches a new Zellij session (using the unique name) and executes `bash -c "..."` inside it. The command given to `bash -c` includes the `eval` of the constructed Aider command and `exec bash` to keep the pane alive after Aider finishes.
    *   The temporary script is made executable.
*   **AppleScript Execution**:
    *   `osascript` is used to tell "Terminal.app" to `do script` with the path to the temporary shell script. This opens a new Terminal window and runs the script.
*   **Cleanup**: A list of temporary scripts is kept, and they are removed at the end.
*   **Error Handling**: The temporary script includes `set -euo pipefail` and basic checks.
*   **Quoting**: The primary challenge is always quoting.
    *   `printf %q` is used within the temporary script to make file paths and the prompt safe for inclusion as arguments to the `aider` command.
    *   The command string for `bash -c` inside Zellij (`zellij_bash_c_payload`) is carefully constructed. The version `bash -c "${zellij_bash_c_payload//\"/\\\"}"` is used to escape double quotes if the payload is enclosed in double quotes for `bash -c`.

This approach isolates each Aider task into its own Terminal window and Zellij session, providing a clear separation of concerns for parallel execution on macOS. Remember to test this thoroughly, especially the quoting and environment variable inheritance.