---
description: Quality constraints for all documentation produced for the netbird stack.
---
## Documentation Quality Rules

All agents generating or editing docs under `docs/`, `README.md`, `ARCHITECTURE.md`, or any
`codemap*.md` in the netbird repo must adhere to the following constraints:

### Derive, Never Invent
- Every file path, init.d step number, container name, env var name, and template file
  name must be copied directly from source files.
- If a detail is ambiguous, note the ambiguity explicitly in the document rather than
  guessing or approximating.
- Do not add files from memory; every file in a table must have a corresponding
  inventory entry.

### Cite Actual Paths
- Use `path/to/file.sh:FunctionName` format for shell scripts and `path/to/file.py:func_name`
  for Python, not vague descriptions.
- Use repo-relative paths that can be directly opened by another agent.

### No Invented Surface Area
- Only document routes or HTTP paths present in `Caddyfile` (`@grpc`, `@gprc`,
  `@websocket`, `@backend`, default `/*`) — cross-check every row against the actual
  `Caddyfile` directives.
- Before writing any route table, paste the relevant `Caddyfile` block verbatim as a
  fenced code block and use it as a checklist.
- Only document init.d steps that exist under `init.d/` — list every numbered
  directory or `.sh` file with its full prefix.
- Only document env vars present in `.env.example` (the canonical surface) — never
  document a value only seen in `.env`.

### No Placeholder Sections
- If a doc type does not apply (e.g. no Python in the stack today), omit the section
  entirely rather than writing a stub or placeholder.
- Keep `docs/archive/` clean: never write current-state documentation there; it is
  for explicitly retired material only.

### Atomic Updates
- When refreshing stale docs, rewrite the affected section completely rather than
  patching individual rows.
- Partial patches leave stale entries that mislead downstream agents.

### No Duplication
- `codemap-config.md` (or its equivalent) owns file-by-file env var bindings and
  render inputs.
- `ARCHITECTURE.md` (or its equivalent) owns system boundaries and request flows.
- These documents must not duplicate each other.

### Verify Before Closing

- **Must** run the `completeness-verification` skill before considering any codemap
  document complete.
- Any count mismatch between source and document is a **hard error** — do not close
  without resolving it.
- Do not skip verification regardless of time pressure.
