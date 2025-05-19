# Feature Symphony Tool

This tool automates the process of breaking down large features into smaller, manageable slices, generating implementation guides for these slices using Google's Gemini API, and then launching Aider instances to implement these guides.

## Prerequisites

1.  **Python**: Version 3.8+
2.  **Git**: For the `dump_repo.sh` script.
3.  **tmux**: For running Aider instances in parallel. (e.g., `sudo apt install tmux` or `brew install tmux`)
4.  **jq**: For parsing JSON in shell scripts. (e.g., `sudo apt install jq` or `brew install jq`)
5.  **Aider**: Ensure `aider` is installed and configured. See Aider's documentation.
6.  **Google Gemini API Key**: You'll need an API key for Gemini.

## Setup

1.  **Clone/Place the Tool**:
    Place the `feature_symphony_tool` directory into your project or a preferred location.

2.  **Configure the Tool**:
    *   Navigate to the `feature_symphony_tool` directory.
    *   Copy `config/config.yaml.template` to `config/config.yaml`.
    *   Edit `config/config.yaml` to set your `gemini_model_guide_generation`, `aider_global_context_files`, and `guides_output_directory` (relative to your main project root).
    *   Copy `.env.template` to `.env`.
    *   Edit `.env` to add your `GEMINI_API_KEY`.
        ```bash
        cd feature_symphony_tool
        cp config/config.yaml.template config/config.yaml
        cp .env.template .env
        # Now edit config/config.yaml and .env with your details
        ```

3.  **Python Virtual Environment (Recommended)**:
    It's highly recommended to run the tool's Python scripts within a virtual environment. From the `feature_symphony_tool` directory:
    ```bash
    python3 -m venv .venv
    source .venv/bin/activate  # On Linux/macOS
    # .venv\Scripts\activate    # On Windows
    pip install -r requirements.txt
    ```
    You'll need to activate this venv (`source .venv/bin/activate`) each time you want to run the tool scripts from a new terminal session if you are running them directly. The main wrapper scripts (`run_symphony.sh`, etc.) will attempt to handle this.

4.  **Make Scripts Executable**:
    Ensure the shell scripts are executable:
    ```bash
    cd feature_symphony_tool
    chmod +x bin/dump_repo.sh bin/launch_aiders.sh run_symphony.sh run_single_aider_task.sh
    ```

## `git dump` Script

The `bin/dump_repo.sh` script creates a `repo_contents.txt` file in your project's root. This file contains a concatenated version of most files in your repository, which can be used as context for LLMs.

**Usage**:
Navigate to your main project's root directory (NOT `feature_symphony_tool` itself, unless that's your target project) and run:
```bash
path/to/feature_symphony_tool/bin/dump_repo.sh
```
This will generate `repo_contents.txt` in your current directory (project root).

You can create a Git alias for convenience (e.g., `git dump`) in your global or project-specific `.gitconfig`:
```ini
[alias]
    dump = "!path/to/feature_symphony_tool/bin/dump_repo.sh"
```

## Workflow Overview

1.  **Prepare Symphony XML**: Manually chat with Gemini (using `repo_contents.txt` as context if desired) to break down a large feature. Format the output as specified:
    ```xml
    <!-- Save this as e.g., my_feature_breakdown.xml in your project -->
    <feature_symphony>
    [
        {
            "name": "Implement User Authentication API",
            "description": "Develop backend API endpoints for user registration, login, and logout using JWT."
        },
        {
            "name": "Setup Database Schemas for Users",
            "description": "Define and migrate database schemas for user profiles, credentials, and sessions."
        }
    ]
    </feature_symphony>
    ```

2.  **Run Feature Symphony**:
    From your main project root:
    ```bash
    path/to/feature_symphony_tool/run_symphony.sh path/to/your/my_feature_breakdown.xml
    ```

3.  **Monitor Aider**:
    A `tmux` session will be created, and Aider instances will start working on each feature slice. You can attach to this session to monitor progress.

## Standalone Aider Task

If you already have a feature guide and want to run Aider on it directly:
```bash
path/to/feature_symphony_tool/run_single_aider_task.sh path/to/your/feature_guide.md
```

This will create a single Aider instance in a tmux session to work on implementing that guide. 