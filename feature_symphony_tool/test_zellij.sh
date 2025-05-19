#!/bin/bash
set -euo pipefail

echo "Testing Zellij command..."

# Create a temporary script to run in Zellij
TEMP_SCRIPT="/tmp/test_zellij_cmd.sh"
SESSION_NAME="test_session_$(date +%s)"

cat > "$TEMP_SCRIPT" << 'EOF'
#!/bin/bash
echo "Hello from Zellij!"
echo "Running a simple command..."
ls -la
echo "Press Ctrl+D to exit"
exec bash
EOF

chmod +x "$TEMP_SCRIPT"

echo "Created temporary script: $TEMP_SCRIPT"
echo "Launching Zellij session: $SESSION_NAME"

# First create the session
echo "Creating Zellij session..."
zellij --session "$SESSION_NAME" options --on-force-close "detach"

# Wait a moment for the session to initialize
sleep 2

# Run the command in the session
echo "Running command in the Zellij session..."
zellij attach "$SESSION_NAME" -c "$TEMP_SCRIPT"

echo "If you're seeing this message, the Zellij attach command returned."
echo "Clean up temp file..."
rm -f "$TEMP_SCRIPT" 