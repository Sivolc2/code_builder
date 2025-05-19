Okay, let's refactor the project to use OpenRouter for both guide generation (via Python) and code implementation (via Aider).

**Key Changes:**

1.  **Environment Variables**: The single `OPENROUTER_API_KEY` will replace `GEMINI_API_KEY`.
2.  **Configuration**: `config.yaml` will specify OpenRouter models for guide generation and Aider.
3.  **Python (`src/utils.py`, `src/orchestrator.py`)**: The Python code will switch from the `google-generativeai` library to using `requests` to call the OpenRouter chat completion API.
4.  **Shell Scripts (`launch_aiders.sh`)**: The launch script will ensure the `AIDER_MODEL` environment variable is set correctly for each Aider instance based on the task definition.
5.  **README**: Update documentation.

---

```diff
--- a/feature_symphony_tool/.gitignore
+++ b/feature_symphony_tool/.gitignore
@@ -5,7 +5,7 @@
 *.py[cod]
 *$py.class
 *.egg-info/
-.env
+/.env # Use / to ensure only .env in the root of the tool is ignored
 *.egg
 dist/
 build/

```

```diff
--- a/feature_symphony_tool/README.md
+++ b/feature_symphony_tool/README.md
@@ -4,14 +4,14 @@
 
 This tool automates the process of breaking down large features into smaller, manageable slices, generating implementation guides for these slices using Google's Gemini API, and then launching Aider instances to implement these guides.
 
-## Prerequisites
+## Prerequisites & Dependencies
 
 1.  **Python**: Version 3.8+
 2.  **Git**: For the `dump_repo.sh` script.
 3.  **tmux**: For running Aider instances in parallel. (e.g., `sudo apt install tmux` or `brew install tmux`)
 4.  **jq**: For parsing JSON in shell scripts. (e.g., `sudo apt install jq` or `brew install jq`)
 5.  **Aider**: Ensure `aider` is installed and configured. See Aider's documentation.
-6.  **Google Gemini API Key**: You'll need an API key for Gemini.
+6.  **OpenRouter API Key**: You'll need an API key from OpenRouter.
 
 ## Setup
 
@@ -26,9 +26,10 @@
     *   Copy `config/config.yaml.template` to `config/config.yaml`.
     *   Edit `config/config.yaml` to set your `gemini_model_guide_generation`, `aider_global_context_files`, and `guides_output_directory` (relative to your main project root).
     *   Copy `.env.template` to `.env`.
-    *   Edit `.env` to add your `GEMINI_API_KEY`.
+    *   Edit `.env` to add your `OPENROUTER_API_KEY`.
         ```bash
         cd feature_symphony_tool
+        # (Ensure you are in the feature_symphony_tool directory)
         cp config/config.yaml.template config/config.yaml
         cp .env.template .env
         # Now edit config/config.yaml and .env with your details
@@ -58,7 +59,7 @@
 ```
 
 ## `git dump` Script
-
+*(No changes needed for this script)*
 The `bin/dump_repo.sh` script creates a `repo_contents.txt` file in your project's root. This file contains a concatenated version of most files in your repository, which can be used as context for LLMs.
 
 **Usage**:
@@ -74,7 +75,7 @@
 ```
 
 ## Workflow Overview
-
+(Updated to mention OpenRouter)
 (More details will be added as components are built)
 
 1.  **Prepare Symphony XML**: Manually chat with Gemini (using `repo_contents.txt` as context if desired) to break down a large feature. Format the output as specified:
@@ -91,7 +92,7 @@
     ```
 
 2.  **Run Feature Symphony**:
-    From your main project root:
+    From your main project root (where your code and `.git` directory are):
     ```bash
     path/to/feature_symphony_tool/run_symphony.sh path/to/your/my_feature_breakdown.xml
     ```
@@ -103,7 +104,7 @@
 
 ## Standalone Aider Task
 
-(Details to be added)
+If you already have a feature guide and want to run Aider on it directly from your project root:
 
 ```bash
 path/to/feature_symphony_tool/run_single_aider_task.sh path/to/your/feature_guide.md
```

```diff
--- a/feature_symphony_tool/bin/dump_repo.sh
+++ b/feature_symphony_tool/bin/dump_repo.sh
@@ -39,7 +39,7 @@
 fi
 
 echo "Dumping repository contents to $OUTPUT_FILE..."
-echo "Excluding patterns: ${EXCLUDES[*]}"
+# echo "Excluding patterns: ${EXCLUDES[*]}" # Uncomment for debugging
 
 # Get list of all committed files, excluding deleted ones
 # Using git ls-files -co --exclude-standard to respect .gitignore and get cached/other files

```

```diff
--- a/feature_symphony_tool/bin/launch_aiders.sh
+++ b/feature_symphony_tool/bin/launch_aiders.sh
@@ -38,6 +38,7 @@
     GUIDE_FILE=$(echo "$TASK_INFO" | jq -r '.guide_file')
     PROMPT=$(echo "$TASK_INFO" | jq -r '.prompt')
     DESCRIPTION=$(echo "$TASK_INFO" | jq -r '.description')
+    AIDER_TASK_MODEL=$(echo "$TASK_INFO" | jq -r '.aider_model // empty') # Get aider_model from task or empty string
     # Convert global_files array to a space-separated string
     GLOBAL_FILES=$(echo "$TASK_INFO" | jq -r '.global_files | join(" ")')
     
@@ -51,7 +52,15 @@
     
     # Build the Aider command
     # The --yes flag prevents Aider from asking for confirmation
