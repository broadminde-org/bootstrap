# Agent Temporary Files

## Scope
All agent tasks that create temporary files, scratch data, test artifacts, logs, screenshots, or intermediate build output.

## Rules
- NO_HOST_TEMP: Never create or write agent scratch files under `/tmp`, `/var/tmp`, `/dev/shm`, or another host-global temporary directory.
- AGENT_TEMP: Use the provisioned, user-owned `$HOME/.tmpdir/` for agent scratch files across workspaces. Use unique names for concurrent tasks and remove only your own disposable files when finished.
- TEMP_ENV: Do not prefix routine shell calls with `TMPDIR=...`. Set `TMPDIR="$HOME/.tmpdir"` only for a tool that actually needs its implicit temporary files redirected; use the tool's explicit temp/output path option when available.
- OUTPUTS: Keep files the user needs in the workspace or its designated output directory, not in `$HOME/.tmpdir/`.
- PATHS: Pass explicit paths under `$HOME/.tmpdir/` for scratch files; do not rely on implicit system temporary locations.
