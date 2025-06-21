Okay, I will update the `auto_feature_tool/auto_feature.py` script with the following enhancements:

1.  **Robust Path Resolution**: `PROJECT_ROOT` will be derived from the script's location, making path resolution more robust. `TOOL_DIR` will represent the absolute path to the `auto_feature_tool` directory. Configuration paths will continue to be interpreted relative to `PROJECT_ROOT`.
2.  **Real-time Output for `claude-code`**: The script will now flush `stdout` and `stderr` after printing each line from `claude-code`, aiming to provide more immediate feedback in the terminal.
3.  **Automatic `repo_contents.txt` Update**: At the beginning of each feature processing loop, the script will attempt to run `git dump > path/to/your/repo_contents.txt`. This ensures the planning phase for each feature uses the latest repository state, including changes from previously implemented features in the same run. This relies on the user having a `git dump` command/alias available in their PATH that outputs the repository contents to `stdout`.
4.  **Enhanced Human Review**: If `human_review` is enabled, the script will also show the latest `git log -n 1 --oneline` entry after `git status -s`, to help the user verify the commit made by `claude-code`.

The `README.md` will also be updated to reflect these changes, particularly the `git dump` requirement for the automatic update feature.

Here are the modified files:

**1. `auto_feature_tool/auto_feature.py` (Updated)**