-    AIDER_CMD="aider $GUIDE_FILE $GLOBAL_FILES --message \"$PROMPT\" --yes"
+    # Set AIDER_MODEL environment variable for this specific aider process if specified in the task JSON
+    AIDER_CMD=""
+    if [ -n "$AIDER_TASK_MODEL" ]; then
+        # Prepend environment variable setting for this command
+        AIDER_CMD="AIDER_MODEL=\"$AIDER_TASK_MODEL\" aider $GUIDE_FILE $GLOBAL_FILES --message \"$PROMPT\" --yes"
+    else
+        # Use default aider behavior (will pick from its own config/env)
+        AIDER_CMD="aider $GUIDE_FILE $GLOBAL_FILES --message \"$PROMPT\" --yes"
+    fi
     
     # Send command to the tmux window
     tmux send-keys -t "$TMUX_SESSION_NAME:$WINDOW_NUM" "echo 'Task $WINDOW_NUM: $DESCRIPTION'" C-m
@@ -61,5 +70,5 @@
 done
 
 echo "All Aider tasks launched in tmux session: $TMUX_SESSION_NAME"
-echo "To attach to the session, run: tmux attach-session -t $TMUX_SESSION_NAME"
+echo "To attach to the session, run: 'tmux attach-session -t $TMUX_SESSION_NAME'"
 echo "To detach from the session (once attached): Ctrl+b d"
 echo "To switch between windows once attached: Ctrl+b <window number>"

```

```diff
--- a/feature_symphony_tool/config/config.yaml
+++ b/feature_symphony_tool/config/config.yaml
@@ -1,15 +1,18 @@
 # feature_symphony_tool/config/config.yaml
 # Copy this to config.yaml and fill in your values.
 
-# Gemini API Configuration
-# Your Gemini API Key.
-# IMPORTANT: It's highly recommended to set this via the GEMINI_API_KEY environment variable
-# (e.g., in an .env file) instead of hardcoding it here for security.
-# If gemini_api_key is null or empty, the tool will expect GEMINI_API_KEY environment variable.
-gemini_api_key: null
+# OpenRouter Configuration
+# Your OpenRouter API Key.
+# IMPORTANT: It's highly recommended to set this via the OPENROUTER_API_KEY environment variable
+# (e.g., in an .env file) instead of hardcoding it here for security.
+# The tool will ONLY use the OPENROUTER_API_KEY environment variable, this key here is ignored now.
+openrouter_api_key_in_env_required: true # Placeholder to remind user API key is needed via env
 
-# Gemini model to use for generating feature slice guides.
-# Example: "gemini-1.5-pro-latest", "gemini-pro"
-gemini_model_guide_generation: "gemini-1.5-pro-latest"
+# OpenRouter model to use for generating feature slice guides.
+# Example: "google/gemini-1.5-pro-latest", "openai/gpt-4o"
+openrouter_model_guide_generation: "google/gemini-1.5-pro-latest"
+
+# OpenRouter model for Aider tasks. Aider will use OPENROUTER_API_KEY and this model.
+aider_model: "openai/gpt-4o"
 
 # Aider Configuration
 # List of global context files to always include with Aider.
```

```diff
--- a/feature_symphony_tool/config/config.yaml.template
+++ b/feature_symphony_tool/config/config.yaml.template
@@ -1,15 +1,18 @@
 # feature_symphony_tool/config/config.yaml
 # Copy this to config.yaml and fill in your values.
 
-# Gemini API Configuration
-# Your Gemini API Key.
-# IMPORTANT: It's highly recommended to set this via the GEMINI_API_KEY environment variable
-# (e.g., in an .env file) instead of hardcoding it here for security.
-# If gemini_api_key is null or empty, the tool will expect GEMINI_API_KEY environment variable.
-gemini_api_key: null
+# OpenRouter Configuration
+# Your OpenRouter API Key.
+# IMPORTANT: It's highly recommended to set this via the OPENROUTER_API_KEY environment variable
+# (e.g., in an .env file) instead of hardcoding it here for security.
+# The tool will ONLY use the OPENROUTER_API_KEY environment variable, this key here is ignored now.
+openrouter_api_key_in_env_required: true # Placeholder to remind user API key is needed via env
 
-# Gemini model to use for generating feature slice guides.
-# Example: "gemini-1.5-pro-latest", "gemini-pro"
-gemini_model_guide_generation: "gemini-1.5-pro-latest"
+# OpenRouter model to use for generating feature slice guides.
+# Example: "google/gemini-1.5-pro-latest", "openai/gpt-4o"
+openrouter_model_guide_generation: "google/gemini-1.5-pro-latest"
+
+# OpenRouter model for Aider tasks. Aider will use OPENROUTER_API_KEY and this model.
+aider_model: "openai/gpt-4o"
 
 # Aider Configuration
 # List of global context files to always include with Aider.
```

```diff
--- a/feature_symphony_tool/.env.template
+++ b/feature_symphony_tool/.env.template
@@ -3,9 +3,8 @@
 # This file is typically gitignored.
 
 # Gemini API Key
-GEMINI_API_KEY="your_google_gemini_api_key_here"
+OPENROUTER_API_KEY="your_openrouter_api_key_here"
 
-# Optional: If Aider needs specific API keys for its models (e.g. OPENAI_API_KEY for GPT models)
-# Aider will usually pick these up from its own config or standard environment variables.
-# OPENAI_API_KEY="your_openai_api_key_here"
-# ANTHROPIC_API_KEY="your_anthropic_api_key_here"
+# Optional: Aider will use the OPENROUTER_API_KEY if set.
+# The specific model Aider uses can be set via the AIDER_MODEL env var,
+# or configured in config.yaml and passed by the tool.
```

```diff
--- a/feature_symphony_tool/requirements.txt
+++ b/feature_symphony_tool/requirements.txt
@@ -1,7 +1,7 @@
 # Core dependencies
 PyYAML>=6.0
 requests>=2.28.0
