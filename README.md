```
 |  __ \        | |       / ____|          | |          | |
 | |__) |__ _ __| |______| |     ___  _ __ | |_ _____  _| |_
 |  ___/ _ \ '__| |______| |    / _ \| '_ \| __/ _ \ \/ / __|
 | |  |  __/ |  | |      | |___| (_) | | | | ||  __/>  <| |_
 |_|   \___|_|  |_|       \_____\___/|_| |_|\__\___/_/\_\\__|
```

# pcontext – Repo → LLM Markdown Dumper

[![CI](https://github.com/SkBlaz/perl-context/actions/workflows/ci.yml/badge.svg)](https://github.com/SkBlaz/perl-context/actions/workflows/ci.yml)

`pcontext.pl` turns a source-code repository into a single, LLM-friendly Markdown dump with:

* a repo + language overview
* a tree view
* annotated file contents in code fences (` ```lang:path/to/file`)

---

## Quick start (clone via `--git_url`)

You 'don't need the repo locally – `pcontext.pl` can clone it, dump it, and clean up after itself:

```bash
perl pcontext.pl --git_url https://github.com/psf/requests.git > requests_context.md
```

This will:

1. Clone `https://github.com/psf/requests.git` into a temp directory
2. Walk the repo and print:

   * overview + languages
   * tree
   * file contents in fenced blocks
3. Delete the temporary clone when done

You can then paste parts of `requests_context.md` into an LLM.

---

## Local repo usage

If you already have the repo locally:

```bash
# From inside the repo
perl /path/to/pcontext.pl . > repo_context.md

# Or from elsewhere
perl pcontext.pl /path/to/repo > repo_context.md
```

---

## Compression mode

For quick repository overviews without full file contents, use `--compress`:

```bash
perl pcontext.pl --compress . > repo_structure.md

# Or with a remote repo
perl pcontext.pl --git_url https://github.com/psf/requests.git --compress > requests_structure.md
```

Compression mode outputs:
* `### REPO OVERVIEW` – same as normal mode
* `### LANGUAGE OVERVIEW` – same as normal mode  
* `### REPO TREE` – same as normal mode
* `### FILE LIST` – file metadata only (no contents)

This produces **much smaller** output (~50x reduction) with just the high-level structure, perfect for getting a quick understanding of a repository's organization.

---

## Useful options (env vars)

Everything is configured via environment variables:

```bash
# Limit how big a single file may be (bytes)
REPO_DUMP_MAX_BYTES=200000 \

# Limit lines per chunk (0 = no chunking)
REPO_DUMP_MAX_LINES=800 \

# Add line numbers: "  137| some_code()"
REPO_DUMP_LINE_NUMBERS=1 \

# Only dump certain extensions (no dots, comma-separated)
REPO_DUMP_ONLY_EXT="py,js,ts" \

# Extra glob-style excludes (on top of .gitignore)
REPO_DUMP_EXCLUDE="docs/*,__snapshots__/*,*.min.js" \

perl pcontext.pl --git_url https://github.com/psf/requests.git > filtered_context.md
```

---

## Output structure (high level)

The generated Markdown is organised into:

1. `### REPO OVERVIEW` – root, dirs, files, approx tokens, key files
2. `### LANGUAGE OVERVIEW` – per-language file counts / tokens / roles
3. `### REPO TREE` – indented directory tree
4. `### FILE CONTENTS` – for each file:

   * metadata (size, language, role, hints)
   * optional `--- CHUNK N of path/to/file ---` headers
   * a fence like:

	 ````text
	 ```python:src/module/foo.py
	 ...file contents...
	 ````

	 ```
	 ```
   * closing `=== FILE END: src/module/foo.py ===`

Paste only the parts you need into your LLM (overview + selected files/chunks) and refer to files as `lang:path/to/file` and to specific lines when line numbers are enabled.

---

## MCP Tool (for LLM integration)

The `pcontext-mcp` tool provides an MCP (Model Context Protocol) compatible interface for programmatic use by LLMs. It accepts JSON input and returns JSON output.

### Basic usage

```bash
# Via stdin
echo '{"path": "."}' | ./pcontext-mcp

# Via --input flag
./pcontext-mcp --input '{"path": ".", "compress": true}'

# Print schema
./pcontext-mcp --schema
```

### Input parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `path` | string | `.` | Local directory to analyze |
| `git_url` | string | - | Git repository URL to clone |
| `compress` | boolean | `false` | Structure only, no file contents |
| `output_format` | string | `markdown` | `markdown` or `json` |
| `include_extensions` | array | - | Only include these extensions |
| `exclude_patterns` | array | - | Glob patterns to exclude |
| `max_file_size` | integer | `300000` | Max file size in bytes |
| `max_lines_per_chunk` | integer | `1200` | Lines per chunk (0=no chunking) |
| `include_line_numbers` | boolean | `false` | Add line numbers |
| `max_total_output_bytes` | integer | `0` | Truncate output (0=unlimited) |

### Example: Analyze repository with filtering

```bash
./pcontext-mcp --input '{
  "path": "/path/to/repo",
  "include_extensions": ["py", "ts", "tsx"],
  "exclude_patterns": ["*_test.py", "*.spec.ts"],
  "compress": true
}'
```

### Output structure

```json
{
  "success": true,
  "metadata": {
    "root_path": "/path/to/repo",
    "total_files": 42,
    "total_dirs": 10,
    "total_bytes": 123456,
    "approx_tokens": 30864,
    "languages": {...},
    "key_files": [...]
  },
  "content": "# Repository Context Dump\n...",
  "truncated": false
}
```

### Using as an LLM tool

The tool is designed to be called by LLMs that need to understand codebases on the fly. The schema file `mcp-tool.json` contains the full MCP tool definition:

```bash
# Get the schema for LLM tool registration
cat mcp-tool.json
```

Key features for LLM usage:
- **Structured output**: JSON response with metadata + content
- **Compression mode**: Quick overview without full file dumps
- **Smart filtering**: Focus on specific file types or exclude patterns
- **Language detection**: 50+ programming languages recognized
- **Key file identification**: Entrypoints, configs, and docs highlighted
