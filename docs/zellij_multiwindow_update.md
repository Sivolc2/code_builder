# Zellij Multi-Window Update for macOS

## Overview

The feature_symphony_tool has been updated to support launching each Aider task in its own Terminal window on macOS. This provides better isolation and a clearer interface for working with multiple parallel Aider tasks.

## Changes Implemented

1. **Modified `launch_aiders_zellij.sh`**: 
   - Now creates a separate Terminal window for each Aider task using AppleScript
   - Each task runs in its own dedicated Zellij session
   - Includes robust quoting and environment variable handling
   - Creates temporary runner scripts in `/tmp/` that are cleaned up after use

2. **Updated README.md**:
   - Added macOS-specific instructions for monitoring tasks
   - Removed outdated instructions for Zellij pane management
   - Updated workflow descriptions

## How It Works

When you run a feature symphony task on macOS:

1. The script iterates through each Aider task from the JSON configuration
2. For each task, it creates a temporary shell script with the necessary parameters
3. AppleScript opens a new Terminal window and runs this temporary script
4. The script launches a unique Zellij session for that specific task
5. The temporary scripts are automatically cleaned up

## Usage Notes

- Each Terminal window title reflects the Zellij session name
- Zellij sessions are named: `symphony_aider_RUNID_taskN_description`
- You can close a task by simply closing its Terminal window or typing `exit` in the Zellij pane
- If needed, you can list or reattach to Zellij sessions with:
  ```bash
  zellij list-sessions
  zellij attach session_name
  ```

## Requirements

- macOS (this feature uses AppleScript to open Terminal windows)
- Terminal.app (default macOS terminal)
- Zellij, jq, and Aider installed and in PATH 