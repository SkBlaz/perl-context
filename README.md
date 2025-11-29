# Repo → LLM Context Dumper (Perl)

This folder contains a single-purpose Perl script that turns a source code repository into an LLM-friendly text dump:

* A **high-level overview** of the repo (languages, roles, key files, rough token count)
* A **tree view** of the directory structure
* **Language-aware, annotated file contents** wrapped in Markdown code fences, optimised for copy-pasting into an LLM chat

The workflow: run the script on a repo, redirect output to a `.md` file, then paste relevant parts of that file into your LLM and refer to files/chunks/lines by name.

---

## Features

### Repository overview

The script prints a top-level summary:

* Root path, number of directories and files (after filtering)
* Approximate total bytes and tokens (assuming ~4 characters per token)
* **Key files**, including:

  * Entry-point-like files (`main.py`, `src/main.rs`, `cmd/foo/main.go`, `src/index.tsx`, …)
  * Configuration/manifests (`package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `pom.xml`, …)
  * Documentation (`README.md`, `CHANGELOG`, `LICENSE`, …)

Each key file is tagged with its inferred role (`source`, `test`, `config`, `docs`) and flags like “entrypoint-ish” or “config”.

### Language-aware summary

Files are grouped by language, with per-language stats:

* Language name (Python, Rust, JS/TS, Go, …)
* Number of files and approximate tokens per language
* Breakdown by role:

  * `source` – main implementation code
  * `test` – unit/integration tests
  * `config` – configuration/manifest/build files
  * `docs` – documentation / README-style content
  * `other` – everything else

For each language it also lists:

* **Entry-point-like files** (e.g. `src/main.rs`, `cmd/foo/main.go`, `src/index.tsx`)
* **Config/manifest files** (e.g. `pyproject.toml`, `package.json`, `Cargo.toml`, …)

### Code fences optimised for LLMs

Every file’s content is wrapped in a Markdown code fence that embeds both language and path, e.g.:

````text
```lang:path/to/file.ext
...file contents...
```
````

This makes it easy to:

* Ask the model about a **specific file** by name (`lang:path/to/file.ext`)
* Refer to **chunks** within large files
* Copy/paste only the relevant parts of the repo when context is tight

### Verbose per-file metadata

Before each file’s content, the script prints:

* File path and clear **start/end markers**

  * `=== FILE START: path/to/file ===`
  * `=== FILE END: path/to/file ===`
* Size, text/binary detection
* Language name and internal language key
* Inferred **role** (source/tests/config/docs/other)
* Short **hint** string, for example:

  * `probable application entrypoint`
  * `JS/TS tests (Jest/Vitest/Mocha style naming)`
  * `Node.js package manifest (dependencies + scripts)`
  * `Python project configuration (PEP 621 / tooling)`
  * `Rust crate manifest`
  * `Go module definition`

Binary or non-text files are **omitted** with an explanatory note.

### Chunking & line numbers

To control context size, files can be:

* **Chunked by line count** – each chunk gets its own fenced block, with headers like `--- CHUNK 2 of path/to/file ---`
* Hard-limited by size (per-file byte threshold)
* Optionally annotated with **line numbers** (`NNNN|`) so you can say “see chunk 2 around line 137”.

---

## Requirements

* Perl 5 (any reasonably modern distribution)
* Only core modules:

  * `File::Find`
  * `File::Spec`
  * `Cwd`
  * `utf8`

No CPAN dependencies. The script is read-only and does not modify the repo.

---

## Usage

Assume the script file is named `repo_dump_verbose.pl` (you can rename it).

### Basic usage

From the root of the repo:

```bash
perl repo_dump_verbose.pl . > repo_context.md
```

Then open `repo_context.md` and paste relevant sections into your LLM.

### Tighter limits

Limit maximum bytes per file and lines per chunk:

```bash
REPO_DUMP_MAX_BYTES=200000 \
REPO_DUMP_MAX_LINES=800 \
perl repo_dump_verbose.pl . > repo_context.md
```

Files over the size limit are skipped with a short note.

### Line numbers

Add line numbers for precise references:

```bash
REPO_DUMP_LINE_NUMBERS=1 \
perl repo_dump_verbose.pl . > repo_context_with_ln.md
```

Example line prefix:

```text
  137| some_code_here();
```

You can then say things like:

> See `typescript:src/components/Foo.tsx`, chunk 2, around line 137.

### Only certain languages / extensions

Limit to specific file extensions (comma-separated, no dots):

```bash
REPO_DUMP_ONLY_EXT="py,js,ts,tsx" \
perl repo_dump_verbose.pl . > python_and_js_only.md
```

This is useful when you want to ignore other ecosystems and focus the LLM on core code.

### Extra excludes

The script respects `.gitignore` and also accepts extra glob-style exclude patterns:

```bash
REPO_DUMP_EXCLUDE="docs/*,__snapshots__/*,*.min.js" \
perl repo_dump_verbose.pl . > repo_context.md
```

These are applied on top of `.gitignore` and built-in noisy-directory pruning (`.git`, `node_modules`, `dist`, `build`, `target`, `venv`, `__pycache__`, …).

---

## Configuration (environment variables)

All configuration is via environment variables:

* **`REPO_DUMP_MAX_BYTES`**
  Max file size in bytes. Larger files are skipped.
  Default: `300000`

* **`REPO_DUMP_MAX_LINES`**
  Max lines per chunk. `0` or empty = no chunking (one fence per file).
  Default: `1200`

* **`REPO_DUMP_LINE_NUMBERS`**
  If set (any value), prefix each line with `NNNN|`.
  Default: unset (no line numbers)

* **`REPO_DUMP_ONLY_EXT`**
  Comma-separated list of extensions to include, e.g. `py,ts,tsx`.
  If unset, all extensions are allowed (subject to ignores).

* **`REPO_DUMP_EXCLUDE`**
  Comma-separated list of extra glob-style patterns to exclude, e.g.
  `docs/*,__snapshots__/*,*.min.js`.

---

## Output structure

The generated Markdown is structured as:

1. `### REPO OVERVIEW`
   High-level stats, approximate tokens, list of key files.

2. `### LANGUAGE OVERVIEW`
   Per-language breakdown: file counts, approx tokens, roles, entrypoints, configs.

3. `### REPO TREE`
   Indented directory tree.

4. `### FILE CONTENTS`
   For each file:

   * Metadata (size, language, role, hints)
   * Optional chunk headers
   * A fenced block using `lang:path/to/file.ext`
   * Closing `=== FILE END ===` marker

This structure is designed so both you and the LLM can:

* Filter to relevant files/chunks
* Refer to locations unambiguously
* Rerun the script with different filters/limits as the conversation deepens.

---

## Tips for LLM use

* Start by pasting:

  1. `REPO OVERVIEW`
  2. `LANGUAGE OVERVIEW`
  3. A small subset of `FILE CONTENTS` (key files only)

* Then ask the LLM:

  * To summarise architecture and key components
  * Which additional files/chunks it wants to inspect next

* When context is limited:

  * Use `REPO_DUMP_ONLY_EXT` and `REPO_DUMP_EXCLUDE` to narrow the dump
  * Lower `REPO_DUMP_MAX_BYTES` / `REPO_DUMP_MAX_LINES` and paste incrementally
  * Turn on line numbers to make back-and-forth on precise locations easier

---

## License
MIT
