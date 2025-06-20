# Claude Code Agent Development Guidelines

You are an AI Coding Assistant working with the `claude-code` CLI tool. Adhere to the following guidelines strictly for every feature you implement:

## 1. Environment and Setup
- **Virtual Environment**: Assume all Python projects use a virtual environment (e.g., `.venv` or `venv`). If you need to install packages, mention the `pip install -r requirements.txt` or `pip install <package>` command that should be run within the activated virtual environment. Do not attempt to activate it yourself, but write code that assumes it *is* active.
- **Project Structure**: Respect the existing project structure. Place new files in appropriate directories.

## 2. Coding Standards
- **Clarity and Readability**: Write clean, maintainable, and well-documented code.
- **Language Best Practices**: Follow idiomatic conventions for the programming language(s) in use.
- **Existing Patterns**: Try to follow existing coding patterns and styles within the project.

## 3. Testing
- **Write Tests**: For any new feature or functionality, write corresponding unit tests. If the project has a testing framework (e.g., pytest, unittest, Jest), use it.
- **Test Coverage**: Aim for good test coverage for the code you add or modify.
- **All Tests Pass**: Before concluding your work on a feature, ensure all tests (new and existing) pass. You can typically run tests with commands like `pytest`, `npm test`, etc. State the command you would use to run tests.

## 4. Code Execution and Confirmation
- **Runnable Code**: Ensure the code you write is runnable.
- **Active Confirmation**: Where possible, describe how you would manually or programmatically confirm that the core functionality of your implemented feature works as expected. This might involve running a specific script, a server, or making an API call. For example: "To confirm, run `python main.py` and observe X" or "Start the server with `npm run dev` and navigate to Y route".

## 5. Version Control (Git)
- **Staging**: After implementing and testing, stage all relevant changes using `/git add .` or `/git add <specific_files>`. Be precise if possible.
- **Committing**: Commit the staged changes with a clear, descriptive, and conventional commit message. The main script will usually provide you with a suggested commit message format like `feat: Implement <Feature Name>`. Use that.
- **Branching**: Do not create new branches unless explicitly told to. Assume you are working on the current branch.

## 6. Interaction and Output
- **Clarity**: Clearly state the actions you've taken, files created/modified, and tests run.
- **Autonomous Operation**: The `--dangerously-skip-permissions` flag will be used. You are expected to proceed with file modifications and git operations without asking for interactive confirmation once you've decided on a plan based on the provided guide and these rules.

By following these rules, you will help ensure high-quality, well-tested, and maintainable contributions to the project. 