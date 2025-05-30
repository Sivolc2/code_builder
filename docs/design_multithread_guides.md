Okay, I'll add a multi-threading option to the `orchestrator.py` script for generating feature slice guides in parallel. This will be controlled by a new `--threads` command-line argument.

Here are the changes:

**1. Modified `feature_symphony_tool/src/orchestrator.py`**

I've added the `--threads` option and integrated `concurrent.futures.ThreadPoolExecutor` for parallel guide generation when `threads > 1` and processing a symphony XML.

```python
# feature_symphony_tool/src/orchestrator.py
import xml.etree.ElementTree as ET
import json
import os
import click
import sys
import requests # Added for OpenRouter API calls
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed # Added for threading

# Ensure src directory is in Python path to import utils
SCRIPT_DIR_ORCH = Path(__file__).resolve().parent
TOOL_ROOT_DIR = SCRIPT_DIR_ORCH.parent # This is the expected root of the tool directory
sys.path.insert(0, str(TOOL_ROOT_DIR)) # Add tool root to path

from src.utils import load_config, get_openrouter_api_key, call_openrouter_api, generate_slug, ConfigError

DEFAULT_AIDER_PROMPT = "Please implement this guide."

def parse_symphony_xml(xml_filepath: Path) -> list[dict]:
    """Parses the feature symphony XML file and extracts feature details."""
    try:
        print(f"Parsing symphony XML file: {xml_filepath}")
        tree = ET.parse(xml_filepath)
        root = tree.getroot()
        
        if root.tag != "feature_symphony":
            raise ValueError(f"Invalid XML format. Root element should be 'feature_symphony', got '{root.tag}'")
        
        # The content is expected to be a JSON array inside the XML
        json_content = root.text.strip() if root.text else "[]"
        
        # Parse the JSON array
        features = json.loads(json_content)
        
        if not isinstance(features, list):
            raise ValueError("Feature symphony content must be a JSON array of feature objects")
        
        # Validate each feature object
        for i, feature in enumerate(features):
            if not isinstance(feature, dict):
                raise ValueError(f"Feature at index {i} is not a valid JSON object")
            if "name" not in feature:
                raise ValueError(f"Feature at index {i} is missing 'name' property")
            if "description" not in feature:
                raise ValueError(f"Feature at index {i} is missing 'description' property")
        
        return features
    except ET.ParseError as e:
        print(f"Error parsing XML: {e}")
        raise
    except json.JSONDecodeError as e:
        print(f"Error parsing JSON content within XML: {e}")
        raise
    except Exception as e:
        print(f"Unexpected error parsing symphony XML: {e}")
        raise


def generate_feature_slice_guide(
    feature_info: dict,
    openrouter_api_key: str,
    openrouter_model: str,
    project_root: Path,
    repo_context_file: Path = None, # Optional repo_contents.txt
    tool_root: Path = None # Optional path to the tool's root dir
) -> str:
    """Generates a detailed implementation guide for a single feature slice using OpenRouter."""
    feature_name = feature_info["name"]
    feature_description = feature_info["description"]
    
    print(f"Generating guide for feature slice: {feature_name}")
    
    # Include repository context if available
    context_text = ""
    if repo_context_file and repo_context_file.exists():
        print(f"Including repository context from: {repo_context_file}")
        context_text = f"\n\n--- Repository Context ---\n{repo_context_file.read_text()}\n--- End Repository Context ---"
    elif repo_context_file:
        print(f"Warning: Specified repository context file not found: {repo_context_file} (Absolute: {project_root / repo_context_file})")

    prompt = f"""
You are an expert software architect and senior developer. Your task is to generate a detailed, step-by-step implementation guide for the following software feature. This guide will be used by an AI coding assistant (Aider) to implement the feature.

Feature Name: {feature_name}
Feature Description: {feature_description}

Your guide should include:
1. A brief overview of the feature and its purpose
2. Any necessary background information or context
3. A detailed, step-by-step implementation plan with specific code changes required
4. Any design patterns, algorithms, or data structures that should be utilized
5. Potential edge cases or challenges to consider
6. Testing approach and key test scenarios

Make your guide as specific and actionable as possible. Assume the AI coding assistant has access to the codebase and can read files, but it needs detailed guidance on WHAT to implement and HOW to implement it.

The guide should be comprehensive and self-contained so the AI can implement the feature with minimal additional input.
{context_text}

Begin the guide now:
"""
    
    try:
        guide_content = call_openrouter_api(prompt, openrouter_api_key, openrouter_model)
        return guide_content
    except Exception as e:
        print(f"Failed to generate guide for '{feature_name}': {e}")
        # Return a placeholder or re-raise if critical, current behavior is to re-raise
        # For threaded execution, better to return a failed marker or specific exception
        return f"# FAILED GUIDE: {feature_name}\n\nError during generation: {e}"


def save_guide(guide_content: str, output_dir: Path, feature_name: str) -> Path:
    """Saves the generated guide to a file in the specified directory."""
    slug = generate_slug(feature_name)
    output_filename = f"feature_slice_guide_{slug}.md"
    output_path = output_dir / output_filename
    
    # Create directory if it doesn't exist
    output_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"Saving guide to {output_path}")
    with open(output_path, 'w') as f:
        f.write(guide_content)
    
    return output_path

def prepare_aider_tasks_json(
    tasks: list, 
    zellij_session_prefix: str,
    run_id: str,
    aider_model: str # Added aider_model
) -> dict:
    """Prepares the JSON structure for launch_aiders_zellij.sh."""
    # Add aider_model to each task if not already present
    updated_tasks = []
    for task in tasks:
        if "aider_model" not in task:
            task["aider_model"] = aider_model
        updated_tasks.append(task)

    return {
        "zellij_session_prefix": zellij_session_prefix,
        "run_id": run_id,
        "tasks": updated_tasks
    }

@click.command()
@click.option('--config-file', required=True, type=click.Path(exists=True, dir_okay=False, path_type=Path), help="Path to config.yaml")
@click.option('--run-id', required=True, type=str, help="Unique ID for this run.")
@click.option('--output-json-file', required=True, type=click.Path(dir_okay=False, writable=True, path_type=Path), help="Path to save the output Aider tasks JSON file.")
@click.option('--project-root', required=True, type=click.Path(exists=True, file_okay=False, path_type=Path), help="Absolute path to the root of the target project where Aider will run.")
@click.option('--tool-root', required=True, type=click.Path(exists=True, file_okay=False, path_type=Path), help="Absolute path to the root of the feature_symphony_tool directory.")
@click.option('--symphony-xml', type=click.Path(exists=True, dir_okay=False, path_type=Path), help="Path to the symphony XML file (for full workflow).")
@click.option('--single-guide', type=click.Path(exists=True, dir_okay=False, path_type=Path), help="Path to a pre-existing single feature slice guide (for single task workflow).")
@click.option('--repo-context-file', type=click.Path(exists=False, dir_okay=False, path_type=Path), default=None, help="Optional path to a repo_contents.txt file for additional context during guide generation. Relative to project_root.")
@click.option('--threads', type=int, default=1, help="Number of threads for parallel guide generation.", show_default=True)
def main(
    config_file: Path, 
    run_id: str, 
    output_json_file: Path,
    project_root: Path,
    tool_root: Path,
    symphony_xml: Path, 
    single_guide: Path,
    repo_context_file: Path,
    threads: int
):
    """Feature Symphony Orchestrator - Processes feature symphony XML and generates implementation guides."""
    try:
        print(f"Feature Symphony Orchestrator")
        print(f"Run ID: {run_id}")
        print(f"Orchestration mode: {'Full Symphony' if symphony_xml else 'Single Guide'}")
        print(f"Project Root: {project_root}")
        
        config = load_config(config_file)
        # Get OpenRouter API key from environment only
        openrouter_api_key = os.environ.get('OPENROUTER_API_KEY')
        if not openrouter_api_key:
            raise ConfigError("OPENROUTER_API_KEY environment variable not set.")
            
        openrouter_model_guide = config.get('openrouter_model_guide_generation', 'google/gemini-1.5-pro-latest')
        aider_model_config = config.get('aider_model', 'default/aider-model') # Get aider_model for tasks
        
        # Output directory for guides, relative to the project_root
        guides_output_dir_rel = config.get('guides_output_directory', 'docs/feature_guides')
        guides_output_dir_abs = project_root / guides_output_dir_rel
        print(f"Guides output directory: {guides_output_dir_abs}")
        
        # Zellij session prefix for Aider runs
        zellij_session_prefix = config.get('zellij_session_prefix', 'symphony_aider')
        
        # Global context files for Aider, relative to project_root
        aider_global_context_files_rel = config.get('aider_global_context_files', [])
        # aider_global_context_files_abs = [str(project_root / f) for f in aider_global_context_files_rel] # Not used directly here

        # Resolve repo_context_file path if provided
        actual_repo_context_file = None
        if repo_context_file:
            actual_repo_context_file = project_root / repo_context_file
            print(f"Repository context file: {actual_repo_context_file}")
        
        # List to collect Aider task definitions
        aider_tasks = []
        
        # Process according to mode
        if symphony_xml:
            if threads <= 0:
                threads = 1
            print(f"Processing symphony XML: {symphony_xml} with {threads} thread(s)")
            features = parse_symphony_xml(symphony_xml)
            
            generated_guides_data = [] # To store (feature_info, guide_content)

            if threads > 1 and len(features) > 0:
                with ThreadPoolExecutor(max_workers=threads) as executor:
                    future_to_feature = {
                        executor.submit(
                            generate_feature_slice_guide,
                            feature_info,
                            openrouter_api_key,
                            openrouter_model_guide,
                            project_root,
                            actual_repo_context_file
                            # tool_root is an optional param in generate_feature_slice_guide, not passed here
                        ): feature_info for feature_info in features
                    }
                    for i, future in enumerate(as_completed(future_to_feature)):
                        feature_info = future_to_feature[future]
                        print(f"Processing feature {i+1}/{len(features)}: {feature_info['name']} (from thread)")
                        try:
                            guide_content = future.result()
                            generated_guides_data.append((feature_info, guide_content))
                        except Exception as exc:
                            error_message = f"Error generating guide for '{feature_info['name']}': {exc}"
                            print(error_message, file=sys.stderr)
                            generated_guides_data.append((feature_info, f"# FAILED GUIDE: {feature_info['name']}\n\n{error_message}"))
            else: # Sequential processing (threads == 1 or no features)
                for i, feature_info in enumerate(features):
                    print(f"Processing feature {i+1}/{len(features)}: {feature_info['name']} (sequentially)")
                    try:
                        guide_content = generate_feature_slice_guide(
                            feature_info,
                            openrouter_api_key,
                            openrouter_model_guide,
                            project_root,
                            actual_repo_context_file
                        )
                        generated_guides_data.append((feature_info, guide_content))
                    except Exception as exc:
                        error_message = f"Error generating guide for '{feature_info['name']}': {exc}"
                        print(error_message, file=sys.stderr)
                        generated_guides_data.append((feature_info, f"# FAILED GUIDE: {feature_info['name']}\n\n{error_message}"))
            
            # Now save guides and prepare Aider tasks sequentially
            for feature_info, guide_content in generated_guides_data:
                saved_guide_path_abs = save_guide(guide_content, guides_output_dir_abs, feature_info['name'])
                # Convert to path relative to project_root
                saved_guide_path_rel = saved_guide_path_abs.relative_to(project_root)
                
                aider_tasks.append({
                    "guide_file": str(saved_guide_path_rel), 
                    "global_files": aider_global_context_files_rel, 
                    "prompt": DEFAULT_AIDER_PROMPT,
                    "description": f"Implement feature: {feature_info['name']}",
                    "aider_model": aider_model_config # Ensure this is added
                })

        elif single_guide:
            print(f"Processing single pre-existing guide: {single_guide}")
            single_guide_rel = single_guide.relative_to(project_root) if single_guide.is_absolute() else single_guide
            
            aider_tasks.append({
                "guide_file": str(single_guide_rel), 
                "global_files": aider_global_context_files_rel, 
                "prompt": DEFAULT_AIDER_PROMPT,
                "description": f"Implement guide: {single_guide.name}",
                "aider_model": aider_model_config # Ensure this is added
            })
        else:
            raise click.UsageError("Either --symphony-xml or --single-guide must be provided.")
        
        # Prepare the final output JSON
        output_json_data = prepare_aider_tasks_json(
            aider_tasks,
            zellij_session_prefix,
            run_id,
            aider_model_config # Pass aider_model_config here
        )
        
        # Create output directory if it doesn't exist
        output_json_file.parent.mkdir(parents=True, exist_ok=True)
        
        # Write JSON to output file
        with open(output_json_file, 'w') as f:
            json.dump(output_json_data, f, indent=2)
        
        print(f"\n✨ Orchestration complete!")
        print(f"Generated {len(aider_tasks)} Aider task(s)")
        print(f"Aider tasks JSON saved to: {output_json_file}")
        
        if symphony_xml:
            print(f"Feature slice guides saved to: {guides_output_dir_abs}")
        
        # Return success
        return 0
        
    except ConfigError as e:
        print(f"Configuration error: {e}", file=sys.stderr)
        sys.exit(1)
    except click.UsageError as e:
        print(f"Usage error: {e}", file=sys.stderr)
        sys.exit(1) # click usually exits with 2 for usage error, but 1 is fine for general script failure
    except Exception as e:
        print(f"An unexpected error occurred in orchestrator: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()
```