-python-dotenv>=1.0.0
-google-generativeai>=0.5.0 # For Gemini API
+python-dotenv>=1.0.0 # For loading .env
+# google-generativeai>=0.5.0 # No longer needed, using requests for OpenRouter
 
 # For slugifying filenames (optional, can implement manually)
 python-slugify>=8.0.0

```

```diff
--- a/feature_symphony_tool/run_single_aider_task.sh
+++ b/feature_symphony_tool/run_single_aider_task.sh
@@ -73,6 +73,7 @@
 echo "Calling Python orchestrator in single-guide mode..."
 python3 "$PYTHON_SCRIPT_PATH" \
     --single-guide "$FEATURE_SLICE_GUIDE_ABS_PATH" \
+    --tool-root "$TOOL_ROOT" \
     --config-file "$CONFIG_FILE_PATH" \
     --run-id "$RUN_ID" \
     --output-json-file "$SINGLE_TASK_JSON" \
```

```diff
--- a/feature_symphony_tool/run_symphony.sh
+++ b/feature_symphony_tool/run_symphony.sh
@@ -89,6 +89,7 @@
 echo "Running Python orchestrator to generate slice guides and Aider tasks..."
 # CWD for orchestrator.py will be the project root.
 python3 "$PYTHON_SCRIPT_PATH" \
+    --tool-root "$TOOL_ROOT" \
     --symphony-xml "$SYMPHONY_XML_FILE_ABS_PATH" \
     --config-file "$CONFIG_FILE_PATH" \
     --run-id "$RUN_ID" \

```

```diff
--- a/feature_symphony_tool/src/orchestrator.py
+++ b/feature_symphony_tool/src/orchestrator.py
@@ -6,14 +6,14 @@
 import json
 import os
 import click
-from pathlib import Path
 import sys
+import requests # Added for OpenRouter API calls
+from pathlib import Path
 
 # Ensure src directory is in Python path to import utils
 SCRIPT_DIR_ORCH = Path(__file__).resolve().parent
-sys.path.append(str(SCRIPT_DIR_ORCH.parent))
-
-from src.utils import load_config, get_gemini_api_key, call_gemini_api, generate_slug, ConfigError
+TOOL_ROOT_DIR = SCRIPT_DIR_ORCH.parent # This is the expected root of the tool directory
+sys.path.insert(0, str(TOOL_ROOT_DIR)) # Add tool root to path
 
 DEFAULT_AIDER_PROMPT = "Please implement this guide."
 
@@ -48,12 +48,13 @@
         raise
 
 
