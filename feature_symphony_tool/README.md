# Feature Symphony Tool

This tool automates the process of breaking down large features into smaller, manageable slices, generating implementation guides for these slices using OpenRouter API, and then launching Aider instances to implement these guides.

## Prerequisites & Dependencies

1.  **Python**: Version 3.8+
2.  **Git**: For the `dump_repo.sh` script.
3.  **tmux**: For running Aider instances in parallel. (e.g., `sudo apt install tmux` or `brew install tmux`)
4.  **jq**: For parsing JSON in shell scripts. (e.g., `sudo apt install jq` or `brew install jq`)
5.  **Aider**: Ensure `aider` is installed and configured. See Aider's documentation.
6.  **OpenRouter API Key**: You'll need an API key from OpenRouter.

## Setup

1.  **Clone/Place the Tool**:
    Place the `feature_symphony_tool` directory into your project or a preferred location.

2.  **Install Dependencies**:
    ```bash
    cd feature_symphony_tool
    pip install -r requirements.txt
    ```

3.  **Configure**:
    *   Copy `config/config.yaml.template` to `config/config.yaml`.
    *   Edit `config/config.yaml` to set your `openrouter_model_guide_generation`, `aider_global_context_files`, and `guides_output_directory` (relative to your main project root).
    *   Copy `.env.template` to `.env`.
    *   Edit `.env` to add your `OPENROUTER_API_KEY`.
        ```bash
        cd feature_symphony_tool
        # (Ensure you are in the feature_symphony_tool directory)
        cp config/config.yaml.template config/config.yaml
        cp .env.template .env
        # Now edit config/config.yaml and .env with your details
        ```

4.  **Configure Aider for OpenRouter**:
    The tool uses OpenRouter for both guide generation and Aider tasks. While the Python side uses the API key from the `.env` file, Aider will use its own configuration.
    
    To set up Aider to use OpenRouter by default:
    
    ```bash
    # Create or edit Aider's config file
    mkdir -p ~/.config/aider
    cat > ~/.config/aider/config.yaml << EOF
    # Aider configuration for OpenRouter
    openai_api_base: https://openrouter.ai/api/v1
    openai_api_key: your_openrouter_api_key_here
    model: anthropic/claude-3-7-sonnet  # or your preferred model
    EOF
    ```
    
    Alternatively, you can set these as environment variables in your shell profile:
    ```bash
    # Add to ~/.bashrc, ~/.zshrc, etc.
    export OPENAI_API_BASE=https://openrouter.ai/api/v1
    export OPENAI_API_KEY=your_openrouter_api_key_here
    export AIDER_MODEL=anthropic/claude-3-7-sonnet
    ```

5.  **Make Scripts Executable**:
    ```bash
    chmod +x bin/dump_repo.sh
    chmod +x bin/launch_aiders.sh
    chmod +x run_symphony.sh
    chmod +x run_single_aider_task.sh
    ```

## Usage

### Quick Start

1.  First, run the repository dump script to create a context file for the LLM:
    ```bash
    cd your_project_root  # where your Git repository is
    path/to/feature_symphony_tool/bin/dump_repo.sh
    ```

2.  Create a file (e.g., `my_feature_breakdown.xml`) containing your feature breakdown.

3.  Run the feature symphony orchestrator:
    ```bash
    cd your_project_root  # where your Git repository is
    path/to/feature_symphony_tool/run_symphony.sh path/to/my_feature_breakdown.xml
    ```

## `git dump` Script

The `bin/dump_repo.sh` script creates a `repo_contents.txt` file in your project's root. This file contains a concatenated version of most files in your repository, which can be used as context for LLMs.

**Usage**:
```bash
cd your_project_root
path/to/feature_symphony_tool/bin/dump_repo.sh
```

You can also customize the exclusion patterns in the script to skip certain file types or directories.

Example of modifying exclusions:
```bash
# Open the script in an editor
vim path/to/feature_symphony_tool/bin/dump_repo.sh
# Edit the EXCLUDES array
```

## Workflow Overview

1.  **Prepare Symphony XML**: Manually chat with an LLM (using `repo_contents.txt` as context if desired) to break down a large feature. Format the output as specified:
    ```xml
    <feature_symphony>
    [
        {
            "name": "Feature Slice 1 Name",
            "description": "Feature Slice 1 Description"
        },
        {
            "name": "Feature Slice 2 Name",
            "description": "Feature Slice 2 Description"
        }
    ]
    </feature_symphony>
    ```

2.  **Run Feature Symphony**:
    From your main project root (where your code and `.git` directory are):
    ```bash
    path/to/feature_symphony_tool/run_symphony.sh path/to/your/my_feature_breakdown.xml
    ```

3.  **Work with Aider**:
    Once the Aider instances are launched in tmux:
    *   Attach to the tmux session: `tmux attach-session -t symphony_aider_20230615_123456`.
    *   Switch between windows (each running one Aider instance for one feature slice): `Ctrl+b <window number>`.

## Standalone Aider Task

If you already have a feature guide and want to run Aider on it directly from your project root:

```bash
path/to/feature_symphony_tool/run_single_aider_task.sh path/to/your/feature_guide.md
``` 