#!/usr/bin/env bash
set -euo pipefail

# Test script for a large number of windows to demonstrate multiple wrapping
echo "--- Testing Window Positioning with Many Windows (Multiple Wrapping) ---"

if ! command -v osascript >/dev/null 2>&1; then
  echo "Error: 'osascript' command not found. This script is designed for macOS."
  exit 1
fi

# Create a temporary directory for our script files
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Window positioning configuration
WINDOW_WIDTH=800
WINDOW_HEIGHT=600
WINDOWS_PER_COLUMN=6
COLUMN_WIDTH=$((WINDOW_WIDTH + 50)) # Add some gap between columns
WINDOW_VERTICAL_OFFSET=30  # Slightly overlap windows vertically (title bar height)
SCREEN_TOP_MARGIN=25       # Start near the top of the screen
SCREEN_LEFT_MARGIN=10      # Start near the left edge
MAX_COLUMNS=2              # Maximum number of columns before wrapping back to the left side
COLUMN_GROUP_OFFSET=200    # Larger vertical offset for each group of columns when wrapping

# How many test windows to create - enough for multiple wraps
NUM_TEST_WINDOWS=32
echo "Creating $NUM_TEST_WINDOWS test windows (multiple wrapping)"

for (( i=0; i<$NUM_TEST_WINDOWS; i++ ))
do
    WINDOW_NUM=$((i+1))
    
    # Create a very simple script to run in each window (minimal content to reduce resources)
    TERMINAL_SCRIPT="${TEMP_DIR}/test_cmd_${WINDOW_NUM}.sh"
    
    # Calculate window position with wrap-around for many windows
    BASE_COLUMN_INDEX=$((i / WINDOWS_PER_COLUMN))
    ROW_INDEX=$((i % WINDOWS_PER_COLUMN))
    
    # When exceeding MAX_COLUMNS, wrap back to left side with vertical offset
    GROUP_INDEX=$((BASE_COLUMN_INDEX / MAX_COLUMNS))  # Which group of columns (0, 1, 2, etc.)
    COLUMN_INDEX=$((BASE_COLUMN_INDEX % MAX_COLUMNS)) # Column within the group (0 to MAX_COLUMNS-1)
    
    LEFT=$((SCREEN_LEFT_MARGIN + COLUMN_INDEX * COLUMN_WIDTH))
    
    # Apply vertical offset for each group and add row position within the group
    VERTICAL_GROUP_OFFSET=$((GROUP_INDEX * COLUMN_GROUP_OFFSET))
    TOP=$((SCREEN_TOP_MARGIN + VERTICAL_GROUP_OFFSET + ROW_INDEX * WINDOW_VERTICAL_OFFSET))
    
    RIGHT=$((LEFT + WINDOW_WIDTH))
    BOTTOM=$((TOP + WINDOW_HEIGHT))
    
    # Simple window content
    cat > "$TERMINAL_SCRIPT" << EOSCRIPT
#!/bin/bash
echo -e "\033]0;Window #${WINDOW_NUM} - Group ${GROUP_INDEX}\007" # Set window title
echo "Window #${WINDOW_NUM} - Group: ${GROUP_INDEX}, Column: ${COLUMN_INDEX}, Row: ${ROW_INDEX}"
echo "Press any key to close..."
read -n 1
exit
EOSCRIPT

    chmod +x "$TERMINAL_SCRIPT"
    
    # Create AppleScript file to open and position the terminal window
    APPLESCRIPT_FILE="${TEMP_DIR}/test_applescript_${WINDOW_NUM}.scpt"
    
    cat > "$APPLESCRIPT_FILE" << EOF
tell application "Terminal"
    set newWindow to do script "${TERMINAL_SCRIPT}"
    delay 0.1
    set bounds of front window to {$LEFT, $TOP, $RIGHT, $BOTTOM}
    set custom title of front window to "#${WINDOW_NUM} G${GROUP_INDEX} C${COLUMN_INDEX} R${ROW_INDEX}"
end tell
EOF

    # Only show every 4th window in the output to reduce clutter
    if (( i % 4 == 0 )); then
        echo "  Opening window #${WINDOW_NUM} (Group: ${GROUP_INDEX}, Column: ${COLUMN_INDEX}) at position {$LEFT, $TOP, $RIGHT, $BOTTOM}"
    fi
    
    osascript "$APPLESCRIPT_FILE"
    
    # Very brief pause to avoid overloading the system
    sleep 0.1
done

echo ""
echo "--- Multiple Window Groups Opened ---"
echo "Windows are now organized in ${GROUP_INDEX} groups of columns."
echo "Press any key in each window to close it." 