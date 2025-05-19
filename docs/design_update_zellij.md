The user wants to refactor the `feature_symphony_tool`.
I need to consider several major changes:

1.  **Project Location**: The `feature_symphony_tool` will now always be a subfolder within the user's main project repository.
    *   This means paths for configuration, scripts, and outputs need to be relative to the user's project root, or the tool's subfolder.
    *   The `run_symphony.sh` and `run_single_aider_task.sh` scripts will be executed from the user's project root.
    *   The `TOOL_ROOT` variable in these scripts will point to `your_project_root/feature_symphony_tool/`.

2.  **Execution Context**: Scripts and Aider instances will run with the user's project root as the Current Working Directory (CWD).
    *   This simplifies path handling for Aider, as all file paths in guides and global context files can be relative to the project root.
    *   `orchestrator.py` will need to be aware of this. The `--project-root` argument it receives will be `.` (current directory) when scripts are run from project root.

3.  **Terminal Multiplexer**: Replace `tmux` with `Zellij`.
    *   `launch_aiders.sh` (or its equivalent) will need to be updated to use Zellij commands.
    *   This involves:
        *   Starting a Zellij session (if not already running).
        *   Launching new panes/tabs within Zellij.
        *   Sending commands to these panes.
    *   The `README.md` and dependencies will need to be updated.
    *   `config.yaml` will need a `zellij_session_prefix` instead of `tmux_session_prefix`.

