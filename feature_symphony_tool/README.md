# Feature Symphony Tool

This tool automates the process of breaking down large features into smaller, manageable slices, generating implementation guides for these slices using OpenRouter API, and then launching Aider instances to implement these guides.

## Prerequisites & Dependencies

1.  **Python**: Version 3.8+
2.  **Git**: For the `dump_repo.sh` script.
3.  **Zellij**: For running Aider instances in parallel. (e.g., `brew install zellij` or `cargo install zellij`)
4.  **jq**: For parsing JSON in shell scripts. (e.g., `sudo apt install jq` or `brew install jq`)
5.  **Aider**: Ensure `aider` is installed and configured. See Aider's documentation.
6.  **OpenRouter API Key**: You'll need an API key from OpenRouter.

## Setup

1.  **Clone/Place the Tool**:
    Place the `feature_symphony_tool` directory into your project or a preferred location.

2.  **Install Dependencies**:
    ```bash
    cd feature_symphony_tool
    python3 -m venv .venv
    source .venv/bin/activate
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
    chmod +x bin/launch_aiders_zellij.sh
    chmod +x run_symphony.sh
    chmod +x run_single_aider_task.sh
    chmod +x generate_guides.sh
    ```

## Usage

### Quick Start

1.  First, run the repository dump script to create a context file for the LLM:
    ```bash
    cd your_project_root  # where your Git repository is
    path/to/feature_symphony_tool/bin/dump_repo.sh
    ```

2.  Create a file (e.g., `my_feature_breakdown.txt`) containing your feature breakdown within `<feature_symphony>` tags:
    ```
    <feature_symphony>
    [
        {
            "name": "User Authentication",
            "description": "Implement user login, registration, and session management"
        },
        {
            "name": "Password Reset",
            "description": "Add password reset functionality with email verification"
        }
    ]
    </feature_symphony>
    ```

3.  To generate feature guides without running Aider:
    ```bash
    cd your_project_root  # where your Git repository is
    path/to/feature_symphony_tool/generate_guides.sh path/to/my_feature_breakdown.txt
    ```

4.  To generate guides and launch Aider instances to implement them:
    ```bash
    cd your_project_root  # where your Git repository is
    path/to/feature_symphony_tool/run_symphony.sh path/to/my_feature_breakdown.txt
    ```

### Command-Line Options

Both `generate_guides.sh` and `run_symphony.sh` support the following command-line options:

* **--threads N**: Number of threads for parallel guide generation (default: 1)
* **--output-dir DIR**: Directory to save guides (overrides the config setting)
* **--model MODEL**: OpenRouter model to use (overrides the config setting)
* **--context-files FILE1 [FILE2...]**: Additional context files (space-separated list)

Examples:

```bash
# Generate guides with 4 threads
./feature_symphony_tool/generate_guides.sh my_feature_breakdown.txt --threads 4

# Generate guides using a custom model and output directory
./feature_symphony_tool/generate_guides.sh my_feature_breakdown.txt --model anthropic/claude-3-opus --output-dir custom/guides

# Generate guides and run Aider with additional context files
./feature_symphony_tool/run_symphony.sh my_feature_breakdown.txt --context-files docs/architecture.md src/main.py
```

### Monitor Aider Tasks (macOS)

*   This tool will open a **new Terminal window for each Aider task** when running on macOS.
*   Each Terminal window will contain its own dedicated Zellij session running one Aider instance.
*   You can interact with each Aider instance in its respective window.
*   To close a specific Aider task, you can type `exit` or `Ctrl+D` in its Zellij pane, or simply close the Terminal window.
*   Zellij sessions are named like `symphony_aider_RUNID_taskN_description`. You can list them with `zellij list-sessions` and attach manually if needed, e.g., `zellij attach session_name`.

### Example Commands

Here are some practical examples of how to use the tool:

1. **Basic Setup and Configuration**:
   ```bash
   # Clone the tool into your project
   cd your_project_root
   git clone https://github.com/your-org/feature_symphony_tool.git

   # Setup the tool
   cd feature_symphony_tool
   python3 -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt

   # Configure the tool
   cp config/config.yaml.template config/config.yaml
   cp .env.template .env
   # Edit config.yaml and .env with your settings
   ```

2. **Generate Repository Context**:
   ```bash
   # From your project root
   ./feature_symphony_tool/bin/dump_repo.sh
   # This creates repo_contents.txt in your project root
   ```

3. **Create a Feature Breakdown**:
   ```bash
   # Create a new file for your feature breakdown
   cat > my_feature_breakdown.txt << EOF
   <feature_symphony>
   [
       {
           "name": "User Authentication",
           "description": "Implement user login, registration, and session management"
       },
       {
           "name": "Password Reset",
           "description": "Add password reset functionality with email verification"
       }
   ]
   </feature_symphony>
   EOF
   ```

4. **Generate Only Feature Guides**:
   ```bash
   # From your project root
   ./feature_symphony_tool/generate_guides.sh my_feature_breakdown.txt
   
   # With custom options
   ./feature_symphony_tool/generate_guides.sh my_feature_breakdown.txt --model anthropic/claude-3-opus --output-dir custom/guides
   ```

5. **Run Full Feature Symphony (Generate Guides + Launch Aider)**:
   ```bash
   # From your project root
   ./feature_symphony_tool/run_symphony.sh my_feature_breakdown.txt
   
   # With custom options
   ./feature_symphony_tool/run_symphony.sh my_feature_breakdown.txt --threads 4 --context-files docs/architecture.md
   ```

6. **Run Single Feature Guide**:
   ```bash
   # If you have a pre-existing guide
   ./feature_symphony_tool/run_single_aider_task.sh docs/feature_guides/feature_slice_guide_user_authentication.md
   ```

7. **Environment Setup for Each Run**:
   ```bash
   # Activate the tool's virtual environment
   cd feature_symphony_tool
   source .venv/bin/activate
   source .env  # Load API keys

   # Return to project root
   cd ..

   # Now run the tool
   ./feature_symphony_tool/generate_guides.sh my_feature_breakdown.txt
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

1.  **Prepare Symphony File**: Manually chat with an LLM (using `repo_contents.txt` as context if desired) to break down a large feature. Format the output within feature_symphony tags:
    ```
<feature_symphony>
[
    {
        "name": "Feature Name",
        "description": "Feature Description"
    },
    {
        "name": "Another Feature Name",
        "description": "Another Feature Description"
    }
]
</feature_symphony>
    ```

2.  **Generate Feature Guides Only**:
    From your main project root (where your code and `.git` directory are):
    ```bash
    path/to/feature_symphony_tool/generate_guides.sh path/to/your/my_feature_breakdown.txt
    ```

3.  **Run Feature Symphony with Aider**:
    From your main project root (where your code and `.git` directory are):
    ```bash
    path/to/feature_symphony_tool/run_symphony.sh path/to/your/my_feature_breakdown.txt
    ```

## Standalone Aider Task

If you already have a feature guide and want to run Aider on it directly from your project root:

```bash
path/to/feature_symphony_tool/run_single_aider_task.sh path/to/your/feature_guide.md
``` 