```python
import os
import sys
import subprocess
import json
import re
import shutil
from pathlib import Path
import yaml # PyYAML
import requests # For OpenRouter API calls

# --- Configuration Loading & Constants ---
_SCRIPT_PATH = Path(__file__).resolve()
TOOL_DIR = _SCRIPT_PATH.parent
PROJECT_ROOT = TOOL_DIR.parent
TOOL_DIR_NAME_IN_PROJECT = TOOL_DIR.name # Should be 'auto_feature_tool'

CONFIG_FILE_PATH = TOOL_DIR / "config_builder" / "config.yaml"
CONFIG_EXAMPLE_FILE_PATH = TOOL_DIR / "config_builder" / "config.yaml.example"

FEATURE_SEPARATOR = "--- FEATURE SEPARATOR ---"

# --- Logging ---
def log_info(message):
    print(f"[INFO] {message}")

def log_error(message):
    print(f"[ERROR] {message}", file=sys.stderr)

def log_warn(message):
    print(f"[WARN] {message}", file=sys.stderr)

def display_paths(config):
    log_info("--- Path Configuration ---")
    log_info(f"Project Root (derived from script location): {PROJECT_ROOT.resolve()}")
    log_info(f"Tool Directory (absolute): {TOOL_DIR.resolve()}")
    log_info(f"Config File Used: {CONFIG_FILE_PATH.resolve()}")
    
    paths_config = config.get('paths', {})
    log_info(f"  Project Context: {(PROJECT_ROOT / paths_config['project_context']).resolve()} (from config: '{paths_config['project_context']}')")
    log_info(f"  Repo Contents: {(PROJECT_ROOT / paths_config['repo_contents']).resolve()} (from config: '{paths_config['repo_contents']}')")
    log_info(f"  Features File: {(PROJECT_ROOT / paths_config['features_file']).resolve()} (from config: '{paths_config['features_file']}')")
    log_info(f"  Claude Rules: {(PROJECT_ROOT / paths_config['claude_rules']).resolve()} (from config: '{paths_config['claude_rules']}')")
    log_info(f"  Guides Directory: {(PROJECT_ROOT / paths_config['guides_dir']).resolve()} (from config: '{paths_config['guides_dir']}')")
    log_info(f"  Claude Temp Commands Dir: {(PROJECT_ROOT / paths_config['claude_temp_commands_dir']).resolve()} (from config: '{paths_config['claude_temp_commands_dir']}')")
    log_info("--- End Path Configuration ---")

def load_config():
    if not CONFIG_FILE_PATH.is_file():
        log_error(f"Configuration file not found: {CONFIG_FILE_PATH}")
        log_error(f"Please copy {CONFIG_EXAMPLE_FILE_PATH} to {CONFIG_FILE_PATH} and customize it.")
        sys.exit(1)
    
    with open(CONFIG_FILE_PATH, 'r', encoding='utf-8') as f:
        config = yaml.safe_load(f)
    
    config.setdefault('openrouter', {})
    config['openrouter'].setdefault('api_key', "YOUR_OPENROUTER_API_KEY_HERE")
    config['openrouter'].setdefault('gemini_model', "google/gemini-2.5-pro")
    config['openrouter'].setdefault('site_url', "<YOUR_SITE_URL_OR_PROJECT_URL>")
    config['openrouter'].setdefault('site_name', "<YOUR_APP_OR_PROJECT_NAME>")

    config.setdefault('paths', {})
    config['paths'].setdefault('project_context', "project_context.md")
    config['paths'].setdefault('repo_contents', "repo_contents.txt")
    config['paths'].setdefault('features_file', "features_to_implement.txt")
    # Default claude_rules path is relative to project root, pointing into the tool dir
    default_claude_rules_path = f"{TOOL_DIR_NAME_IN_PROJECT}/CLAUDE_AGENT_RULES.md"
    config['paths'].setdefault('claude_rules', default_claude_rules_path)
    config['paths'].setdefault('guides_dir', "docs/guides")
    config['paths'].setdefault('claude_temp_commands_dir', ".claude/commands")
    
    config.setdefault('script_behavior', {})
    config['script_behavior'].setdefault('human_review', False)
    config['script_behavior'].setdefault('auto_update_repo_contents', True) # New: control auto-update

    config.setdefault('claude_code', {})
    config['claude_code'].setdefault('cli_path', "claude")

    return config

def validate_config_and_paths(config):
    if config['openrouter']['api_key'] == "YOUR_OPENROUTER_API_KEY_HERE" or not config['openrouter']['api_key']:
        log_error(f"OPENROUTER_API_KEY is not set or is still the default placeholder in {CONFIG_FILE_PATH}.")
        sys.exit(1)

    claude_exec = config['claude_code']['cli_path']
    if not shutil.which(claude_exec):
        log_error(f"Claude Code CLI ('{claude_exec}') not found. Install via 'npm install -g @anthropic-ai/claude-code' or set path in {CONFIG_FILE_PATH}.")
        sys.exit(1)
    
    if not shutil.which("git"):
        log_warn("git command not found. 'git status' and repo update features might not work correctly.")

    paths_to_check = {
        "Project Context": Path(config['paths']['project_context']),
        "Repository Contents": Path(config['paths']['repo_contents']),
        "Features File": Path(config['paths']['features_file']),
        "Claude Rules File": Path(config['paths']['claude_rules']),
    }
    for name, rel_path_str in paths_to_check.items():
        # Ensure rel_path_str is not None or empty before creating Path object
        if not rel_path_str:
            log_error(f"Configuration for '{name}' path is empty. Please check your config.yaml.")
            sys.exit(1)
        rel_path = Path(rel_path_str)
        abs_path = PROJECT_ROOT / rel_path
        if not abs_path.is_file():
            log_error(f"{name} file not found: {abs_path} (configured as '{rel_path_str}')")
            sys.exit(1)

def sanitize_filename_for_path(name: str) -> str:
    name = name.lower()
    name = re.sub(r'[\s\W]+', '_', name) 
    name = re.sub(r'_+', '_', name)      
    name = name.strip('_')              
    return name

def parse_features_file(features_file_path: Path):
    if not features_file_path.is_file():
        log_error(f"Features file not found: {features_file_path}")
        return []
    
    with open(features_file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    feature_blocks_raw = content.split(FEATURE_SEPARATOR)
    parsed_features = []

    for block_raw in feature_blocks_raw:
        block = block_raw.strip()
        if not block:
            continue

        name = None
        description_lines = []
        in_description_section = False

        for line_idx, line in enumerate(block.splitlines()):
            line_stripped = line.strip()
            if line_idx == 0 and line_stripped.startswith("Feature:"):
                name = line_stripped.replace("Feature:", "", 1).strip()
            elif line_stripped.startswith("Description:"):
                description_lines.append(line_stripped.replace("Description:", "", 1).strip())
                in_description_section = True
            elif in_description_section: 
                description_lines.append(line) 
        
        if name:
            full_description = "\n".join(description_lines).strip()
            parsed_features.append({ "name": name, "description": full_description })
            if not full_description:
                 log_warn(f"Feature '{name}' has an empty description section.")
        else:
            log_warn(f"Could not parse a feature name from block: '{block[:70]}...'")
            
    return parsed_features

def call_openrouter_api(config, prompt_text: str):
    api_key = config['openrouter']['api_key']
    model = config['openrouter']['gemini_model']
    site_url = config['openrouter']['site_url']
    site_name = config['openrouter']['site_name']
    
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "HTTP-Referer": site_url,
        "X-Title": site_name,
    }
    data = {"model": model, "messages": [{"role": "user", "content": prompt_text}]}
    
    log_info(f"Calling OpenRouter API with model: {model}...")
    try:
        response = requests.post("https://openrouter.ai/api/v1/chat/completions", headers=headers, json=data, timeout=300)
        response.raise_for_status()
        response_json = response.json()
        content = response_json.get("choices", [{}])[0].get("message", {}).get("content")
        if content:
            return content
        else:
            log_error(f"OpenRouter API response missing expected content. Response: {response_json}")
            return None
    except requests.exceptions.RequestException as e:
        log_error(f"OpenRouter API call failed: {e}")
        if hasattr(e, 'response') and e.response is not None:
            log_error(f"Response status: {e.response.status_code}, Response text: {e.response.text[:500]}")
        return None

def run_claude_code(claude_cli_path: str, project_command_slug: str, temp_command_file_path: Path):
    claude_command_parts = [
        claude_cli_path,
        "-p", f"/project:{project_command_slug}",
        "--dangerously-skip-permissions"
    ]
    log_info(f"Executing Claude Code: {' '.join(claude_command_parts)}")
    log_info(f"Claude task details defined in: {temp_command_file_path.resolve()}")

    try:
        process = subprocess.Popen(claude_command_parts, cwd=PROJECT_ROOT, text=True, 
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, 
                                   bufsize=1, universal_newlines=True)
        
        log_info("--- Claude Code Output START ---")
        # Stream stdout
        if process.stdout:
            for stdout_line in iter(process.stdout.readline, ""):
                print(stdout_line, end="")
                sys.stdout.flush() # Ensure real-time output
            process.stdout.close()
        
        # Stream stderr
        stderr_output_full = ""
        if process.stderr:
            for stderr_line in iter(process.stderr.readline, ""):
                stderr_output_full += stderr_line
                print(stderr_line, end="", file=sys.stderr)
                sys.stderr.flush() # Ensure real-time output
            process.stderr.close()
        
        return_code = process.wait()
        log_info("--- Claude Code Output END ---") # Signifies end of streaming

        if return_code == 0:
            log_info(f"Claude Code finished successfully for task: {project_command_slug}")
            return True
        else:
            log_error(f"Claude Code command failed with exit code {return_code} for task: {project_command_slug}")
            # If there was stderr, it's already printed.
            return False
    except FileNotFoundError:
        log_error(f"Claude CLI executable '{claude_cli_path}' not found. Check config and PATH.")
        return False
    except Exception as e:
        log_error(f"An error occurred while running Claude Code: {e}")
        return False

def main():
    config = load_config()
    display_paths(config) 
    validate_config_and_paths(config)

    project_context_file_abs = PROJECT_ROOT / config['paths']['project_context']
    repo_contents_file_abs = PROJECT_ROOT / config['paths']['repo_contents'] # Used for reading initially and for update target
    features_input_file_abs = PROJECT_ROOT / config['paths']['features_file']
    
    claude_rules_file_for_prompt = Path(config['paths']['claude_rules']) 
    guides_dir_for_prompt = Path(config['paths']['guides_dir'])

    guides_output_dir_abs = PROJECT_ROOT / config['paths']['guides_dir']
    claude_temp_commands_dir_abs = PROJECT_ROOT / config['paths']['claude_temp_commands_dir']
    
    claude_cli_path = config['claude_code']['cli_path']
    human_review_enabled = config['script_behavior']['human_review']
    auto_update_repo_contents = config['script_behavior']['auto_update_repo_contents']

    guides_output_dir_abs.mkdir(parents=True, exist_ok=True)
    claude_temp_commands_dir_abs.mkdir(parents=True, exist_ok=True)

    try:
        project_context_content = project_context_file_abs.read_text(encoding='utf-8')
        # Initial read of repo_contents.txt
        repo_contents_content = repo_contents_file_abs.read_text(encoding='utf-8') 
    except Exception as e:
        log_error(f"Error reading initial context files: {e}")
        sys.exit(1)

    features = parse_features_file(features_input_file_abs)
    if not features:
        log_info(f"No features found to process in {features_input_file_abs}.")
        sys.exit(0)

    log_info(f"Found {len(features)} features to process.")

    for index, feature_item in enumerate(features):
        feature_idx_display = index + 1
        current_feature_name = feature_item['name']
        current_feature_description = feature_item['description']
        
        log_info(f"\n--- Preparing for Feature {feature_idx_display}/{len(features)}: {current_feature_name} ---")

        if auto_update_repo_contents:
            log_info(f"Attempting to update repository contents file: {repo_contents_file_abs.name}")
            # Assumes 'git dump' command outputs to stdout, which we redirect to the file.
            # User must ensure 'git dump' is an alias/script in PATH.
            update_command = f"git dump > \"{repo_contents_file_abs.as_posix()}\""
            try:
                process = subprocess.run(update_command, shell=True, check=True, cwd=PROJECT_ROOT, capture_output=True, text=True)
                log_info(f"Successfully updated '{repo_contents_file_abs.name}'.")
                # Reload repo_contents_content for the current feature
                repo_contents_content = repo_contents_file_abs.read_text(encoding='utf-8')
            except subprocess.CalledProcessError as e:
                log_error(f"Failed to update '{repo_contents_file_abs.name}' using '{update_command}'. Error: {e.stderr.strip()}")
                log_warn("Proceeding with potentially stale repository contents for planning.")
            except FileNotFoundError: # If 'git' or 'git dump' is not found
                log_error(f"Command for '{update_command}' not found. Ensure 'git' is in PATH and 'git dump' is a valid command/alias.")
                log_warn("Proceeding with potentially stale repository contents for planning.")
            except Exception as e:
                log_error(f"An unexpected error occurred while updating '{repo_contents_file_abs.name}': {e}")
                log_warn("Proceeding with potentially stale repository contents for planning.")
        else:
            log_info("Skipping automatic update of repository contents file as per configuration.")

        log_info(f"--- Processing Feature {feature_idx_display}/{len(features)}: {current_feature_name} ---")

        sanitized_name = sanitize_filename_for_path(current_feature_name)
        guide_filename = f"{feature_idx_display}_{sanitized_name}_change.md"
        
        guide_path_for_claude = guides_dir_for_prompt / guide_filename 
        guide_path_abs = guides_output_dir_abs / guide_filename      

        gemini_prompt = f"""You are an expert software architect. Given the following project context, repository contents, and a specific feature request, generate a detailed step-by-step implementation plan in Markdown format. This plan will be used by an AI coding assistant (Claude Code) to write the actual code. The plan should be clear, actionable, and provide enough detail for the AI to understand the requirements, necessary code changes, new files to create, and expected outcomes.

Feature Request:
Title: {current_feature_name}
Description:
{current_feature_description}

Project Context:
---
{project_context_content}
---

Repository Contents (structure and key file snippets):
---
{repo_contents_content} 
---

Produce only the Markdown implementation plan."""

        implementation_guide = call_openrouter_api(config, gemini_prompt)
        if not implementation_guide:
            log_error(f"Skipping feature '{current_feature_name}' due to guide generation failure.")
            continue
        
        try:
            guide_path_abs.write_text(implementation_guide, encoding='utf-8')
            log_info(f"Implementation guide saved to: {guide_path_abs}")
        except Exception as e:
            log_error(f"Failed to write implementation guide to {guide_path_abs}: {e}. Skipping feature.")
            continue

        temp_claude_cmd_slug_base = f"feature_{feature_idx_display}_{sanitized_name}_task"
        temp_claude_cmd_slug = re.sub(r'[^a-zA-Z0-9_-]+', '', temp_claude_cmd_slug_base.replace('_', '-'))
        if not temp_claude_cmd_slug: temp_claude_cmd_slug = "default-task" 
        
        temp_cmd_file_path_abs = claude_temp_commands_dir_abs / f"{temp_claude_cmd_slug}.md"

        claude_task_md = f"""Your current task is to implement the feature: "{current_feature_name}".

1.  First, carefully read and understand the detailed implementation plan provided in the file: `{guide_path_for_claude.as_posix()}`
    You can use the command: `/read "{guide_path_for_claude.as_posix()}"` to load it.

2.  After understanding the plan, proceed to implement all necessary code changes, create new files, and modify existing ones as described.

3.  While working, you MUST strictly adhere to all guidelines specified in the document located at `{claude_rules_file_for_prompt.as_posix()}`.
    If you are unsure about these rules, you can use `/read "{claude_rules_file_for_prompt.as_posix()}"` to review them.

4.  Key development practices to follow (as per the rules):
    *   Write unit tests for new functionality and ensure all tests pass.
    *   Confirm that the implemented code runs correctly and the feature works as expected.
    *   Clearly state what tests you ran or how you verified the functionality.

5.  Once you have successfully implemented the feature, verified it, and ensured tests pass:
    *   Stage all relevant changes using an appropriate git add command (e.g., `/git add .` or list specific files).
    *   Commit the changes with the exact commit message: `feat: Implement {current_feature_name}`
       (Use the command: `/git commit -m "feat: Implement {current_feature_name}"`)

Execute all these steps autonomously and comprehensively. Begin by reading the implementation plan.
"""
        try:
            temp_cmd_file_path_abs.write_text(claude_task_md, encoding='utf-8')
        except Exception as e:
            log_error(f"Failed to write temporary Claude command file: {e}. Skipping feature.")
            continue

        claude_success = run_claude_code(claude_cli_path, temp_claude_cmd_slug, temp_cmd_file_path_abs)

        try:
            temp_cmd_file_path_abs.unlink(missing_ok=True)
            log_info(f"Cleaned up temporary Claude command file: {temp_cmd_file_path_abs}")
        except Exception as e:
            log_warn(f"Could not remove temporary Claude command file {temp_cmd_file_path_abs}: {e}")

        if not claude_success:
            log_error(f"Claude Code failed for '{current_feature_name}'. Manual review advised.")

        if human_review_enabled:
            print("-" * 50)
            log_info(f"Feature '{current_feature_name}' processed by Claude. Review changes and commit status.")
            try:
                log_info("Current Git status (short):")
                subprocess.run(["git", "status", "-s"], cwd=PROJECT_ROOT, check=False)
                log_info("Last commit:")
                subprocess.run(["git", "log", "-n", "1", "--oneline"], cwd=PROJECT_ROOT, check=False)
            except Exception as e:
                log_warn(f"Could not get git status/log: {e}")
            input("Press Enter for next feature, or Ctrl+C to abort.")

    log_info("\nAll features processed.")

if __name__ == "__main__":
    main()
```

