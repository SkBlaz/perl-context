#!/bin/bash
set -e

# A simple end-to-end test for pcontext.pl
# This script will clone a small git repository, run pcontext.pl on it,
# and check that the output is not empty.

REPO_URL="https://github.com/git-fixtures/basic.git"
OUTPUT_FILE="basic_context.md"
COMPRESSED_OUTPUT_FILE="basic_context_compressed.md"

echo "Running e2e test with normal mode..."
# Run pcontext.pl in normal mode
./pcontext.pl --git_url "$REPO_URL" > "$OUTPUT_FILE"

# Check that the output file is not empty
if [ -s "$OUTPUT_FILE" ]; then
    echo "Normal mode e2e test passed."
else
    echo "Normal mode e2e test failed."
    exit 1
fi

# Verify normal mode output contains file contents
if grep -q "FILE CONTENTS" "$OUTPUT_FILE"; then
    echo "Normal mode includes FILE CONTENTS section."
else
    echo "Normal mode e2e test failed - missing FILE CONTENTS."
    exit 1
fi

echo "Running e2e test with compress mode..."
# Run pcontext.pl in compress mode
./pcontext.pl --git_url "$REPO_URL" --compress > "$COMPRESSED_OUTPUT_FILE"

# Check that the compressed output file is not empty
if [ -s "$COMPRESSED_OUTPUT_FILE" ]; then
    echo "Compress mode e2e test passed."
else
    echo "Compress mode e2e test failed."
    exit 1
fi

# Verify compress mode output contains file list but not file contents
if grep -q "FILE LIST" "$COMPRESSED_OUTPUT_FILE"; then
    echo "Compress mode includes FILE LIST section."
else
    echo "Compress mode e2e test failed - missing FILE LIST."
    exit 1
fi

# Verify compress mode does NOT contain file contents section
if ! grep -q "FILE CONTENTS" "$COMPRESSED_OUTPUT_FILE"; then
    echo "Compress mode correctly excludes FILE CONTENTS section."
else
    echo "Compress mode e2e test failed - should not have FILE CONTENTS."
    exit 1
fi

# Verify compressed output is smaller than normal output
NORMAL_SIZE=$(wc -c < "$OUTPUT_FILE")
COMPRESSED_SIZE=$(wc -c < "$COMPRESSED_OUTPUT_FILE")

if [ "$COMPRESSED_SIZE" -lt "$NORMAL_SIZE" ]; then
    echo "Compress mode output is smaller ($COMPRESSED_SIZE bytes vs $NORMAL_SIZE bytes)."
else
    echo "Warning: Compress mode output is not smaller than normal mode."
fi

echo "All e2e tests passed!"

# Clean up
rm "$OUTPUT_FILE" "$COMPRESSED_OUTPUT_FILE"
