Okay, I will re-implement the project as a Python script. The core functionality will be moved to `auto_feature.py`, which will use Python libraries for configuration parsing (`PyYAML`) and API calls (`requests`). The execution of `claude-code` will still be done by invoking its CLI using Python's `subprocess` module.

Here's a summary of the changes:

1.  **New Python Script**: `auto_feature_tool/auto_feature.py` will be the main executable.
2.  **Requirements File**: `auto_feature_tool/requirements.txt` will list Python dependencies.
3.  **Configuration**: Remains YAML-based (`auto_feature_tool/config_builder/config.yaml`), parsed by `PyYAML`.
4.  **README Update**: Instructions will be updated for Python execution, new dependencies (`PyYAML`, `requests`), and removal of `yq`/`jq` as direct prerequisites.
5.  **Path Display**: The Python script will print the absolute paths it's using for key configuration items at runtime.
6.  **Bash Script Removal**: `auto_feature_tool/auto_feature.sh` will be removed.

The `.gitignore`, `LICENSE`, `CLAUDE_AGENT_RULES.md`, `features_to_implement.txt.example`, and `config.yaml.example` files will remain largely the same as in the previous YAML-configured bash version, with necessary adjustments to the README.

Here are the new and updated files:

**1. `auto_feature_tool/requirements.txt` (New)**
```text
PyYAML>=5.1
requests>=2.20
```

**2. `auto_feature_tool/auto_feature.py` (New)**
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
# Assume script is run from project root, e.g., python auto_feature_tool/auto_feature.py
PROJECT_ROOT = Path.cwd() 
SCRIPT_DIR_FROM_ROOT = Path("auto_feature_tool") # Relative path of this tool's directory from project root
CONFIG_FILE_PATH = PROJECT_ROOT / SCRIPT_DIR_FROM_ROOT / "config_builder" / "config.yaml"
CONFIG_EXAMPLE_FILE_PATH = PROJECT_ROOT / SCRIPT_DIR_FROM_ROOT / "config_builder" / "config.yaml.example"

FEATURE_SEPARATOR = "--- FEATURE SEPARATOR ---"

# --- Logging ---
def log_info(message):
    print(f"[INFO] {message}")

def log_error(message):
    print(f"[ERROR] {message}", file=sys.stderr)

def log_warn(message):
    print(f"[WARN] {message}", file=sys.stderr)

def display_paths(config):
    log_info("--- Path Configuration (all paths resolved from project root) ---")
    log_info(f"Project Root (CWD): {PROJECT_ROOT.resolve()}")
    log_info(f"Tool Script Directory (expected): {(PROJECT_ROOT / SCRIPT_DIR_FROM_ROOT).resolve()}")
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
    
    # Apply defaults for potentially missing keys
    config.setdefault('openrouter', {})
    config['openrouter'].setdefault('api_key', "YOUR_OPENROUTER_API_KEY_HERE")
    config['openrouter'].setdefault('gemini_model', "google/gemini-2.5-pro")
    config['openrouter'].setdefault('site_url', "<YOUR_SITE_URL_OR_PROJECT_URL>")
    config['openrouter'].setdefault('site_name', "<YOUR_APP_OR_PROJECT_NAME>")

    config.setdefault('paths', {})
    config['paths'].setdefault('project_context', "project_context.md")
    config['paths'].setdefault('repo_contents', "repo_contents.txt")
    config['paths'].setdefault('features_file', "features_to_implement.txt")
    # Default claude_rules path relative to project root
    default_claude_rules_path = (SCRIPT_DIR_FROM_ROOT / "CLAUDE_AGENT_RULES.md").as_posix()
    config['paths'].setdefault('claude_rules', default_claude_rules_path)
    config['paths'].setdefault('guides_dir', "docs/guides")
    config['paths'].setdefault('claude_temp_commands_dir', ".claude/commands")
    
    config.setdefault('script_behavior', {})
    config['script_behavior'].setdefault('human_review', False)

    config.setdefault('claude_code', {})
    config['claude_code'].setdefault('cli_path', "claude")

    return config

