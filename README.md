# pcontext – Repo → LLM Markdown Dumper

`pcontext.pl` turns a source-code repository into a single, LLM-friendly Markdown dump with:

* a repo + language overview
* a tree view
* annotated file contents in code fences (` ```lang:path/to/file`)

---

## Quick start (clone via `--git_url`)

You don’t need the repo locally – `pcontext.pl` can clone it, dump it, and clean up after itself:

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
