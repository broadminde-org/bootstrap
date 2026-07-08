---
description: Always use built-in tools for file operations, not bash
---
<file_ops>
- Read: Read tool; Write: Write tool; Edit: Edit tool; Search: Glob/Grep
- Never use bash commands (cat, echo, sed, find, grep) for file content
</file_ops>

## Read tool hygiene

When reading files that may be large (>200 lines):
- Use offset/limit parameters to read targeted sections, not the whole file.
- For shell scripts: read targeted functions with offset+limit around the relevant line range.
- For Python files: read the specific function (find line number with grep first, then offset+limit around it).
- Never read a file you've already read in the same session unless an edit failed.

For large bash outputs: scope the command. Avoid piping unbounded output.
Use `| head -N` or redirect to grep if you only need a subset.

For docker compose logs: stream them to a file, then read that file rather than `docker compose logs <svc>` directly. Containers buffer and truncate on long-running services.

## Session-level read discipline

Never read a file you have already read in the same session unless:
- An edit to that file failed and you need to verify current state.
- The session is long enough that you cannot recall the content with confidence — in that case, consider SESSION_SPLIT_SIGNAL instead.

If you catch yourself about to re-read a file for context, STOP. Reference the path and the content you already read. Do not re-read to "make sure".