#!/usr/bin/env bash
set -euo pipefail

# Test script to verify window positioning with multiple tasks
echo "--- Testing Window Positioning with Multiple Terminal Windows ---"

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

# How many test windows to create
NUM_TEST_WINDOWS=20        # Increased to demonstrate the wrapping behavior
echo "Creating $NUM_TEST_WINDOWS test windows"

for (( i=0; i<$NUM_TEST_WINDOWS; i++ ))
do
    WINDOW_NUM=$((i+1))
    
    # Create a simple script to run in each window
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
    
    # Update the window information display to show the column grouping
    cat > "$TERMINAL_SCRIPT" << EOSCRIPT
#!/bin/bash
echo "Test Window #${WINDOW_NUM}"
echo "This window demonstrates the positioning system."
echo "Window position calculation:"
echo "  Group: $GROUP_INDEX (offset: $VERTICAL_GROUP_OFFSET px)"
echo "  Column: $COLUMN_INDEX (within group)"
echo "  Row: $ROW_INDEX"
echo ""
echo "Press ENTER to close this window..."
read
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
    set custom title of front window to "Test Window #${WINDOW_NUM}"
end tell
EOF

    echo "  Opening test window #${WINDOW_NUM} at position {$LEFT, $TOP, $RIGHT, $BOTTOM}"
    osascript "$APPLESCRIPT_FILE"
    
    # Brief pause to allow Terminal window to open
    sleep 0.5
done

echo ""
echo "--- Test windows opened successfully ---"
echo "Each window shows its position calculation."
echo "Press ENTER in each window to close it." 