**2. `README.md` (Updated Sections)**

I'll update the relevant sections in your `README.md`:

*   Under **Process Flow**: Add a note about `repo_contents.txt` being updated.
*   Under **Setup > Prerequisites**: Emphasize the `git dump` command requirement.
*   Under **Usage**: Mention real-time output.
*   Under **Configuration Options**: Add `script_behavior.auto_update_repo_contents`.
*   Under **Notes and Best Practices**: Mention the `git dump` dependency for the update feature.

Here's how the `README.md` would be modified:

```markdown
# Code Builder - AI Feature Implementation Automation

This repository provides tools for automating software development through AI orchestration. The centerpiece is an AI Feature Implementation Automation Tool that leverages multiple Large Language Models (LLMs) to plan and implement features autonomously.

## AI Feature Implementation Automation Tool

This tool automates the complete process of implementing features using AI. It orchestrates different AI models for optimal results:
- **Gemini (via OpenRouter)**: Generates detailed implementation documents and guides (default model "google/gemini-2.5-pro", configurable).
- **Claude Code (local CLI)**: Writes the actual code based on the generated guides.

The tool is designed to be placed within your project's repository (e.g., in a subdirectory like `auto_feature_tool/`) and run from your project's root directory using Python.

### Process Flow

For each feature in a provided list:

0. **Update Repository Context (Optional)**: If enabled, the script attempts to update `repo_contents.txt` using a `git dump` command to reflect the latest state of the repository (including changes from previous features in the same run).

1. **Generate Implementation Document**: An LLM (Gemini) creates a detailed Markdown document outlining how to implement the feature. This uses the entire repository context (`repo_contents.txt`), a project-specific context file, and the feature description.

2. **Save Document**: The generated guide is saved to `docs/guides/{index_number}_name_of_feature.md` (configurable path).

3. **Code Implementation**: The `claude-code` CLI is invoked locally. It's given a dynamic, temporary "slash command" which instructs it to:
   - Read the generated guide.
   - Implement the feature following best practices.
   - Adhere to rules specified in `CLAUDE_AGENT_RULES.md` (testing, virtual environments, verification, git).
   - Commit the changes with proper conventional commit messages.
   Output from `claude-code` will be streamed to your terminal in real-time.

4. **Repeat**: The process repeats for all features in the list.

### Setup

#### Prerequisites

- **Python**: Version 3.7+ recommended.
- **pip**: Python package installer.
- **`claude-code` CLI**: Install globally: `npm install -g @anthropic-ai/claude-code`.
  - Ensure your Anthropic credentials are properly configured.
- **`git` CLI**: For version control operations used by `claude-code`, status display, and potentially for updating `repo_contents.txt`.
- **OpenRouter API Key**: Obtain from [OpenRouter.ai](https://openrouter.ai).
- **`git dump` (or equivalent)**: You need a command that produces a `repo_contents.txt` file at the root of your project. This file should contain a textual representation of your repository's content.
  - **Crucially**, if you enable `script_behavior.auto_update_repo_contents` (default: true), you must have a command or alias named `git dump` available in your system's PATH that outputs the repository contents to standard output. The script will run `git dump > path/to/your/repo_contents.txt`.
  - Example `git dump` script/alias (ensure it outputs to stdout):
    ```bash
    # (in your .bashrc, .zshrc, or as a script named 'git-dump' in your PATH)
    # git-dump
    (tree -L 3 --prune -I '.git|.venv|__pycache__|node_modules|dist|build|target' . && \
    find . -type f \
      -not -path "./.git/*" \
      -not -path "./.venv/*" \
      # ... other exclusions from README ...
      -not -name "repo_contents.txt" \
      -print0 | xargs -0 -I {} sh -c 'echo "\n===== {} ====="; cat "{}" 2>/dev/null || echo "Error reading file: {}"')
    ```
    If your command is different, you'll need to adapt the script or ensure `git dump` acts as a suitable wrapper.

#### Installation

1.  **Copy Tool Files**: Copy the `auto_feature_tool/` directory into your project's root.

2.  **Install Python Dependencies**:
    Navigate to your project's root directory and run:
    ```bash
    pip install -r auto_feature_tool/requirements.txt
    ```
    (It's highly recommended to do this within a Python virtual environment for your project.)
    The `auto_feature_tool/requirements.txt` includes:
    *   `PyYAML`: For parsing YAML configuration.
    *   `requests`: For making HTTP requests to the OpenRouter API.

3.  **Configure**:
    *   The configuration file is `auto_feature_tool/config_builder/config.yaml`.
    *   If it doesn't exist, copy `auto_feature_tool/config_builder/config.yaml.example` to `config.yaml`.
    *   Edit `config.yaml` and fill in your `openrouter.api_key`, desired `paths`, model preferences, etc. Pay attention to `script_behavior.auto_update_repo_contents`.
    *   **Important**: Ensure `auto_feature_tool/config_builder/config.yaml` is added to your project's `.gitignore` file to avoid committing your API key. The main `.gitignore` provided with this tool already includes this.

4.  **Prepare Input Files** (paths configurable in `config.yaml`, defaults shown, relative to project root):

    *   **Project Context** (`project_context.md`): Create a Markdown file that provides overall context about your project.
    *   **Repository Contents** (`repo_contents.txt`): Generate this file initially using your `git dump` or equivalent command. If `auto_update_repo_contents` is enabled, this file will be automatically updated by the script during its run.
    *   **Feature List** (`features_to_implement.txt`): Create a text file listing the features. (Format as before)

5.  **Review Agent Rules**:
    *   The file `auto_feature_tool/CLAUDE_AGENT_RULES.md` contains guidelines for Claude Code. Customize if needed.

### Usage

1.  Navigate to your project's root directory in the terminal.
2.  (If using a Python virtual environment, activate it).
3.  Ensure your `repo_contents.txt` (or configured path) is initially present.
4.  Run the script:
    ```bash
    python auto_feature_tool/auto_feature.py
    ```

The script will:
- Display the configuration paths it's using.
- For each feature:
    - (Optionally) Update `repo_contents.txt`.
    - Generate a detailed implementation guide.
    - Invoke `claude-code` to implement the feature, streaming its output to your terminal.
    - Clean up temporary task files.
- If `script_behavior.human_review: true`, pause for review, showing `git status` and the last commit.

### Configuration Options

Key settings in `auto_feature_tool/config_builder/config.yaml`:
(Existing options...)
- `script_behavior.auto_update_repo_contents`: (Default: `true`) Set to `false` to disable automatic updates to `repo_contents.txt` before each feature's planning phase. If `true`, requires a `git dump` command in PATH.
(Other options as before...)

### Architecture 
(Diagram remains the same)

### Notes and Best Practices
(Existing notes...)
- **Repository Context Updates**: The `script_behavior.auto_update_repo_contents` feature (default: true) helps keep the AI planner informed of changes from previous features in the same run. This relies on a `git dump` command/alias being available in your PATH that outputs the repository context to stdout.
(Other notes as before...)

### Troubleshooting
(Existing troubleshooting tips...)
6.  **`repo_contents.txt` not updating**: If `auto_update_repo_contents` is true, ensure a command or alias `git dump` is in your PATH and correctly outputs repository contents to standard output. Check script logs for errors from the update command.

---

*"Let us contemplate the elegant simplicity of automation, where each tool serves its purpose in perfect harmony."* - The Zen Master 🧘
```