def validate_config_and_paths(config):
    if config['openrouter']['api_key'] == "YOUR_OPENROUTER_API_KEY_HERE" or not config['openrouter']['api_key']:
        log_error(f"OPENROUTER_API_KEY is not set or is still the default placeholder in {CONFIG_FILE_PATH}.")
        sys.exit(1)

    claude_exec = config['claude_code']['cli_path']
    if not shutil.which(claude_exec):
        log_error(f"Claude Code CLI ('{claude_exec}') not found. Please install it (e.g., npm install -g @anthropic-ai/claude-code) and ensure it's in your PATH or configured in {CONFIG_FILE_PATH}.")
        sys.exit(1)
    
    if not shutil.which("git"):
        log_warn("git command not found. 'git status' for human review might not work.")

    paths_to_check = {
        "Project Context": Path(config['paths']['project_context']),
        "Repository Contents": Path(config['paths']['repo_contents']),
        "Features File": Path(config['paths']['features_file']),
        "Claude Rules File": Path(config['paths']['claude_rules']),
    }
    for name, rel_path in paths_to_check.items():
        abs_path = PROJECT_ROOT / rel_path
        if not abs_path.is_file():
            log_error(f"{name} file not found: {abs_path} (configured as '{rel_path}')")
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

        for line in block.splitlines():
            line_stripped = line.strip()
            if line_stripped.startswith("Feature:"):
                name = line_stripped.replace("Feature:", "", 1).strip()
            elif line_stripped.startswith("Description:"):
                description_lines.append(line_stripped.replace("Description:", "", 1).strip())
                in_description_section = True
            elif in_description_section:
                description_lines.append(line) # Keep original spacing for subsequent lines
        
        if name:
            full_description = "\n".join(description_lines).strip()
            parsed_features.append({
                "name": name,
                "description": full_description
            })
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
        response = requests.post("https://openrouter.ai/api/v1/chat/completions", headers=headers, json=data, timeout=300) # 5 min timeout
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
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        
        log_info("--- Claude Code Output START ---")
        for stdout_line in iter(process.stdout.readline, ""):
            print(stdout_line, end="") # Already has newline
        process.stdout.close()
        
        stderr_output = ""
        for stderr_line in iter(process.stderr.readline, ""):
            stderr_output += stderr_line
            print(stderr_line, end="", file=sys.stderr) # Already has newline
        process.stderr.close()
        log_info("--- Claude Code Output END ---")
        
        return_code = process.wait()

        if return_code == 0:
            log_info(f"Claude Code finished successfully for task: {project_command_slug}")
            return True
        else:
            log_error(f"Claude Code command failed with exit code {return_code} for task: {project_command_slug}")
            return False
    except FileNotFoundError:
        log_error(f"Claude CLI executable not found at '{claude_cli_path}'. Check config and PATH.")
        return False
    except Exception as e:
        log_error(f"An error occurred while running Claude Code: {e}")
        return False

def main():
    config = load_config()
    display_paths(config) 
    validate_config_and_paths(config)

    # Get absolute paths for file operations, relative for claude prompts
    project_context_file = PROJECT_ROOT / config['paths']['project_context']
    repo_contents_file = PROJECT_ROOT / config['paths']['repo_contents']
    features_input_file = PROJECT_ROOT / config['paths']['features_file']
    
    # These paths are used INSIDE the claude prompt, so they must be relative to project root
    claude_rules_file_for_prompt = Path(config['paths']['claude_rules']) 
    guides_dir_for_prompt = Path(config['paths']['guides_dir'])

    # These paths are for script's file I/O, so absolute
    guides_output_dir_abs = PROJECT_ROOT / config['paths']['guides_dir']
    claude_temp_commands_dir_abs = PROJECT_ROOT / config['paths']['claude_temp_commands_dir']
    
    claude_cli_path = config['claude_code']['cli_path']
    human_review_enabled = config['script_behavior']['human_review']

    guides_output_dir_abs.mkdir(parents=True, exist_ok=True)
    claude_temp_commands_dir_abs.mkdir(parents=True, exist_ok=True)

    try:
        project_context_content = project_context_file.read_text(encoding='utf-8')
        repo_contents_content = repo_contents_file.read_text(encoding='utf-8')
    except Exception as e:
        log_error(f"Error reading context files: {e}")
        sys.exit(1)

    features = parse_features_file(features_input_file)
    if not features:
        log_info("No features found to process in {features_input_file}.")
        sys.exit(0)

    log_info(f"Found {len(features)} features to process.")

    for index, feature_item in enumerate(features):
        feature_idx_display = index + 1
        current_feature_name = feature_item['name']
        current_feature_description = feature_item['description']
        
        log_info(f"\n--- Processing Feature {feature_idx_display}/{len(features)}: {current_feature_name} ---")

        sanitized_name = sanitize_filename_for_path(current_feature_name)
        guide_filename = f"{feature_idx_display}_{sanitized_name}_change.md"
        
        guide_path_for_claude = guides_dir_for_prompt / guide_filename # Relative path for /read
        guide_path_abs = guides_output_dir_abs / guide_filename       # Absolute path for writing

        gemini_prompt = f"""You are an expert software architect...
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
Produce only the Markdown implementation plan.""" # (Shortened for brevity)

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
        # Sanitize again for claude slug (alphanumeric, -, _)
        temp_claude_cmd_slug = re.sub(r'[^a-zA-Z0-9_-]', '', temp_claude_cmd_slug_base.replace('_', '-')) 
        temp_cmd_file_path_abs = claude_temp_commands_dir_abs / f"{temp_claude_cmd_slug}.md"

        claude_task_md = f"""Your current task is to implement the feature: "{current_feature_name}".

1.  First, read: `/read "{guide_path_for_claude.as_posix()}"`
2.  Then, read agent rules: `/read "{claude_rules_file_for_prompt.as_posix()}"`
3.  Implement the feature based on the guide, adhering to the rules.
4.  Key actions: Write code, write tests, ensure tests pass, verify functionality.
5.  Finally, commit changes: `/git commit -m "feat: Implement {current_feature_name}"` (after appropriate \`/git add ...\`)

Execute autonomously. Begin by reading the implementation plan.
""" # (Shortened for brevity, full details from previous version would be here)
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
            log_info(f"Feature '{current_feature_name}' processed. Review changes.")
            try:
                log_info("Current Git status:")
                subprocess.run(["git", "status", "-s"], cwd=PROJECT_ROOT, check=False) # Allow non-zero exit if no changes
            except Exception as e:
                log_warn(f"Could not get git status: {e}")
            input("Press Enter for next feature, or Ctrl+C to abort.")

    log_info("\nAll features processed.")

