# feature_symphony_tool/src/orchestrator.py
import xml.etree.ElementTree as ET
import json
import os
import click
from pathlib import Path
import sys

# Ensure src directory is in Python path to import utils
SCRIPT_DIR_ORCH = Path(__file__).resolve().parent
sys.path.append(str(SCRIPT_DIR_ORCH.parent))

from src.utils import load_config, get_gemini_api_key, call_gemini_api, generate_slug, ConfigError

DEFAULT_AIDER_PROMPT = "Please implement this guide."

def parse_symphony_xml(xml_filepath: Path) -> list[dict]:
    """Parses the feature symphony XML file and extracts feature details."""
    try:
        print(f"Parsing symphony XML file: {xml_filepath}")
        tree = ET.parse(xml_filepath)
        root = tree.getroot()
        
        if root.tag != "feature_symphony":
            raise ValueError("Root XML tag must be <feature_symphony>")
            
        # The content inside <feature_symphony> is expected to be a JSON string
        json_string = root.text.strip()
        if not json_string:
            raise ValueError("No JSON content found within <feature_symphony> tags.")
            
        features = json.loads(json_string)
        if not isinstance(features, list):
            raise ValueError("Parsed JSON content is not a list.")
        
        # Validate feature structure
        for i, feature in enumerate(features):
            if not isinstance(feature, dict) or "name" not in feature or "description" not in feature:
                raise ValueError(f"Invalid feature structure at index {i}. Each feature must be a dict with 'name' and 'description'. Found: {feature}")
        
        print(f"Successfully parsed {len(features)} features from XML.")
        return features
    except FileNotFoundError:
        print(f"Error: Symphony XML file not found at {xml_filepath}")
        raise
    except ET.ParseError as e:
        print(f"Error parsing XML file {xml_filepath}: {e}")
        raise
    except json.JSONDecodeError as e:
        print(f"Error parsing JSON content within XML {xml_filepath}: {e}")
        raise
    except ValueError as e:
        print(f"Error validating XML content {xml_filepath}: {e}")
        raise


def generate_feature_slice_guide(
    feature_info: dict, 
    gemini_api_key: str, 
    gemini_model: str,
    project_root: Path,
    repo_context_file: Path = None # Optional repo_contents.txt
) -> str:
    """Generates a detailed implementation guide for a single feature slice using Gemini."""
    feature_name = feature_info["name"]
    feature_description = feature_info["description"]
    
    print(f"Generating feature slice guide for: '{feature_name}'...")
    
    context_text = ""
    if repo_context_file and repo_context_file.exists():
        print(f"Including repository context from: {repo_context_file}")
        context_text = f"\n\n--- Repository Context ---\n{repo_context_file.read_text()}\n--- End Repository Context ---"
    elif repo_context_file:
        print(f"Warning: Specified repository context file not found: {repo_context_file}")

    prompt = f"""
You are an expert software architect and senior developer. Your task is to generate a detailed, step-by-step implementation guide for the following software feature. This guide will be used by an AI coding assistant (Aider) to implement the feature.

Feature Name: {feature_name}
Feature Description: {feature_description}

Please provide a comprehensive guide that includes:
1.  **Objective**: A clear statement of what this feature slice aims to achieve.
2.  **Key Files to Create/Modify**: List specific file paths (relative to the project root: "{project_root}") that will likely be involved. If new files are needed, suggest their names and locations.
3.  **Detailed Implementation Steps**: Break down the implementation into small, actionable steps. For each step, describe what needs to be done. Be specific. If there's code to be written, provide examples or clear instructions.
4.  **Data Structures/Schemas (if applicable)**: Define any new data models, Pydantic schemas, database table structures, or important type definitions.
5.  **API Endpoints (if applicable)**: Specify routes, HTTP methods, request/response bodies for any APIs.
6.  **Important Considerations/Edge Cases**: Highlight any potential challenges, dependencies, or edge cases the AI assistant should be aware of.
7.  **Testing Suggestions**: Briefly outline what kind of tests (unit, integration) would be appropriate for this feature slice and what they should cover.

The AI assistant (Aider) will be operating within the project root: "{project_root}".
Ensure all file paths mentioned are relative to this root.
The output should be a clear, well-structured markdown document.
{context_text}

Begin the guide now:
"""
    
    try:
        guide_content = call_gemini_api(prompt, gemini_api_key, gemini_model)
        return guide_content
    except Exception as e:
        print(f"Failed to generate guide for '{feature_name}': {e}")
        # Return a placeholder or re-raise if critical
        return f"# FAILED GUIDE: {feature_name}\n\nError during generation: {e}"


def save_guide(guide_content: str, output_dir: Path, feature_name: str) -> Path:
    """Saves the generated guide to a file."""
    guide_slug = generate_slug(feature_name)
    guide_filename = f"feature_slice_guide_{guide_slug}.md"
    output_filepath = output_dir / guide_filename
    
    output_dir.mkdir(parents=True, exist_ok=True)
    
    with open(output_filepath, 'w', encoding='utf-8') as f:
        f.write(guide_content)
    print(f"Saved guide to: {output_filepath}")
    return output_filepath


def prepare_aider_tasks_json(
    tasks: list, 
    tmux_session_prefix: str, 
    run_id: str
) -> dict:
    """Prepares the JSON structure for launch_aiders.sh."""
    return {
        "tmux_session_name": f"{tmux_session_prefix}_{run_id}",
        "tasks": tasks
    }

