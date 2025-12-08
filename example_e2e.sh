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

echo ""
echo "=== Testing MCP Tool ==="
MCP_OUTPUT_FILE="mcp_output.json"

echo "Running MCP tool with local directory..."
echo '{"path": ".", "compress": true}' | ./pcontext-mcp > "$MCP_OUTPUT_FILE"

# Verify MCP output is valid JSON with success field
if grep -q '"success"' "$MCP_OUTPUT_FILE"; then
    echo "MCP tool returns valid JSON with success field."
else
    echo "MCP tool e2e test failed - missing success field."
    exit 1
fi

# Verify MCP output contains metadata
if grep -q '"metadata"' "$MCP_OUTPUT_FILE"; then
    echo "MCP tool includes metadata."
else
    echo "MCP tool e2e test failed - missing metadata."
    exit 1
fi

# Verify MCP output contains content
if grep -q '"content"' "$MCP_OUTPUT_FILE"; then
    echo "MCP tool includes content."
else
    echo "MCP tool e2e test failed - missing content."
    exit 1
fi

# Test MCP tool with git URL
echo "Running MCP tool with git URL..."
MCP_GIT_OUTPUT="mcp_git_output.json"
./pcontext-mcp --input "{\"git_url\": \"$REPO_URL\", \"compress\": true}" > "$MCP_GIT_OUTPUT"

if grep -q '"success".*true\|"success" : 1' "$MCP_GIT_OUTPUT"; then
    echo "MCP tool git clone test passed."
else
    echo "MCP tool git clone test failed."
    cat "$MCP_GIT_OUTPUT"
    exit 1
fi

# Test MCP schema output
echo "Testing MCP schema output..."
./pcontext-mcp --schema > /dev/null
if [ $? -eq 0 ]; then
    echo "MCP schema output works."
else
    echo "MCP schema output failed."
    exit 1
fi

echo ""
echo "=== All e2e tests passed! ==="

# Clean up
rm -f "$OUTPUT_FILE" "$COMPRESSED_OUTPUT_FILE" "$MCP_OUTPUT_FILE" "$MCP_GIT_OUTPUT"
