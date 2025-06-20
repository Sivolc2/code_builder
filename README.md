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