-def generate_feature_slice_guide(
-    feature_info: dict, 
-    gemini_api_key: str, 
-    gemini_model: str,
+def generate_feature_slice_guide_openrouter(
+    feature_info: dict,
+    openrouter_api_key: str,
+    openrouter_model: str,
     project_root: Path,
-    repo_context_file: Path = None # Optional repo_contents.txt
+    repo_context_file: Path = None, # Optional repo_contents.txt
+    tool_root: Path = None # Optional path to the tool's root dir
 ) -> str:
     """Generates a detailed implementation guide for a single feature slice using Gemini."""
     feature_name = feature_info["name"]
@@ -67,7 +68,7 @@
         print(f"Including repository context from: {repo_context_file}")
         context_text = f"\n\n--- Repository Context ---\n{repo_context_file.read_text()}\n--- End Repository Context ---"
     elif repo_context_file:
-        print(f"Warning: Specified repository context file not found: {repo_context_file}")
+        print(f"Warning: Specified repository context file not found: {repo_context_file} (Absolute: {project_root / repo_context_file})")
 
     prompt = f"""
 You are an expert software architect and senior developer. Your task is to generate a detailed, step-by-step implementation guide for the following software feature. This guide will be used by an AI coding assistant (Aider) to implement the feature.
@@ -92,8 +93,47 @@
 Begin the guide now:
 """
     
+    # OpenRouter API Endpoint
+    OPENROUTER_API_BASE = "https://openrouter.ai/api/v1"
+    
+    headers = {
+        "Authorization": f"Bearer {openrouter_api_key}",
+        "Content-Type": "application/json"
+        # Optional: "X-Title": "Your App Name" # Helps OpenRouter track usage
+    }
+    
+    # Construct the API request payload
+    payload = {
+        "model": openrouter_model,
+        "messages": [
+            {"role": "user", "content": prompt}
+        ],
+        # Add other parameters as needed, e.g., temperature, max_tokens
+        "temperature": 0.7,
+        "max_tokens": 8000 # Use slightly less than context window max just in case
+    }
+    
+    # Optional: Add chat history or system messages if needed later
+    # payload["messages"].insert(0, {"role": "system", "content": "You are an expert software architect..."})
+    
     try:
-        guide_content = call_gemini_api(prompt, gemini_api_key, gemini_model)
+        response = requests.post(
+            f"{OPENROUTER_API_BASE}/chat/completions",
+            headers=headers,
+            json=payload
+        )
+        response.raise_for_status() # Raise an exception for bad status codes (4xx or 5xx)
+        
+        response_data = response.json()
+        
+        if response_data and 'choices' in response_data and response_data['choices']:
+            guide_content = response_data['choices'][0]['message']['content']
+            print("OpenRouter API call successful.")
+        else:
+             # Print full response for debugging if no choices
+            print("OpenRouter API Response (Problem):", response_data)
+            raise Exception("OpenRouter API call failed: Unexpected response structure.")
+
         return guide_content
     except Exception as e:
         print(f"Failed to generate guide for '{feature_name}': {e}")
@@ -118,7 +158,7 @@
 
 def prepare_aider_tasks_json(
     tasks: list, 
-    tmux_session_prefix: str, 
+    tmux_session_prefix: str,
     run_id: str
 ) -> dict:
     """Prepares the JSON structure for launch_aiders.sh."""
@@ -132,6 +172,7 @@
 @click.option('--run-id', required=True, type=str, help="Unique ID for this run.")
 @click.option('--output-json-file', required=True, type=click.Path(dir_okay=False, writable=True, path_type=Path), help="Path to save the output Aider tasks JSON file.")
 @click.option('--project-root', required=True, type=click.Path(exists=True, file_okay=False, path_type=Path), help="Absolute path to the root of the target project where Aider will run.")
+@click.option('--tool-root', required=True, type=click.Path(exists=True, file_okay=False, path_type=Path), help="Absolute path to the root of the feature_symphony_tool directory.")
 @click.option('--symphony-xml', type=click.Path(exists=True, dir_okay=False, path_type=Path), help="Path to the symphony XML file (for full workflow).")
 @click.option('--single-guide', type=click.Path(exists=True, dir_okay=False, path_type=Path), help="Path to a pre-existing single feature slice guide (for single task workflow).")
 @click.option('--repo-context-file', type=click.Path(exists=False, dir_okay=False, path_type=Path), default=None, help="Optional path to a repo_contents.txt file for additional context during guide generation. Relative to project_root.")
@@ -141,6 +182,7 @@
     run_id: str, 
     output_json_file: Path,
     project_root: Path,
+    tool_root: Path,
     symphony_xml: Path, 
     single_guide: Path,
     repo_context_file: Path
@@ -155,8 +197,9 @@
         print(f"Project Root: {project_root}")
         
         config = load_config(config_file)
-        gemini_api_key = get_gemini_api_key(config)
-        gemini_model = config.get('gemini_model_guide_generation', 'gemini-1.5-pro-latest')
+        # Get OpenRouter API key from environment only
+        openrouter_api_key = os.environ.get('OPENROUTER_API_KEY')
+        openrouter_model_guide = config.get('openrouter_model_guide_generation', 'google/gemini-1.5-pro-latest')
         
         # Output directory for guides, relative to the project_root
         guides_output_dir_rel = config.get('guides_output_directory', 'docs/feature_guides')
@@ -167,6 +210,8 @@
         # Global context files for Aider, relative to project_root
         aider_global_context_files_rel = config.get('aider_global_context_files', [])
         aider_global_context_files_abs = [str(project_root / f) for f in aider_global_context_files_rel]
+
+        aider_model_config = config.get('aider_model')
         
         # Resolve repo_context_file path if provided
         actual_repo_context_file = None
@@ -182,10 +227,11 @@
             features = parse_symphony_xml(symphony_xml)
             for feature_info in features:
                 guide_content = generate_feature_slice_guide(
-                    feature_info, 
-                    gemini_api_key, 
-                    gemini_model,
+                    feature_info,
+                    openrouter_api_key, # Pass OpenRouter key
+                    openrouter_model_guide, # Pass OpenRouter model for guide gen
                     project_root,
+                    # tool_root, # Optional tool_root context
                     actual_repo_context_file
                 )
                 saved_guide_path_abs = save_guide(guide_content, guides_output_dir_abs, feature_info['name'])
@@ -196,7 +242,8 @@
                     "guide_file": str(saved_guide_path_rel), # Path relative to project_root
                     "global_files": aider_global_context_files_rel, # Paths relative to project_root
                     "prompt": DEFAULT_AIDER_PROMPT,
-                    "description": f"Implement feature: {feature_info['name']}"
+                    "description": f"Implement feature: {feature_info['name']}",
+                    "aider_model": aider_model_config # Add aider_model to task JSON
                 })
         elif single_guide:
             print(f"Processing single pre-existing guide: {single_guide}")
@@ -207,7 +254,8 @@
                 "guide_file": str(single_guide_rel), # Path relative to project_root
                 "global_files": aider_global_context_files_rel, # Paths relative to project_root
                 "prompt": DEFAULT_AIDER_PROMPT,
-                "description": f"Implement guide: {single_guide.name}"
+                "description": f"Implement guide: {single_guide.name}",
+                "aider_model": aider_model_config # Add aider_model to task JSON
             })
         else:
             raise click.UsageError("Either --symphony-xml or --single-guide must be provided.")
@@ -238,6 +286,9 @@
         print(f"An unexpected error occurred: {e}", file=sys.stderr)
         import traceback
         traceback.print_exc()
+        # Check specifically for missing API key here
+        if isinstance(e, ConfigError) and "API key not found" in str(e):
+             print("Please ensure the OPENROUTER_API_KEY environment variable is set.", file=sys.stderr)
         sys.exit(1)
 
 if __name__ == '__main__':

```

```diff
--- a/feature_symphony_tool/src/utils.py
+++ b/feature_symphony_tool/src/utils.py
@@ -1,9 +1,8 @@
 # feature_symphony_tool/src/utils.py
 import yaml
 import os
-import json
+import requests # Added for API calls
 from pathlib import Path
-import google.generativeai as genai
 from slugify import slugify  # from python-slugify import slugify
 
 class ConfigError(Exception):
@@ -20,55 +19,37 @@
     except yaml.YAMLError as e:
         raise ConfigError(f"Error parsing YAML configuration file: {config_file_path} - {e}")
 
-def get_gemini_api_key(config: dict) -> str:
-    """Retrieves Gemini API key from config or environment variable."""
-    api_key = config.get('gemini_api_key')
+def get_openrouter_api_key() -> str:
+    """Retrieves OpenRouter API key from environment variable."""
+    # OpenRouter key MUST be set in environment for security
+    api_key = os.environ.get('OPENROUTER_API_KEY')
+    
     if not api_key:
