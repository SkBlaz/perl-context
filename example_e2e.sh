#!/bin/bash
set -e

# A simple end-to-end test for pcontext.pl
# This script will clone a small git repository, run pcontext.pl on it,
# and check that the output is not empty.

REPO_URL="https://github.com/git-fixtures/basic.git"
OUTPUT_FILE="basic_context.md"

# Run pcontext.pl
./pcontext.pl --git_url "$REPO_URL" > "$OUTPUT_FILE"

# Check that the output file is not empty
if [ -s "$OUTPUT_FILE" ]; then
    echo "e2e test passed."
else
    echo "e2e test failed."
    exit 1
fi

# Clean up
rm "$OUTPUT_FILE"