if __name__ == "__main__":
    # Ensure the script is run from project root for consistent path resolution
    if not (PROJECT_ROOT / SCRIPT_DIR_FROM_ROOT / Path(__file__).name).exists():
        log_error(f"This script ({Path(__file__).name}) must be run from the project root directory, "
                  f"where '{SCRIPT_DIR_FROM_ROOT}' is a subdirectory.")
        log_error(f"Current CWD: {PROJECT_ROOT.resolve()}")
        log_error(f"Expected script location relative to CWD: {SCRIPT_DIR_FROM_ROOT / Path(__file__).name}")
        # sys.exit(1) # This check might be too strict if symlinks or complex setups are used.
                      # Relying on config file presence is primary.

    # Restore full prompts for Gemini and Claude task from previous response for completeness
    # The actual implementation of main() would have the full prompts.
    # For example, the gemini_prompt should be the full multi-line string.
    # The claude_task_md should also be the full multi-line string.
    # This placeholder is just to keep the response size manageable here.
    # In the actual file, these would be:
    # gemini_prompt = f"""You are an expert software architect... FULL PROMPT ..."""
    # claude_task_md = f"""Your current task is to implement the feature ... FULL PROMPT ..."""
    # (Using the full prompts from the previous bash script version)
    main()
```
*Self-correction*: The `gemini_prompt` and `claude_task_md` in the Python script above were shortened for brevity in this thought block. The actual generated Python file should contain the full, detailed prompts as defined in the previous bash script logic. I will ensure the final output uses the full prompts.
The check for running from project root using `(PROJECT_ROOT / SCRIPT_DIR_FROM_ROOT / Path(__file__).name).exists()` is a good heuristic.

**3. `README.md` (Updated)**
I will provide the updated `README.md` reflecting Python usage and new dependencies. The content will be similar to what was drafted in the thought block:
*   Prerequisites: Python 3.7+, pip, `claude-code` CLI, `git` CLI, OpenRouter API Key, `git dump` equivalent.
*   Installation: Copy `auto_feature_tool/`, `pip install -r auto_feature_tool/requirements.txt`, configure `config.yaml`.
*   Input Files: `project_context.md`, `repo_contents.txt`, `features_to_implement.txt`.
*   Usage: `python auto_feature_tool/auto_feature.py`.

**4. Removal of `auto_feature_tool/auto_feature.sh`**
This file will be omitted from the output, as it's replaced by the Python script.

The other files (`.gitignore`, `LICENSE`, `CLAUDE_AGENT_RULES.md`, `features_to_implement.txt.example`, `config.yaml.example`) remain as they were in your last provided context.

I will now generate the full content for `auto_feature.py` (with full prompts) and the updated `README.md`. The `requirements.txt` is already defined. The `.gitignore` provided by you is suitable. The other helper files are also suitable.

```python
# auto_feature_tool/auto_feature.py
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
# Assume script is run from project root, e.g., python auto_feature_tool/auto_feature.py
PROJECT_ROOT = Path.cwd() 
SCRIPT_DIR_FROM_ROOT = Path("auto_feature_tool") # Relative path of this tool's directory from project root
CONFIG_FILE_PATH = PROJECT_ROOT / SCRIPT_DIR_FROM_ROOT / "config_builder" / "config.yaml"
CONFIG_EXAMPLE_FILE_PATH = PROJECT_ROOT / SCRIPT_DIR_FROM_ROOT / "config_builder" / "config.yaml.example"

