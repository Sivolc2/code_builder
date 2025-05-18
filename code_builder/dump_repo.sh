#!/bin/bash
# Get the root directory of the git repository
REPO_ROOT=$(git rev-parse --show-toplevel)
# Set output file name
OUTPUT_FILE="repo_contents.txt"

# Clear the file if it exists or create a new empty file
> "$OUTPUT_FILE"

# Define exclusion patterns
EXCLUDES=(
  "docs/guides/*"
  "docs/context/*"
  "pnpm-lock.yaml"
  ".gitignore"
  "LICENSE"
)

# Function to check if a file matches any exclude pattern
should_exclude() {
  local file="$1"
  for pattern in "${EXCLUDES[@]}"; do
    if [[ "$file" == $pattern ]]; then
      return 0  # Should exclude
    fi
  done
  return 1  # Should not exclude
}

# Get list of all committed files, excluding deleted ones
git ls-files | while read -r file; do
    if should_exclude "$file"; then
        continue
    fi

    # Check if file exists (not deleted)
    if [ -f "$REPO_ROOT/$file" ]; then
        # Add file name as header
        echo -e "\n\n===== $file =====\n" >> "$OUTPUT_FILE"

        # Append file contents
        cat "$REPO_ROOT/$file" >> "$OUTPUT_FILE"
    fi
done

echo "Repository contents dumped to $OUTPUT_FILE"