4.  **Python Package Design Considerations**: Outline how to turn this into a proper Python package.
    *   **Structure**: `setup.py` or `pyproject.toml`, package layout (`src/feature_symphony/`, `tests/`).
    *   **Entry Points**: Using `console_scripts` in `setup.py` to make `run_symphony` and `run_single_aider_task` directly callable Python commands. This would replace the shell scripts.
    *   **Configuration Management**: How the package finds its configuration (e.g., looking in CWD, user's home directory, environment variables).
    *   **Dependencies**: Declared in `setup.py` or `pyproject.toml`.
    *   **Resource Files**: How templates or default configs are packaged (e.g., `package_data`).
    *   **Installation**: `pip install .` or `pip install feature-symphony-tool`.
    *   **User Experience**: How users would interact with the packaged tool.

Let's break down the refactoring steps:

**Phase 1: Path and Execution Context Adjustments**

*   Modify `run_symphony.sh` and `run_single_aider_task.sh`:
    *   Assume they are run from the project root.
    *   `TOOL_ROOT` will be `./feature_symphony_tool`.
    *   Paths to `config.yaml`, `orchestrator.py`, `launch_aiders.sh` will be relative to `TOOL_ROOT`.
    *   The `--project-root` passed to `orchestrator.py` will be `.` or `$(pwd)`.
*   Modify `orchestrator.py`:
    *   Adapt to `--project-root` being the CWD.
    *   Ensure all paths it generates for guides and Aider tasks are correctly relative to this CWD.
*   Modify `config.yaml.template` and `README.md` to reflect these new assumptions.
    *   `guides_output_directory` will be relative to project root (e.g., `docs/feature_guides`).
    *   `aider_global_context_files` will be relative to project root.

**Phase 2: Zellij Integration**

*   Rename `launch_aiders.sh` to `launch_aiders_zellij.sh` or similar.
*   Update this script:
    *   Check for `zellij` command.
    *   Use `zellij action new-pane -- ...` or `zellij run -- ...` to launch Aider instances.
    *   Manage Zellij sessions/layouts.
*   Update `config.yaml.template` for Zellij session naming.
*   Update `README.md` with Zellij prerequisites and usage.

**Phase 3: Python Packaging Outline (Documentation)**

*   Create a new section in `docs/design.md` or a new file like `docs/packaging_notes.md`.
*   Detail the points listed above (structure, entry points, config, etc.).

**Detailed Plan:**

**I. Update File Structure and Paths**

1.  **`README.md`**:
    *   Update setup instructions: user clones/adds `feature_symphony_tool` into their project.
    *   Update usage examples: `cd your_project_root; ./feature_symphony_tool/run_symphony.sh ...`.
    *   Mention Zellij as a prerequisite.
    *   Update how `repo_contents.txt` is generated (`./feature_symphony_tool/bin/dump_repo.sh`).

2.  **`config.yaml.template` and `config.yaml`**:
    *   Paths like `guides_output_directory` and `aider_global_context_files` are already specified as relative to the project root where the symphony tool is run. This aligns well, just need to ensure scripts enforce this.
    *   Change `tmux_session_prefix` to `zellij_session_name` (or similar, Zellij might not need a prefix in the same way). Zellij sessions are named, and panes are launched within them.

3.  **Shell Scripts (`run_symphony.sh`, `run_single_aider_task.sh`)**:
    *   **`TOOL_ROOT`**:  `TOOL_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." &> /dev/null && pwd )/feature_symphony_tool"` - No, this is wrong. If the script is `./feature_symphony_tool/run_symphony.sh`, then `SCRIPT_DIR` is `./feature_symphony_tool`. `TOOL_ROOT` should be simply `SCRIPT_DIR`.
        *   Correct: `SCRIPT_DIR_SYMPHONY="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"` (this gives `your_project_root/feature_symphony_tool`)
        *   So, `TOOL_ROOT="$SCRIPT_DIR_SYMPHONY"` is correct.
    *   **Paths to internal scripts/config**:
        *   `CONFIG_FILE_PATH="$TOOL_ROOT/config/config.yaml"`
        *   `PYTHON_SCRIPT_PATH="$TOOL_ROOT/src/orchestrator.py"`
        *   `LAUNCH_AIDERS_SCRIPT_PATH="$TOOL_ROOT/bin/launch_aiders_zellij.sh"` (new name)
    *   **`--project-root` for `orchestrator.py`**: Pass `$(pwd)` or `.`.
    *   **`--tool-root` for `orchestrator.py`**: Pass `$TOOL_ROOT`.
    *   **`.env` file**: Source from `$TOOL_ROOT/.env`.
    *   **Virtual Environment**: Activate from `$TOOL_ROOT/.venv`.
    *   **`dump_repo.sh`**: Path to it will be `$TOOL_ROOT/bin/dump_repo.sh`.

4.  **`bin/dump_repo.sh`**:
    *   It already uses `REPO_ROOT=$(git rev-parse --show-toplevel)` which is correct when run from anywhere within the git repo. The output `repo_contents.txt` will be in the project root. No changes needed here if it's invoked correctly.

5.  **`src/orchestrator.py`**:
    *   The `--project-root` argument will now be the actual CWD of the user's project.
    *   The `--tool-root` argument points to the `feature_symphony_tool` subfolder.
    *   `load_config` will use `config_file` which is an absolute path passed by the shell script (e.g., `your_project_root/feature_symphony_tool/config/config.yaml`).
    *   `guides_output_dir_abs = project_root / guides_output_dir_rel` remains correct. `project_root` is CWD.
    *   Paths in the output JSON (`guide_file`, `global_files`) should be relative to `project_root`. This is already the case.

**II. Zellij Integration**

1.  **Prerequisites**: `README.md` updated to list Zellij.
2.  **Configuration**: `config.yaml.template` to use `zellij_session_name` (e.g., `symphony_aider_run_id`).
3.  **`bin/launch_aiders_zellij.sh`**:
    *   Input: `RUN_ID`, `tasks_json_file_path`.
    *   Read `zellij_session_name` from JSON (or construct it from prefix in config + RUN_ID).
    *   **Session Management**:
        *   Check if Zellij session exists: `zellij list-sessions | grep -q "$ZELLIJ_SESSION_NAME"`.
        *   If not, start a new detached session: `zellij --session "$ZELLIJ_SESSION_NAME" &` (this might need adjustment; Zellij usually attaches. Or, launch first pane which creates session).
        *   A simpler way: `zellij action new-tab --layout ... --name ... --cwd ...` can create a session if one isn't specified or running.
        *   Let's try `zellij attach --create "$ZELLIJ_SESSION_NAME"`. This creates if not exists, and attaches. We want to run commands *in* it.
        *   Alternative: `zellij --session "$SESSION_NAME" action run-command -- ...`
    *   **Launching Tasks**:
        *   For each task:
            *   `zellij --session "$ZELLIJ_SESSION_NAME" action new-pane --name "task_N_desc" -- bash -c "echo 'Task N: Description'; echo 'Guide: ...'; AIDER_CMD; exec bash"`
            *   The `exec bash` at the end keeps the pane open after Aider finishes/exits.
            *   The Aider command construction needs to be careful with quoting.
            *   `AIDER_MODEL` environment variable setting for the Aider command needs to be part of the command string passed to `bash -c`.
            *   Example: `zellij --session "$SESSION_NAME" action new-pane --name "$WINDOW_NAME" -- bash -c "echo 'Task $WINDOW_NUM: $DESCRIPTION'; echo 'Running: $AIDER_CMD_WITH_ENV'; $AIDER_CMD_WITH_ENV; echo 'Aider finished. Press Ctrl+P then X to close this pane.'; exec bash"`
    *   Inform user how to attach: `zellij attach "$ZELLIJ_SESSION_NAME"`.

**III. Python Packaging Design Outline (New `docs/python_packaging.md`)**

*   **Goal**: Allow installation via `pip` and provide command-line entry points.
*   **Directory Structure**:
    ```
    feature-symphony/
    ├── feature_symphony/    # Python package (renamed for PEP8)
    │   ├── __init__.py
    │   ├── orchestrator.py
    │   ├── utils.py
    │   ├── cli.py           # Main CLI handling using Click
    │   ├── config_mgmt.py   # For loading/managing config
    │   └── resources/
    │       └── config.yaml.template
    ├── scripts/             # Helper scripts (like dump_repo.sh, could be moved or integrated)
    │   └── dump_repo.sh
    ├── tests/
    │   └── ...
    ├── pyproject.toml       # PEP 517/518 build system and metadata
    ├── README.md
    ├── LICENSE
    └── .gitignore
    ```
*   **`pyproject.toml`**:
    *   Using `setuptools` or `poetry` or `flit`.
    *   Dependencies: `click`, `pyyaml`, `python-slugify`, `requests`, `python-dotenv`.
    *   **Entry Points**:
        ```toml
        [project.scripts]
        feature-symphony = "feature_symphony.cli:main_symphony"
        feature-symphony-single = "feature_symphony.cli:main_single_task"
        feature-symphony-dump = "feature_symphony.cli:main_dump_repo" # If dump_repo.sh is Pythonized
        ```
*   **`cli.py`**:
    *   Use `click` to define commands.
    *   `main_symphony` would call orchestrator logic for full XML.
    *   `main_single_task` would call orchestrator logic for a single guide.
    *   These functions would replace `run_symphony.sh` and `run_single_aider_task.sh`.
    *   They would handle:
        *   Finding/loading `.env` (from current dir or tool's sub-dir if tool is a submodule).
        *   Finding/loading `config.yaml` (from current dir or tool's sub-dir).
        *   Generating `RUN_ID`.
        *   Calling the core orchestrator logic.
        *   Invoking the Zellij launcher (which could also be a Python function using `subprocess`).
*   **Configuration (`config_mgmt.py`)**:
    *   Strategy:
        1.  Look for `feature_symphony_config.yaml` in CWD (project root).
        2.  If not found, look for `config.yaml` inside the installed package's `resources` (for defaults).
        3.  Overlay with environment variables.
    *   `OPENROUTER_API_KEY` strictly from env.
*   **Resource Files**:
    *   `config.yaml.template` included via `MANIFEST.in` or `package_data` in `pyproject.toml`.
    *   A command to copy/initialize a default config in the user's project: `feature-symphony init-config`.
*   **`dump_repo.sh`**:
    *   Could remain a shell script, and the package could provide a helper to find its path.
    *   Or, re-implement its logic in Python using `gitpython` or `subprocess.run(['git', ...])`.
*   **Zellij Launcher**:
    *   The `launch_aiders_zellij.sh` logic could be moved into a Python function in `cli.py` or a separate `zellij_launcher.py`, using `subprocess` to call `zellij` commands.
*   **User Workflow with Package**:
    1.  `pip install feature-symphony`
    2.  `cd your_project_root`
    3.  `feature-symphony init-config` (copies `config.yaml.template` to CWD as `feature_symphony_config.yaml`)
    4.  Edit `feature_symphony_config.yaml` and create `.env` with `OPENROUTER_API_KEY`.
    5.  `feature-symphony-dump` (if Pythonized) or run the `dump_repo.sh` script.
    6.  `feature-symphony your_breakdown.xml`
    7.  `feature-symphony-single your_guide.md`

This is a substantial refactor. I'll focus on implementing Phase 1 and 2, and then provide the design doc for Phase 3.

One point of clarification: If `feature_symphony_tool` is a subfolder, say `tools/feature_symphony_tool`, then `TOOL_ROOT` in the scripts would be `$(pwd)/tools/feature_symphony_tool` when running from project root. The current scripts set `TOOL_ROOT` based on their own location.
If the user is *always* expected to run `path/to/feature_symphony_tool/run_symphony.sh`, then `TOOL_ROOT` as `SCRIPT_DIR_SYMPHONY` is fine.
The prompt says "Assume the user runs from the top level". This means commands like `./feature_symphony_tool/run_symphony.sh ...`.
So, `SCRIPT_DIR_SYMPHONY` will correctly resolve to `your_project_root/feature_symphony_tool`. This is good.

The `bin/dump_repo.sh` needs to be callable as `./feature_symphony_tool/bin/dump_repo.sh`. Its internal `REPO_ROOT=$(git rev-parse --show-toplevel)` will correctly find the *actual* project root, not `feature_symphony_tool`'s root, which is desired.

Let's refine Zellij command generation:
`zellij action run-command --floating --name "Task $i" -- bash -c "$COMMAND_STRING; exec bash"` might be better. Or `zellij action new-pane --name "Task $i" -- bash -c "$COMMAND_STRING; exec bash"`.
The `--cwd $(pwd)` option for `zellij action new-pane` is important to ensure Aider runs in the project root.

```bash
# Example Zellij command for launch_aiders_zellij.sh
ZELLIJ_SESSION_NAME="symphony_${RUN_ID}" # Define this
# Check if session exists, if not, start it (maybe just launch first pane and it creates session)
# zellij attach --create "$ZELLIJ_SESSION_NAME" # Might not be needed if subsequent commands create it.

# For each task:
WINDOW_NAME="task_${WINDOW_NUM}_${DESCRIPTION_SLUG}" # Make sure slug is shell-safe
# AIDER_CMD_WITH_ENV="OPENROUTER_API_KEY='$OPENROUTER_API_KEY' AIDER_MODEL='$AIDER_TASK_MODEL' aider $GUIDE_FILE $GLOBAL_FILES --message \"$PROMPT\" --yes"
# Shell script inherits OPENROUTER_API_KEY. AIDER_MODEL needs to be set for the command.
AIDER_LAUNCH_COMMAND=""
if [ -n "$AIDER_TASK_MODEL" ]; then
    AIDER_LAUNCH_COMMAND="AIDER_MODEL=\"$AIDER_TASK_MODEL\" aider"
else
    AIDER_LAUNCH_COMMAND="aider"
fi
AIDER_FULL_CMD="$AIDER_LAUNCH_COMMAND \"$GUIDE_FILE\" $GLOBAL_FILES --message \"$PROMPT\" --yes"


# Using new-pane. It will create the session if it doesn't exist when attached.
# Or if Zellij is already running with that session, it adds a pane.
# If Zellij is not running at all, this might try to start a new server.
# Best to ensure a session is active or can be created.
# `zellij options --session-name "$ZELLIJ_SESSION_NAME"` can set current session context.

# Simpler approach for Zellij:
# 1. Create/attach to session: `zellij attach --create $ZELLIJ_SESSION_NAME`
#    This might be interactive. We need non-interactive launching.
#
# `zellij run -- <command>` launches command in a new session or existing if specified.
# `zellij action new-pane --cwd . -- command ... `

# Revised Zellij logic for launch_aiders_zellij.sh:
# Create a layout file for Zellij on the fly, then launch Zellij with it? Complex.
# Or, use `zellij action ...` commands targeting a specific session.

# Assume user might not have Zellij running.
# Start a detached Zellij server with the session if it's not there:
# `zellij setup --dump-layout default > /tmp/default_layout.kdl` (to see default)
# `zellij --session $SESSION_NAME` (starts and attaches)
# `zellij --session $SESSION_NAME action new-pane -- bash -c "..."`

# If zellij is running:
# `zellij action --session $SESSION_NAME new-pane ...` (if session exists)
# If zellij is not running, or session doesn't exist:
# `zellij --layout default --session $SESSION_NAME action new-pane ...` (this creates new session and runs action)

# Let's try this for launch_aiders_zellij.sh
# At the start:
# `zellij list-sessions | grep -q "$ZELLIJ_SESSION_NAME" || zellij --session "$ZELLIJ_SESSION_NAME" --detach`
# This seems like a plausible way to ensure session exists, detached.
# However, `--detach` is not a standard option for `zellij --session`.
#
# Alternative: launch the first pane which will create the session if needed.
# `zellij --session "$ZELLIJ_SESSION_NAME" action new-pane --name "control_pane" -- bash -c "echo 'Session started'; exec bash"`
# Then for subsequent panes:
# `zellij --session "$ZELLIJ_SESSION_NAME" action new-pane --name "$WINDOW_NAME" --cwd . -- bash -c "$FULL_COMMAND_STRING; echo 'Task finished. Pane remains open.'; exec bash"`

# Ensure `OPENROUTER_API_KEY` is available to Aider. Since `launch_aiders_zellij.sh` sources `.env`,
# the key will be in its environment. When Zellij launches a pane, it should inherit the environment
# of the `zellij` command issuer. So, this should be fine.

Final check on `.gitignore`:
The current `.gitignore` has `/.env`. This is good, it ignores `.env` only at the tool's root.
`config/config.yaml` is also good.
`runs/` is good.

Consider the structure if the tool is a subfolder:
`my_project_root/`
  `.git/`
  `feature_symphony_tool/`  <- This is TOOL_ROOT
    `bin/`
      `dump_repo.sh`
      `launch_aiders_zellij.sh`
    `config/`
      `config.yaml`
      `config.yaml.template`
    `src/`
      `orchestrator.py`
      `utils.py`
    `.env`
    `.gitignore` (for the tool's own files, like .env, runs/, config.yaml)
    `README.md` (tool's readme)
    `requirements.txt`
    `run_symphony.sh`
    `run_single_aider_task.sh`
  `docs/`
    `feature_guides/` (output from the tool)
  `src/` (user's project source)
  `repo_contents.txt` (output from dump_repo.sh)
  `user_feature_breakdown.xml`

This structure and the script logic adjustments seem consistent.