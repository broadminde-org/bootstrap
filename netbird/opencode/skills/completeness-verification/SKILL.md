---
name: completeness-verification
description: >-
  Final verification step for any codemap/architecture document in the netbird stack.
  Count check against source to ensure every init.d step, template, container, and
  env var is accounted for.
---
## Completeness Verification

### Purpose

Before considering any codemap document complete, perform a count verification against the primary source. This is your final defense against omissions and phantom entries.

### Verification Table

After writing each document, re-read the primary source and emit the following count check in your working notes (not in the doc file itself):

| Check | Expected | Actual | Pass? |
|-------|----------|--------|-------|
| `codemap.md` top-level file count | N (`ls` of repo root) | M (rows in summary table) | ✓ / ✗ |
| `codemap-pipeline.md` init.d step count | N (numbered entries under `init.d/`) | M (rows in table) | ✓ / ✗ |
| `codemap-config.md` template count | N (`*.tmpl` files at repo root) | M (rows in table) | ✓ / ✗ |
| `ARCHITECTURE.md` service count | N (named services in `docker-compose.yml`) | M (rows in table) | ✓ / ✗ |
| Caddyfile route matcher count | N (`@*` matcher blocks + default `/*`) | M (rows in route table) | ✓ / ✗ |
| `.env.example` var count | N (lines in `.env.example`) | M (rows in env table) | ✓ / ✗ |

### Counting Rules

1. **`codemap.md` top-level file count**: count every regular file at the repo root
   (excluding `init.d/`, `.git/`, `.kilo/`, `docs/`). Count every row in the summary
   table. Expected must equal Actual.

2. **`codemap-pipeline.md` init.d step count**: count every numbered directory
   (`init.d/<NN>-*`) and flat file (`init.d/<NN>-*.sh`). Count every row in the
   per-step table. Each step produces exactly one row.

3. **`codemap-config.md` template count**: count every `*.tmpl` file. Count every
   row in the per-template table. Each template produces one row.

4. **`ARCHITECTURE.md` service count**: count every `services:` entry in
   `docker-compose.yml`. Count every row in the per-service table. Each service
   produces one row.

5. **Caddyfile route matcher count**: count every named matcher (`@grpc`, `@gprc`,
   `@websocket`, `@backend`) plus the default `/*` block. Count every row in the
   route table. Expected must equal Actual.

6. **`.env.example` var count**: count every `KEY=value` (or `KEY=`) line, ignoring
   blank lines and comments. Count every row in the env-var table.

### Discrepancy Resolution

- Any ✗ row must be resolved before the document is considered done.
- Explicitly note any discrepancy rather than silently omitting it.
- If a file/table/route exists in source but is intentionally excluded, document the reason in your working notes.
- Re-read the source if counts do not match — do not adjust the count to make it match.

### When to Run

Run this verification:
- After writing a new document from scratch
- After updating an existing document
- Before closing any documentation task

Do not skip this step regardless of time pressure.