The rest of the files (`.gitignore`, `LICENSE`, `auto_feature_tool/CLAUDE_AGENT_RULES.md`, `auto_feature_tool/requirements.txt`, etc.) would remain the same as in the previous `repo_contents.txt`. The `auto_feature_tool/config_builder/config.yaml.example` should ideally be updated to include the new `auto_update_repo_contents` flag.

**3. `auto_feature_tool/config_builder/config.yaml.example` (Updated)**
```yaml
# --- OpenRouter API Configuration ---
openrouter:
  api_key: "YOUR_OPENROUTER_API_KEY_HERE"
  gemini_model: "google/gemini-2.5-pro" # Or your preferred model for planning
  site_url: "<YOUR_SITE_URL_OR_PROJECT_URL>" # Optional: e.g., https://yourproject.com
  site_name: "<YOUR_APP_OR_PROJECT_NAME>"    # Optional: e.g., MyProject FeatureGen

# --- File Path Configurations (relative to project root) ---
paths:
  project_context: "project_context.md"
  repo_contents: "repo_contents.txt"
  features_file: "features_to_implement.txt"
  # Default uses the rules file within the auto_feature_tool directory
  claude_rules: "auto_feature_tool/CLAUDE_AGENT_RULES.md"
  guides_dir: "docs/guides" # Generated implementation guides will be saved here
  # claude-code usually looks for .claude/commands in the current working directory (project root)
  claude_temp_commands_dir: ".claude/commands"

# --- Script Behavior ---
script_behavior:
  # Set to true to pause for human review (git status, last commit) after each feature.
  human_review: false
  # Set to true to attempt to automatically update 'repo_contents.txt' using 'git dump > repo_contents.txt'
  # before planning each feature. Requires 'git dump' command/alias in PATH.
  auto_update_repo_contents: true

# --- Claude Code Configuration ---
claude_code:
  # Path to the claude CLI executable, if not "claude" or not in system PATH.
  cli_path: "claude"
```
These changes should address the user's requests for better visibility and more robust state management during the feature implementation loop.