@click.command()
@click.option('--config-file', required=True, type=click.Path(exists=True, dir_okay=False, path_type=Path), help="Path to the config.yaml file.")
@click.option('--run-id', required=True, type=str, help="Unique ID for this run.")
@click.option('--output-json-file', required=True, type=click.Path(dir_okay=False, writable=True, path_type=Path), help="Path to save the output Aider tasks JSON file.")
@click.option('--project-root', required=True, type=click.Path(exists=True, file_okay=False, path_type=Path), help="Absolute path to the root of the target project where Aider will run.")
@click.option('--symphony-xml', type=click.Path(exists=True, dir_okay=False, path_type=Path), help="Path to the symphony XML file (for full workflow).")
@click.option('--single-guide', type=click.Path(exists=True, dir_okay=False, path_type=Path), help="Path to a pre-existing single feature slice guide (for single task workflow).")
@click.option('--repo-context-file', type=click.Path(exists=False, dir_okay=False, path_type=Path), default=None, help="Optional path to a repo_contents.txt file for additional context during guide generation. Relative to project_root.")

def main(
    config_file: Path, 
    run_id: str, 
    output_json_file: Path,
    project_root: Path,
    symphony_xml: Path, 
    single_guide: Path,
    repo_context_file: Path
    ):
    """
    Orchestrates feature slice guide generation and prepares Aider tasks.
    Run from the main project's root directory.
    The `config_file` path should be absolute or relative to feature_symphony_tool dir.
    The `guides_output_directory` in config.yaml is relative to `project_root`.
    """
    try:
        print(f"--- Feature Symphony Orchestrator ---")
        print(f"Run ID: {run_id}")
        print(f"Config File: {config_file}")
        print(f"Project Root: {project_root}")
        
        config = load_config(config_file)
        gemini_api_key = get_gemini_api_key(config)
        gemini_model = config.get('gemini_model_guide_generation', 'gemini-1.5-pro-latest')
        
        # Output directory for guides, relative to the project_root
        guides_output_dir_rel = config.get('guides_output_directory', 'docs/feature_guides')
        guides_output_dir_abs = project_root / guides_output_dir_rel
        guides_output_dir_abs.mkdir(parents=True, exist_ok=True)
        print(f"Generated guides will be saved to: {guides_output_dir_abs}")

        # Global context files for Aider, relative to project_root
        aider_global_context_files_rel = config.get('aider_global_context_files', [])
        aider_global_context_files_abs = [str(project_root / f) for f in aider_global_context_files_rel]
        
        # Resolve repo_context_file path if provided
        actual_repo_context_file = None
        if repo_context_file:
            actual_repo_context_file = project_root / repo_context_file
            if not actual_repo_context_file.exists():
                print(f"Warning: repo-context-file '{actual_repo_context_file}' not found. Proceeding without it.")
                actual_repo_context_file = None


        aider_tasks = []

        if symphony_xml:
            print(f"Processing symphony XML: {symphony_xml}")
            features = parse_symphony_xml(symphony_xml)
            for feature_info in features:
                guide_content = generate_feature_slice_guide(
                    feature_info, 
                    gemini_api_key, 
                    gemini_model,
                    project_root,
                    actual_repo_context_file
                )
                saved_guide_path_abs = save_guide(guide_content, guides_output_dir_abs, feature_info['name'])
                # Store path relative to project_root for Aider, as Aider runs from there
                saved_guide_path_rel = saved_guide_path_abs.relative_to(project_root)
                
                aider_tasks.append({
                    "guide_file": str(saved_guide_path_rel), # Path relative to project_root
                    "global_files": aider_global_context_files_rel, # Paths relative to project_root
                    "prompt": DEFAULT_AIDER_PROMPT,
                    "description": f"Implement feature: {feature_info['name']}"
                })
        elif single_guide:
            print(f"Processing single pre-existing guide: {single_guide}")
            # Ensure single_guide is relative to project_root for consistency in tasks.json
            single_guide_rel = single_guide.relative_to(project_root) if single_guide.is_absolute() else single_guide
            
            aider_tasks.append({
                "guide_file": str(single_guide_rel), # Path relative to project_root
                "global_files": aider_global_context_files_rel, # Paths relative to project_root
                "prompt": DEFAULT_AIDER_PROMPT,
                "description": f"Implement guide: {single_guide.name}"
            })
        else:
            raise click.UsageError("Either --symphony-xml or --single-guide must be provided.")

        tmux_session_prefix = config.get('tmux_session_prefix', 'symphony_aider')
        output_data = prepare_aider_tasks_json(aider_tasks, tmux_session_prefix, run_id)
        
        # Ensure output JSON directory exists
        output_json_file.parent.mkdir(parents=True, exist_ok=True)
        with open(output_json_file, 'w') as f:
            json.dump(output_data, f, indent=2)
        
        print(f"Aider tasks JSON saved to: {output_json_file}")
        print("--- Orchestrator Finished Successfully ---")

    except ConfigError as e:
        print(f"Configuration Error: {e}", file=sys.stderr)
        sys.exit(1)
    except FileNotFoundError as e:
        print(f"File Not Found Error: {e}", file=sys.stderr)
        sys.exit(1)
    except ET.ParseError as e: # XML parsing error
        print(f"XML Parsing Error: {e}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e: # JSON parsing error
        print(f"JSON Parsing Error: {e}", file=sys.stderr)
        sys.exit(1)
    except ValueError as e: # Other value errors (e.g. from XML/JSON content validation)
        print(f"Value Error: {e}", file=sys.stderr)
        sys.exit(1)
    except click.UsageError as e:
        print(f"Usage Error: {e}", file=sys.stderr)
        sys.exit(2) # click's standard exit code for usage errors
    except Exception as e:
        print(f"An unexpected error occurred: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main() 