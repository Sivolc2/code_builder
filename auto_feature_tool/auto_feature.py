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