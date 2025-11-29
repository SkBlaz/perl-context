# Basic: full repo dump to a Markdown file you can paste into an LLM
perl repo_dump_verbose.pl /path/to/repo > repo_context.md

# Tighter per-file limits
REPO_DUMP_MAX_BYTES=200000 REPO_DUMP_MAX_LINES=800 \
  perl repo_dump_verbose.pl . > ctx.md

# Only Python and JS/TS code, skipping docs/tests/snapshots dirs via extra excludes
REPO_DUMP_ONLY_EXT="py,js,ts,tsx" \
REPO_DUMP_EXCLUDE="docs/*,__snapshots__/*" \
  perl repo_dump_verbose.pl . > ctx_code.md

# With line numbers so you can say “see file X, chunk 2, line 137”
REPO_DUMP_LINE_NUMBERS=1 \
  perl repo_dump_verbose.pl . > ctx_ln.md