FEATURE_SEPARATOR = "--- FEATURE SEPARATOR ---"

# --- Logging ---
def log_info(message):
    print(f"[INFO] {message}")

def log_error(message):
    print(f"[ERROR] {message}", file=sys.stderr)

def log_warn(message):
    print(f"[WARN] {message}", file=sys.stderr)

def display_paths(config):
    log_info("--- Path Configuration (all paths resolved from project root) ---")
    log_info(f"Project Root (CWD): {PROJECT_ROOT.resolve()}")
    log_info(f"Tool Script Directory (expected relative to root): {SCRIPT_DIR_FROM_ROOT}")
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
    default_claude_rules_path = (SCRIPT_DIR_FROM_ROOT / "CLAUDE_AGENT_RULES.md").as_posix()
    config['paths'].setdefault('claude_rules', default_claude_rules_path)
    config['paths'].setdefault('guides_dir', "docs/guides")
    config['paths'].setdefault('claude_temp_commands_dir', ".claude/commands")
    
    config.setdefault('script_behavior', {})
    config['script_behavior'].setdefault('human_review', False)

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
        log_warn("git command not found. 'git status' for human review might not work correctly.")

    paths_to_check = {
        "Project Context": Path(config['paths']['project_context']),
        "Repository Contents": Path(config['paths']['repo_contents']),
        "Features File": Path(config['paths']['features_file']),
        "Claude Rules File": Path(config['paths']['claude_rules']),
    }
    for name, rel_path in paths_to_check.items():
        abs_path = PROJECT_ROOT / rel_path
        if not abs_path.is_file():
            log_error(f"{name} file not found: {abs_path} (configured as '{rel_path}')")
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
            elif in_description_section: # Append subsequent lines of the description
                description_lines.append(line) # Keep original spacing for multi-line description
        
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
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=1, universal_newlines=True)
        
        log_info("--- Claude Code Output START ---")
        if process.stdout:
            for stdout_line in iter(process.stdout.readline, ""):
                print(stdout_line, end="") 
            process.stdout.close()
        
        stderr_output = ""
        if process.stderr:
            for stderr_line in iter(process.stderr.readline, ""):
                stderr_output += stderr_line
                print(stderr_line, end="", file=sys.stderr) 
            process.stderr.close()
        log_info("--- Claude Code Output END ---")
        
        return_code = process.wait()

        if return_code == 0:
            log_info(f"Claude Code finished successfully for task: {project_command_slug}")
            return True
        else:
            log_error(f"Claude Code command failed with exit code {return_code} for task: {project_command_slug}")
            return False
    except FileNotFoundError:
        log_error(f"Claude CLI executable '{claude_cli_path}' not found. Check config and PATH.")
        return False
    except Exception as e:
        log_error(f"An error occurred while running Claude Code: {e}")
        return False