**2. Updated `feature_symphony_tool/README.md`**

Added a note about the `--threads` option.

```diff
--- a/feature_symphony_tool/README.md
+++ b/feature_symphony_tool/README.md
@@ -107,6 +107,11 @@
     path/to/feature_symphony_tool/run_symphony.sh path/to/your/my_feature_breakdown.xml
     ```
 
+    **Multi-threading for Guide Generation**:
+    The `orchestrator.py` script supports a `--threads N` option to generate feature slice guides in parallel.
+    To use this, you can modify the `run_symphony.sh` script directly. For example, change the line:
+    `python3 "$PYTHON_SCRIPT_PATH" \`
+    to include the threads option:
+    `python3 "$PYTHON_SCRIPT_PATH" --threads 4 \` (to use 4 threads)
+    The default is 1 thread (sequential processing). This option is only relevant when processing a full symphony XML.
+
 3.  **Monitor Aider Tasks (macOS)**:
     *   This tool will open a **new Terminal window for each Aider task** when running on macOS.
     *   Each Terminal window will contain its own dedicated Zellij session running one Aider instance.

```

**Explanation of Changes in `orchestrator.py`:**

1.  **Import `ThreadPoolExecutor`**: Added `from concurrent.futures import ThreadPoolExecutor, as_completed`.
2.  **`--threads` CLI Option**: A new Click option `--threads` is added to the `main` function, defaulting to 1.
3.  **Parallel Execution Logic**:
    *   Inside the `if symphony_xml:` block, if `threads > 1` and there are features to process, it uses a `ThreadPoolExecutor`.
    *   `executor.submit()` is used to queue up `generate_feature_slice_guide` calls for each feature.
    *   `as_completed()` is used to process results as they finish.
    *   Error handling is included for futures: if a guide generation fails, an error message is printed, and a placeholder "FAILED GUIDE" content is stored.
4.  **Sequential Fallback**: If `threads == 1` (or invalid value <=0) or there are no features, it falls back to the existing sequential loop.
5.  **Result Collection and Saving**: All generated guide content (or failure placeholders) along with their corresponding `feature_info` are collected in `generated_guides_data`. After all threads (or sequential tasks) complete, this list is iterated to save the guides and prepare the Aider task definitions. This ensures file saving is done sequentially.
6.  **`aider_model` in JSON**: Ensured `aider_model_config` is correctly passed to `prepare_aider_tasks_json` and included in each task within the output JSON.
7.  **Error Handling**: Improved error message for missing `OPENROUTER_API_KEY`. The `generate_feature_slice_guide` function now returns a failure marker string instead of re-raising immediately, which is better for threaded execution where you want to collect all results. The main loop that processes futures now handles exceptions from `future.result()`.

This setup allows for significantly faster guide generation when dealing with multiple features in a symphony XML by leveraging multiple threads for the API calls. The rest of the workflow (saving guides, creating JSON, launching Aider tasks) remains sequential after the parallel generation phase.