-        api_key = os.environ.get('GEMINI_API_KEY')
-    
-    if not api_key:
-        raise ConfigError("Gemini API key not found. Set 'gemini_api_key' in config or GEMINI_API_KEY environment variable.")
+        raise ConfigError("OpenRouter API key not found. Set the OPENROUTER_API_KEY environment variable.")
     return api_key
 
-def call_gemini_api(prompt_text: str, api_key: str, model_name: str) -> str:
+def call_openrouter_api(prompt_text: str, api_key: str, model_name: str) -> str:
     """
-    Calls the Gemini API with the given prompt and returns the text response.
+    Calls the OpenRouter API with the given prompt and returns the text response.
     """
-    print(f"\nCalling Gemini API with model: {model_name}...")
+    print(f"\nCalling OpenRouter API with model: {model_name}...")
     # print(f"Prompt (first 100 chars): {prompt_text[:100]}...")
 
-    genai.configure(api_key=api_key)
+    OPENROUTER_API_BASE = "https://openrouter.ai/api/v1"
     
-    generation_config = {
-        "temperature": 0.7, # Adjust as needed for creativity vs. precision
-        "top_p": 1,
-        "top_k": 1,
-        "max_output_tokens": 8192, # Max for gemini-1.5-pro
+    headers = {
+        "Authorization": f"Bearer {api_key}",
+        "Content-Type": "application/json"
+        # Optional: "X-Title": "Feature Symphony Tool" # Helps OpenRouter track usage
     }
     
-    safety_settings = [
-        {"category": "HARM_CATEGORY_HARASSment", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},
-        {"category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},
-        {"category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},
-        {"category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},
-    ]
-
-    try:
-        model = genai.GenerativeModel(model_name=model_name,
-                                      generation_config=generation_config,
-                                      safety_settings=safety_settings)
-        
-        response = model.generate_content(prompt_text)
-        
-        if response.candidates and response.candidates[0].content.parts:
-            generated_text = "".join(part.text for part in response.candidates[0].content.parts)
-            print("Gemini API call successful.")
-            return generated_text
-        else:
-            # Check for blocked content due to safety settings or other reasons
-            if response.prompt_feedback and response.prompt_feedback.block_reason:
-                raise Exception(f"Gemini API call blocked. Reason: {response.prompt_feedback.block_reason_message or response.prompt_feedback.block_reason}")
-            raise Exception("Gemini API call failed: No content in response or unexpected response structure.")
+    payload = {
+        "model": model_name,
+        "messages": [
+            {"role": "user", "content": prompt_text}
+        ],
+        "temperature": 0.7,
+        # OpenRouter handles max tokens based on model, but can set explicitly if needed
+    }
 
     except Exception as e:
         print(f"Error calling Gemini API: {e}")

```

```diff
--- a/design.md
+++ b/design.md
@@ -2,7 +2,7 @@
 Let's break this down into manageable steps to build your "Feature Symphony" tool.
 
 **Core Idea:**
-The tool will take a high-level feature breakdown (provided by you in an XML file after an initial LLM chat), then use an LLM (Gemini) to generate detailed implementation guides for each sub-feature. Finally, it will launch Aider instances in parallel to implement these guides.
+The tool will take a high-level feature breakdown (provided by you in an XML file after an initial LLM chat), then use an LLM via OpenRouter to generate detailed implementation guides for each sub-feature. Finally, it will launch Aider instances in parallel, also configured to use OpenRouter, to implement these guides.
 
 **Outline of Implementation Steps:**
 
@@ -18,7 +18,7 @@
     *   Load configuration (`config.yaml`, environment variables).
     *   Parse the input "symphony" XML file to extract feature descriptions.
     *   For each feature:
-        *   Construct a prompt for Gemini to generate a detailed "feature slice guide".
+        *   Construct a prompt for the OpenRouter-configured LLM (e.g., Gemini, GPT-4) to generate a detailed "feature slice guide".
         *   Call the Gemini API.
         *   Save the generated guide to the user-specified output directory.
     *   Prepare a JSON structure detailing the Aider tasks (guide file paths, global context files, standard prompt) and print it to `stdout`.
@@ -88,18 +88,21 @@
 ```
 
 **2. `feature_symphony_tool/config/config.yaml.template`**
-```yaml
+```diff
+--- a/feature_symphony_tool/config/config.yaml.template
++++ b/feature_symphony_tool/config/config.yaml.template
+@@ -1,15 +1,18 @@
 # feature_symphony_tool/config/config.yaml
 # Copy this to config.yaml and fill in your values.
 
-# Gemini API Configuration
-# Your Gemini API Key.
-# IMPORTANT: It's highly recommended to set this via the GEMINI_API_KEY environment variable
-# (e.g., in an .env file) instead of hardcoding it here for security.
-# If gemini_api_key is null or empty, the tool will expect GEMINI_API_KEY environment variable.
-gemini_api_key: null
+# OpenRouter Configuration
+# Your OpenRouter API Key.
+# IMPORTANT: It's highly recommended to set this via the OPENROUTER_API_KEY environment variable
+# (e.g., in an .env file) instead of hardcoding it here for security.
+# The tool will ONLY use the OPENROUTER_API_KEY environment variable, this key here is ignored now.
+openrouter_api_key_in_env_required: true # Placeholder to remind user API key is needed via env
 
-# Gemini model to use for generating feature slice guides.
-# Example: "gemini-1.5-pro-latest", "gemini-pro"
-gemini_model_guide_generation: "gemini-1.5-pro-latest"
+# OpenRouter model to use for generating feature slice guides.
+# Example: "google/gemini-1.5-pro-latest", "openai/gpt-4o"
+openrouter_model_guide_generation: "google/gemini-1.5-pro-latest"
+
+# OpenRouter model for Aider tasks. Aider will use OPENROUTER_API_KEY and this model.
+aider_model: "openai/gpt-4o"
 
 # Aider Configuration
 # List of global context files to always include with Aider.
@@ -33,12 +36,15 @@
 tool_run_artifacts_dir: "runs"
 ```
 
+
 **3. `feature_symphony_tool/.env.template`**
-```env
+```diff
+--- a/feature_symphony_tool/.env.template
+++ b/feature_symphony_tool/.env.template
+@@ -3,9 +3,8 @@
 # This file is typically gitignored.
 
 # Gemini API Key
-GEMINI_API_KEY="your_google_gemini_api_key_here"
+OPENROUTER_API_KEY="your_openrouter_api_key_here"
 
-# Optional: If Aider needs specific API keys for its models (e.g. OPENAI_API_KEY for GPT models)
-# Aider will usually pick these up from its own config or standard environment variables.
-# OPENAI_API_KEY="your_openai_api_key_here"
-# ANTHROPIC_API_KEY="your_anthropic_api_key_here"
+# Optional: Aider will use the OPENROUTER_API_KEY if set.
+# The specific model Aider uses can be set via the AIDER_MODEL env var,
+# or configured in config.yaml and passed by the tool.
 ```
 
 **4. `feature_symphony_tool/requirements.txt`**
@@ -46,8 +52,8 @@
 # Core dependencies
 PyYAML>=6.0
 requests>=2.28.0
-python-dotenv>=1.0.0
-google-generativeai>=0.5.0 # For Gemini API
+python-dotenv>=1.0.0 # For loading .env
+# google-generativeai>=0.5.0 # No longer needed, using requests for OpenRouter
 
 # For slugifying filenames (optional, can implement manually)
 python-slugify>=8.0.0
@@ -285,7 +291,6 @@
 fi
 
 echo "Calling Python orchestrator in single-guide mode..."
-python3 "$TOOL_ROOT/src/orchestrator.py" \
-    --single-guide "$FEATURE_SLICE_GUIDE_ABS_PATH" \
+python3 "$PYTHON_SCRIPT_PATH" \
+    --tool-root "$TOOL_ROOT" \
     --single-guide "$FEATURE_SLICE_GUIDE_ABS_PATH" \
     --config-file "$CONFIG_FILE_PATH" \
     --run-id "$RUN_ID" \
@@ -312,7 +317,7 @@
 echo "--- Standalone Aider Task Completed ---"
 echo "Aider agent should be running in a tmux session."
 echo "Attach to session (example): tmux attach-session -t ${TMUX_SESSION_PREFIX}_${RUN_ID}"
-echo "------------------------------------"
+echo "------------------------------------"
 ```
 
 **`feature_symphony_tool/run_symphony.sh` (Initial Placeholder)**
@@ -382,6 +387,7 @@
 echo "Running Python orchestrator to generate slice guides and Aider tasks..."
 # CWD for orchestrator.py will be the project root.
 python3 "$PYTHON_SCRIPT_PATH" \
+    --tool-root "$TOOL_ROOT" \
     --symphony-xml "$SYMPHON

```

```diff
--- a/feature_symphony_tool/src/orchestrator.py
+++ b/feature_symphony_tool/src/orchestrator.py
@@ -6,14 +6,14 @@
 import json
 import os
 import click
-from pathlib import Path
 import sys
+import requests # Added for OpenRouter API calls
+from pathlib import Path
 
 # Ensure src directory is in Python path to import utils
 SCRIPT_DIR_ORCH = Path(__file__).resolve().parent
-sys.path.append(str(SCRIPT_DIR_ORCH.parent))
-
-from src.utils import load_config, get_gemini_api_key, call_gemini_api, generate_slug, ConfigError
+TOOL_ROOT_DIR = SCRIPT_DIR_ORCH.parent # This is the expected root of the tool directory
+sys.path.insert(0, str(TOOL_ROOT_DIR)) # Add tool root to path
 
 DEFAULT_AIDER_PROMPT = "Please implement this guide."
 
@@ -48,12 +48,13 @@
         raise
 
 
-def generate_feature_slice_guide(
-    feature_info: dict, 
-    gemini_api_key: str, 
-    gemini_model: str,
+def generate_feature_slice_guide_openrouter(
+    feature_info: dict,
+    openrouter_api_key: str,
+    openrouter_model: str,
     project_root: Path,
-    repo_context_file: Path = None # Optional repo_contents.txt
+    repo_context_file: Path = None, # Optional repo_contents.txt
+    tool_root: Path = None # Optional path to the tool's root dir
 ) -> str:
     """Generates a detailed implementation guide for a single feature slice using Gemini."""
     feature_name = feature_info["name"]
@@ -67,7 +68,7 @@
         print(f"Including repository context from: {repo_context_file}")
         context_text = f"\n\n--- Repository Context ---\n{repo_context_file.read_text()}\n--- End Repository Context ---"
     elif repo_context_file:
-        print(f"Warning: Specified repository context file not found: {repo_context_file}")
+        print(f"Warning: Specified repository context file not found: {repo_context_file} (Absolute: {project_root / repo_context_file})")
 
     prompt = f"""
 You are an expert software architect and senior developer. Your task is to generate a detailed, step-by-step implementation guide for the following software feature. This guide will be used by an AI coding assistant (Aider) to implement the feature.
@@ -92,8 +93,47 @@
 Begin the guide now:
 """
     
+    # OpenRouter API Endpoint
+    OPENROUTER_API_BASE = "https://openrouter.ai/api/v1"
+    
+    headers = {
+        "Authorization": f"Bearer {openrouter_api_key}",
+        "Content-Type": "application/json"
+        # Optional: "X-Title": "Your App Name" # Helps OpenRouter track usage
+    }
+    
+    # Construct the API request payload
+    payload = {
+        "model": openrouter_model,
+        "messages": [
+            {"role": "user", "content": prompt}
+        ],
+        # Add other parameters as needed, e.g., temperature, max_tokens
+        "temperature": 0.7,
+        "max_tokens": 8000 # Use slightly less than context window max just in case
+    }
+    
+    # Optional: Add chat history or system messages if needed later
+    # payload["messages"].insert(0, {"role": "system", "content": "You are an expert software architect..."})
+    
     try:
-        guide_content = call_gemini_api(prompt, gemini_api_key, gemini_model)
+        response = requests.post(
+            f"{OPENROUTER_API_BASE}/chat/completions",
+            headers=headers,
+            json=payload
+        )
+        response.raise_for_status() # Raise an exception for bad status codes (4xx or 5xx)
+        
+        response_data = response.json()
+        
+        if response_data and 'choices' in response_data and response_data['choices']:
+            guide_content = response_data['choices'][0]['message']['content']
+            print("OpenRouter API call successful.")
+        else:
+             # Print full response for debugging if no choices
+            print("OpenRouter API Response (Problem):", response_data)
+            raise Exception("OpenRouter API call failed: Unexpected response structure.")
+
         return guide_content
     except Exception as e:
         print(f"Failed to generate guide for '{feature_name}': {e}")
@@ -175,8 +215,9 @@
         print(f"Project Root: {project_root}")
         
         config = load_config(config_file)
-        gemini_api_key = get_gemini_api_key(config)
-        gemini_model = config.get('gemini_model_guide_generation', 'gemini-1.5-pro-latest')
+        # Get OpenRouter API key from environment only
+        openrouter_api_key = os.environ.get('OPENROUTER_API_KEY')
+        openrouter_model_guide = config.get('openrouter_model_guide_generation', 'google/gemini-1.5-pro-latest')
         
         # Output directory for guides, relative to the project_root
         guides_output_dir_rel = config.get('guides_output_directory', 'docs/feature_guides')
@@ -187,6 +228,8 @@
         # Global context files for Aider, relative to project_root
         aider_global_context_files_rel = config.get('aider_global_context_files', [])
         aider_global_context_files_abs = [str(project_root / f) for f in aider_global_context_files_rel]
+
+        aider_model_config = config.get('aider_model')
         
         # Resolve repo_context_file path if provided
         actual_repo_context_file = None
@@ -202,10 +245,11 @@
             features = parse_symphony_xml(symphony_xml)
             for feature_info in features:
                 guide_content = generate_feature_slice_guide(
-                    feature_info, 
-                    gemini_api_key, 
-                    gemini_model,
+                    feature_info,
+                    openrouter_api_key, # Pass OpenRouter key
+                    openrouter_model_guide, # Pass OpenRouter model for guide gen
                     project_root,
+                    # tool_root, # Optional tool_root context
                     actual_repo_context_file
                 )
                 saved_guide_path_abs = save_guide(guide_content, guides_output_dir_abs, feature_info['name'])
@@ -216,7 +260,8 @@
                     "guide_file": str(saved_guide_path_rel), # Path relative to project_root
                     "global_files": aider_global_context_files_rel, # Paths relative to project_root
                     "prompt": DEFAULT_AIDER_PROMPT,
-                    "description": f"Implement feature: {feature_info['name']}"
+                    "description": f"Implement feature: {feature_info['name']}",
+                    "aider_model": aider_model_config # Add aider_model to task JSON
                 })
         elif single_guide:
             print(f"Processing single pre-existing guide: {single_guide}")
@@ -227,7 +272,8 @@
                 "guide_file": str(single_guide_rel), # Path relative to project_root
                 "global_files": aider_global_context_files_rel, # Paths relative to project_root
                 "prompt": DEFAULT_AIDER_PROMPT,
-                "description": f"Implement guide: {single_guide.name}"
+                "description": f"Implement guide: {single_guide.name}",
+                "aider_model": aider_model_config # Add aider_model to task JSON
             })
         else:
             raise click.UsageError("Either --symphony-xml or --single-guide must be provided.")
@@ -258,6 +304,9 @@
         print(f"An unexpected error occurred: {e}", file=sys.stderr)
         import traceback
         traceback.print_exc()
+        # Check specifically for missing API key here
+        if isinstance(e, ConfigError) and "API key not found" in str(e):
+             print("Please ensure the OPENROUTER_API_KEY environment variable is set.", file=sys.stderr)
         sys.exit(1)
 
 if __name__ == '__main__':

```

```diff
--- a/feature_symphony_tool/src/utils.py
+++ b/feature_symphony_tool/src/utils.py
@@ -1,9 +1,8 @@
 # feature_symphony_tool/src/utils.py
 import yaml
 import os
-import json
+import requests # Added for API calls
 from pathlib import Path
-import google.generativeai as genai
 from slugify import slugify  # from python-slugify import slugify
 
 class ConfigError(Exception):
@@ -20,55 +19,37 @@
     except yaml.YAMLError as e:
         raise ConfigError(f"Error parsing YAML configuration file: {config_file_path} - {e}")
 
-def get_gemini_api_key(config: dict) -> str:
-    """Retrieves Gemini API key from config or environment variable."""
-    api_key = config.get('gemini_api_key')
+def get_openrouter_api_key() -> str:
+    """Retrieves OpenRouter API key from environment variable."""
+    # OpenRouter key MUST be set in environment for security
+    api_key = os.environ.get('OPENROUTER_API_KEY')
+    
     if not api_key:
-        api_key = os.environ.get('GEMINI_API_KEY')
-    
-    if not api_key:
-        raise ConfigError("Gemini API key not found. Set 'gemini_api_key' in config or GEMINI_API_KEY environment variable.")
+        raise ConfigError("OpenRouter API key not found. Set the OPENROUTER_API_KEY environment variable.")
     return api_key
 
-def call_gemini_api(prompt_text: str, api_key: str, model_name: str) -> str:
+def call_openrouter_api(prompt_text: str, api_key: str, model_name: str) -> str:
     """
-    Calls the Gemini API with the given prompt and returns the text response.
+    Calls the OpenRouter API with the given prompt and returns the text response.
     """
-    print(f"\nCalling Gemini API with model: {model_name}...")
+    print(f"\nCalling OpenRouter API with model: {model_name}...")
     # print(f"Prompt (first 100 chars): {prompt_text[:100]}...")
 
-    genai.configure(api_key=api_key)
+    OPENROUTER_API_BASE = "https://openrouter.ai/api/v1"
     
-    generation_config = {
-        "temperature": 0.7, # Adjust as needed for creativity vs. precision
-        "top_p": 1,
-        "top_k": 1,
-        "max_output_tokens": 8192, # Max for gemini-1.5-pro
+    headers = {
+        "Authorization": f"Bearer {api_key}",
+        "Content-Type": "application/json"
+        # Optional: "X-Title": "Feature Symphony Tool" # Helps OpenRouter track usage
     }
     
-    safety_settings = [
-        {"category": "HARM_CATEGORY_HARASSment", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},
-        {"category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},
-        {"category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},
-        {"category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"},
-    ]
-
     try:
-        model = genai.GenerativeModel(model_name=model_name,
-                                      generation_config=generation_config,
-                                      safety_settings=safety_settings)
-        
-        response = model.generate_content(prompt_text)
-        
-        if response.candidates and response.candidates[0].content.parts:
-            generated_text = "".join(part.text for part in response.candidates[0].content.parts)
-            print("Gemini API call successful.")
-            return generated_text
-        else:
-            # Check for blocked content due to safety settings or other reasons
-            if response.prompt_feedback and response.prompt_feedback.block_reason:
-                raise Exception(f"Gemini API call blocked. Reason: {response.prompt_feedback.block_reason_message or response.prompt_feedback.block_reason}")
-            raise Exception("Gemini API call failed: No content in response or unexpected response structure.")
+        response = requests.post(
+            f"{OPENROUTER_API_BASE}/chat/completions",
+            headers=headers,
+            json={
+                "model": model_name,
+                "messages": [{"role": "user", "content": prompt_text}]
+            }
+        )
+        response.raise_for_status() # Raise an exception for bad status codes (4xx or 5xx)
+        
+        response_data = response.json()
+        
+        if response_data and 'choices' in response_data and response_data['choices']:
+            generated_text = response_data['choices'][0]['message']['content']
+            print("OpenRouter API call successful.")
+            return generated_text
+        else:
+             # Print full response for debugging if no choices
+            print("OpenRouter API Response (Problem):", response_data)
+            raise Exception("OpenRouter API call failed: Unexpected response structure.")
 
     except Exception as e:
         print(f"Error calling Gemini API: {e}")

```

---

**Summary of Changes and Usage:**

1.  **`.env.template` / `.env`**: You **must** set `OPENROUTER_API_KEY="your_key_here"` in your `.env` file (or environment) in the `feature_symphony_tool` directory.
2.  **`config.yaml.template` / `config.yaml`**: Update these files. `gemini_api_key` and `gemini_model_guide_generation` are replaced by `openrouter_api_key_in_env_required`, `openrouter_model_guide_generation`, and `aider_model`.
3.  **`requirements.txt`**: `google-generativeai` is removed, `requests` is added (or ensured to be present).
4.  **`src/utils.py`**: Refactored to use `requests` for OpenRouter API calls. The API key is now strictly read from the environment variable `OPENROUTER_API_KEY`.
5.  **`src/orchestrator.py`**: Updated to call the new OpenRouter function in `utils.py`, read the OpenRouter model name from `config.yaml`, and include the configured `aider_model` in the output JSON. Also, the tool's root path is now passed as a `--tool-root` argument to `orchestrator.py` for better context (although not strictly used in the current guide generation prompt, it's good practice for future expansions).
6.  **`bin/launch_aiders.sh`**: Modified to read the `aider_model` from the task JSON and set it as an environment variable specifically for each `aider` command it launches (`AIDER_MODEL="..." aider ...`). This ensures each Aider instance uses the model specified in your `config.yaml` via OpenRouter.
7.  **`bin/run_symphony.sh` / `bin/run_single_aider_task.sh`**: Modified to pass the `--tool-root` argument to `orchestrator.py`.

Now, when you run `run_symphony.sh` or `run_single_aider_task.sh`:

*   They will source the `.env` file in the tool's root, setting `OPENROUTER_API_KEY`.
*   `orchestrator.py` will pick up `OPENROUTER_API_KEY` from the environment, read OpenRouter models from `config.yaml`, call the OpenRouter API to generate guides, and produce the tasks JSON including the `aider_model`.
*   `launch_aiders.sh` will read the tasks JSON, including the `aider_model` for each task, and launch Aider instances with `OPENROUTER_API_KEY` (inherited from the shell) and `AIDER_MODEL="..."` set specifically for that Aider process.

This centralizes the API key management and allows you to specify the desired LLM models for both stages (guide generation and coding) via OpenRouter and the configuration file. Remember to `pip install -r requirements.txt` after updating the file.