def main():
    if not (PROJECT_ROOT / SCRIPT_DIR_FROM_ROOT / Path(__file__).name).is_file():
        log_warn(f"Script seems to be run from an unexpected location. CWD: {PROJECT_ROOT.resolve()}")
        log_warn(f"Expected script location relative to CWD: {SCRIPT_DIR_FROM_ROOT / Path(__file__).name}")
        log_warn("Ensure you are running this script from your project's root directory.")

    config = load_config()
    display_paths(config) 
    validate_config_and_paths(config)

    project_context_file = PROJECT_ROOT / config['paths']['project_context']
    repo_contents_file = PROJECT_ROOT / config['paths']['repo_contents']
    features_input_file = PROJECT_ROOT / config['paths']['features_file']
    
    claude_rules_file_for_prompt = Path(config['paths']['claude_rules']) 
    guides_dir_for_prompt = Path(config['paths']['guides_dir'])

    guides_output_dir_abs = PROJECT_ROOT / config['paths']['guides_dir']
    claude_temp_commands_dir_abs = PROJECT_ROOT / config['paths']['claude_temp_commands_dir']
    
    claude_cli_path = config['claude_code']['cli_path']
    human_review_enabled = config['script_behavior']['human_review']

    guides_output_dir_abs.mkdir(parents=True, exist_ok=True)
    claude_temp_commands_dir_abs.mkdir(parents=True, exist_ok=True)

    try:
        project_context_content = project_context_file.read_text(encoding='utf-8')
        repo_contents_content = repo_contents_file.read_text(encoding='utf-8')
    except Exception as e:
        log_error(f"Error reading context files: {e}")
        sys.exit(1)

    features = parse_features_file(features_input_file)
    if not features:
        log_info(f"No features found to process in {features_input_file}.")
        sys.exit(0)

    log_info(f"Found {len(features)} features to process.")

    for index, feature_item in enumerate(features):
        feature_idx_display = index + 1
        current_feature_name = feature_item['name']
        current_feature_description = feature_item['description']
        
        log_info(f"\n--- Processing Feature {feature_idx_display}/{len(features)}: {current_feature_name} ---")

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
        if not temp_claude_cmd_slug: temp_claude_cmd_slug = "default-task" # fallback
        
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
            log_info(f"Feature '{current_feature_name}' processed. Review changes.")
            try:
                log_info("Current Git status:")
                subprocess.run(["git", "status", "-s"], cwd=PROJECT_ROOT, check=False) 
            except Exception as e:
                log_warn(f"Could not get git status: {e}")
            input("Press Enter for next feature, or Ctrl+C to abort.")

    log_info("\nAll features processed.")

if __name__ == "__main__":
    main()
