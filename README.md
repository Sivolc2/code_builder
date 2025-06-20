# Code Builder - AI Feature Implementation Automation

This repository provides tools for automating software development through AI orchestration. The centerpiece is an AI Feature Implementation Automation Tool that leverages multiple Large Language Models (LLMs) to plan and implement features autonomously.

## AI Feature Implementation Automation Tool

This tool automates the complete process of implementing features using AI. It orchestrates different AI models for optimal results:
- **Gemini 2.5 Pro (via OpenRouter)**: Generates detailed implementation documents and guides
- **Claude Code (local CLI)**: Writes the actual code based on the generated guides

The tool is designed to be placed within your project's repository and run from your project's root directory.

### Process Flow

For each feature in a provided list:

1. **Generate Implementation Document**: An LLM (Gemini) creates a detailed Markdown document outlining how to implement the feature. This uses the entire repository context (`repo_contents.txt`), a project-specific context file, and the feature description.

2. **Save Document**: The generated guide is saved to `docs/guides/{index_number}_name_of_feature.md`.

3. **Code Implementation**: The `claude-code` CLI is invoked locally. It's given a dynamic, temporary "slash command" which instructs it to:
   - Read the generated guide
   - Implement the feature following best practices
   - Adhere to rules specified in `CLAUDE_AGENT_RULES.md` (testing, virtual environments, verification, git)
   - Commit the changes with proper conventional commit messages

4. **Repeat**: The process repeats for all features in the list.

### Setup

#### Prerequisites

- **`claude-code` CLI**: Install globally: `npm install -g @anthropic-ai/claude-code`
  - Ensure your Anthropic credentials are properly configured
- **`jq`**: Required for parsing JSON responses
  - Ubuntu/Debian: `sudo apt-get install jq`
  - macOS: `brew install jq`
- **OpenRouter API Key**: Obtain from [OpenRouter.ai](https://openrouter.ai)
- **`git dump` (or equivalent)**: You need a command that produces a `repo_contents.txt` file at the root of your project

#### Installation

1. **Copy Tool Files**: Copy the `auto_feature_tool/` directory into your project's root.

2. **Configure**: 
   - Navigate to the `auto_feature_tool/` directory
   - Copy `config.sh.example` to `config.sh`
   - Edit `config.sh` and fill in your `OPENROUTER_API_KEY`, paths, model preferences, etc.
   - **Important**: The provided `.gitignore` already excludes `auto_feature_tool/config.sh` to protect your API key

3. **Prepare Input Files** (at your project root):

   - **Project Context** (`project_context.md` by default): Create a Markdown file that provides overall context about your project (e.g., main technologies, purpose, high-level architecture).

   - **Feature List** (`features_to_implement.txt` by default): Create a text file listing the features to be implemented. Use this format:
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

   - **Repository Contents** (`repo_contents.txt`): Generate this file using your `git dump` or equivalent command. Example command:
     ```bash
     tree -L 3 --prune -I 'node_modules|.git|.venv|dist|build' . && \
     find . -type f -not -path "./node_modules/*" -not -path "./.git/*" \
     -not -path "./.venv/*" -not -path "./dist/*" -not -path "./build/*" \
     -print0 | xargs -0 -I {} sh -c 'echo "\n===== {} ====="; cat {}'
     ```

4. **Review Agent Rules**: 
   - The file `auto_feature_tool/CLAUDE_AGENT_RULES.md` contains guidelines for Claude Code
   - Customize it if needed to better suit your project's specific requirements

### Usage

1. Navigate to your project's root directory in the terminal
2. Ensure your `repo_contents.txt` is up-to-date
3. Run the script:
   ```bash
   bash auto_feature_tool/auto_feature.sh
   ```

The script will process each feature:
- Generate a detailed implementation guide in `docs/guides/`
- Invoke `claude-code` to implement the feature autonomously
- Create temporary task files in `.claude/commands/` (cleaned up afterwards)
- If `HUMAN_REVIEW="true"` in `config.sh`, pause after each feature for your review

### Configuration Options

Key settings in `auto_feature_tool/config.sh`:

- `OPENROUTER_API_KEY`: Your OpenRouter API key
- `GEMINI_MODEL`: Model identifier for OpenRouter (default: "google/gemini-2.5-pro")
- `PROJECT_CONTEXT_PATH`: Path to your project context file
- `FEATURES_FILE_PATH`: Path to your features list
- `HUMAN_REVIEW`: Set to "true" to pause for review after each feature
- `GUIDES_DIR`: Directory where implementation guides are saved

### Architecture

The tool follows the Zen principle of elegant simplicity:

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Feature List  │ -> │  Gemini Planning │ -> │ Implementation  │
│                 │    │   (OpenRouter)   │    │     Guide       │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                                        │
                                                        v
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Git Commit    │ <- │  Claude Code     │ <- │   Code Writing  │
│                 │    │  Implementation  │    │   & Testing     │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

### Notes and Best Practices

- **Virtual Environments**: The tool assumes Python projects use virtual environments and includes guidance for proper dependency management
- **Autonomous Operation**: Uses `claude --dangerously-skip-permissions` for fully autonomous operation
- **Error Handling**: Includes robust error handling and logging throughout the process
- **Cost Awareness**: Be mindful of API costs for OpenRouter usage
- **Idempotency**: Not designed to be idempotent - manage your git history accordingly when re-running
- **Testing**: The agent rules emphasize writing tests and verifying functionality before committing

### Troubleshooting

Common issues and solutions:

1. **Claude Code not found**: Ensure `claude-code` is installed globally and in your PATH
2. **API Key errors**: Verify your OpenRouter API key is correctly set in `config.sh`
3. **Missing context files**: Ensure all required input files exist before running
4. **jq not found**: Install `jq` for JSON parsing functionality

---

*"Let us contemplate the elegant simplicity of automation, where each tool serves its purpose in perfect harmony."* - The Zen Master 🧘
