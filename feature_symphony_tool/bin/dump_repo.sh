#!/bin/bash
# Get the root directory of the git repository
REPO_ROOT=$(git rev-parse --show-toplevel)
# Set output file name (in the REPO_ROOT)
OUTPUT_FILE="$REPO_ROOT/repo_contents.txt"

# Clear the file if it exists or create a new empty file
> "$OUTPUT_FILE"

# Define exclusion patterns (relative to REPO_ROOT)
# Add more patterns as needed
EXCLUDES=(
  "docs/guides/*"       # Example: exclude generated guides
  "docs/context/*"      # Example: exclude other context files
  "pnpm-lock.yaml"
  ".gitignore"
  "LICENSE"
  "*.lock"
  "node_modules/*"
  "dist/*"
  "build/*"
  ".venv/*"
  "__pycache__/*"
  ".DS_Store"
  "feature_symphony_tool/runs/*" # Exclude tool's own run artifacts
  "repo_contents.txt" # Exclude the output file itself
)

# Function to check if a file matches any exclude pattern
should_exclude() {
  local file_to_check="$1"
  for pattern in "${EXCLUDES[@]}"; do
    if [[ "$file_to_check" == $pattern || "$file_to_check" == */$pattern ]]; then
      # Handle direct match and directory prefix match for patterns like "node_modules/*"
      if [[ "$pattern" == *"*"* ]]; then # If pattern contains wildcard
         if [[ "$file_to_check" == $pattern ]]; then
            return 0 # Exclude
         fi
      elif [[ "$file_to_check" == "$pattern" ]]; then # Exact match
            return 0 # Exclude
      fi
    fi
  done
  return 1  # Should not exclude
}

echo "Dumping repository contents to $OUTPUT_FILE..."
echo "Excluding patterns: ${EXCLUDES[*]}"

# Get list of all committed files, excluding deleted ones
# Using git ls-files -co --exclude-standard to respect .gitignore and get cached/other files
# Then apply custom exclusion list
git ls-files -co --exclude-standard | while read -r file; do
    relative_file_path="$file" # Path is already relative to REPO_ROOT

    if should_exclude "$relative_file_path"; then
        # echo "Excluding: $relative_file_path" # Uncomment for debugging
        continue
    fi

    # Check if file exists (not deleted)
    if [ -f "$REPO_ROOT/$relative_file_path" ]; then
        # Add file name as header
        echo -e "\n\n===== $relative_file_path =====\n" >> "$OUTPUT_FILE"

        # Append file contents
        cat "$REPO_ROOT/$relative_file_path" >> "$OUTPUT_FILE"
    fi
done

echo "Repository contents dumped to $OUTPUT_FILE" 