```

**Updated `README.md`** (Content from thought process, to be placed in `README.md`)
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

1. **Generate Implementation Document**: An LLM (Gemini) creates a detailed Markdown document outlining how to implement the feature. This uses the entire repository context (`repo_contents.txt`), a project-specific context file, and the feature description.

2. **Save Document**: The generated guide is saved to `docs/guides/{index_number}_name_of_feature.md` (configurable path).

3. **Code Implementation**: The `claude-code` CLI is invoked locally. It's given a dynamic, temporary "slash command" which instructs it to:
   - Read the generated guide.
   - Implement the feature following best practices.
   - Adhere to rules specified in `CLAUDE_AGENT_RULES.md` (testing, virtual environments, verification, git).
   - Commit the changes with proper conventional commit messages.

4. **Repeat**: The process repeats for all features in the list.

### Setup

#### Prerequisites

- **Python**: Version 3.7+ recommended.
- **pip**: Python package installer.
- **`claude-code` CLI**: Install globally: `npm install -g @anthropic-ai/claude-code`.
  - Ensure your Anthropic credentials are properly configured.
- **`git` CLI**: For version control operations used by `claude-code` and for status display.
- **OpenRouter API Key**: Obtain from [OpenRouter.ai](https://openrouter.ai).
- **`git dump` (or equivalent)**: You need a command that produces a `repo_contents.txt` file at the root of your project. This file should contain a textual representation of your repository's content.

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
    *   Edit `config.yaml` and fill in your `openrouter.api_key`, desired `paths`, model preferences, etc.
    *   **Important**: Ensure `auto_feature_tool/config_builder/config.yaml` is added to your project's `.gitignore` file to avoid committing your API key. The main `.gitignore` provided with this tool already includes this.

4.  **Prepare Input Files** (paths configurable in `config.yaml`, defaults shown, relative to project root):

    *   **Project Context** (`project_context.md`): Create a Markdown file that provides overall context about your project (e.g., main technologies, purpose, high-level architecture).
    *   **Repository Contents** (`repo_contents.txt`): Generate this file using your `git dump` or equivalent command. Example for generating `repo_contents.txt`:
      ```bash
      # Example: Adjust depth and excludes as needed
      (tree -L 3 --prune -I '.git|.venv|__pycache__|node_modules|dist|build|target' . && \
      find . -type f \
        -not -path "./.git/*" \
        -not -path "./.venv/*" \
        -not -path "./**/__pycache__/*" \
        -not -path "./node_modules/*" \
        -not -path "./dist/*" \
        -not -path "./build/*" \
        -not -path "./target/*" \
        -not -name "*.pyc" \
        -not -name "*.sqlite3" \
        -not -name "*.db" \
        -not -name "repo_contents.txt" \
        -print0 | xargs -0 -I {} sh -c 'echo "\n===== {} ====="; cat "{}" 2>/dev/null || echo "Error reading file: {}"') > repo_contents.txt
      ```
    *   **Feature List** (`features_to_implement.txt`): Create a text file listing the features to be implemented. Use the format shown in `auto_feature_tool/features_to_implement.txt.example`:
        ```text
        Feature: Name of Feature One
        Description:
        Multi-line description of feature one.
        Details about what needs to be done.
        --- FEATURE SEPARATOR ---
        Feature: Name of Feature Two
        Description:
        Description for feature two.
        ```

5.  **Review Agent Rules**:
    *   The file `auto_feature_tool/CLAUDE_AGENT_RULES.md` contains guidelines for Claude Code.
    *   Customize it if needed to better suit your project's specific requirements. Its path is configurable in `config.yaml` (default: `auto_feature_tool/CLAUDE_AGENT_RULES.md`).

### Usage

1.  Navigate to your project's root directory in the terminal.
2.  (If using a Python virtual environment, activate it).
3.  Ensure your `repo_contents.txt` (or configured path) is up-to-date.
4.  Run the script:
    ```bash
    python auto_feature_tool/auto_feature.py
    ```

The script will:
- Display the configuration paths it's using.
- Process each feature:
    - Generate a detailed implementation guide in `docs/guides/` (or configured path).
    - Invoke `claude-code` to implement the feature autonomously.
    - Create temporary task files in `.claude/commands/` (or configured path), which are cleaned up afterwards.
- If `script_behavior.human_review: true` in `auto_feature_tool/config_builder/config.yaml`, the script will pause after each feature for your review and show `git status`.

### Configuration Options

Key settings in `auto_feature_tool/config_builder/config.yaml`:

- `openrouter.api_key`: Your OpenRouter API key.
- `openrouter.gemini_model`: Model identifier for OpenRouter (e.g., "google/gemini-2.5-pro").
- `paths.project_context`: Path to your project context file.
- `paths.repo_contents`: Path to your repository contents dump.
- `paths.features_file`: Path to your features list.
- `paths.claude_rules`: Path to the rules file for Claude.
- `paths.guides_dir`: Directory where implementation guides are saved.
- `paths.claude_temp_commands_dir`: Directory for Claude's temporary task files.
- `script_behavior.human_review`: Set to `true` to pause for review after each feature.
- `claude_code.cli_path`: Path to the `claude` executable (if not in system PATH).

### Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Feature List  │ -> │  Gemini Planning │ -> │ Implementation  │
│ (features.txt)  │    │   (OpenRouter)   │    │     Guide (.md) │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                                        │
                                                        v
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Git Commit    │ <- │  Claude Code     │ <- │   Code Writing  │
│                 │    │  Implementation  │    │   & Testing     │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

### Notes and Best Practices

- **Virtual Environments**: Highly recommended to run this tool within a Python virtual environment specific to your project.
- **Autonomous Operation**: Uses `claude --dangerously-skip-permissions` for fully autonomous operation. Use with caution.
- **Error Handling**: Includes error handling and logging. Failures in `claude-code` might require manual inspection of its output.
- **Cost Awareness**: Be mindful of API costs for OpenRouter usage.
- **Idempotency**: Not designed to be idempotent - manage your git history accordingly when re-running.
- **Testing**: The agent rules (`CLAUDE_AGENT_RULES.md`) emphasize writing tests and verifying functionality before committing.

### Troubleshooting

Common issues and solutions:

1.  **`ModuleNotFoundError`**: Ensure you've installed dependencies with `pip install -r auto_feature_tool/requirements.txt` in your active Python environment.
2.  **`claude` command not found**: Ensure `claude-code` is installed globally (`npm install -g @anthropic-ai/claude-code`) and its installation directory is in your system's PATH. Or, specify the full path in `config.yaml` under `claude_code.cli_path`.
3.  **API Key errors**: Verify your OpenRouter API key is correctly set in `config.yaml`. Check for network issues or OpenRouter service status.
4.  **Missing context files**: Ensure all required input files (project context, repo contents, features list) exist at the configured paths before running. The script will display resolved paths on startup.
5.  **Permission Denied (Python script)**: Ensure `auto_feature_tool/auto_feature.py` has execute permissions if you try to run it directly like `./auto_feature_tool/auto_feature.py` (though `python auto_feature_tool/auto_feature.py` doesn't require it).

---

*"Let us contemplate the elegant simplicity of automation, where each tool serves its purpose in perfect harmony."* - The Zen Master 🧘
```