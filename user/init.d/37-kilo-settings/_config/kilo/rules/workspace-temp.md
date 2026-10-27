# Agent Temporary Files

## Scope
All agent tasks that create temporary files, scratch data, test artifacts, logs, screenshots, or intermediate build output.

## Rules
- NO_HOST_TEMP: Never create or write agent scratch files under `/tmp`, `/var/tmp`, `/dev/shm`, or another host-global temporary directory. Exception: when the tool harness explicitly designates a pre-approved directory such as `/tmp/kilo`, that harness directory is allowed — prefer `$HOME/.tmpdir/` when there is a choice.
- AGENT_TEMP: Use the provisioned, user-owned `$HOME/.tmpdir/` for agent scratch files across workspaces. Use unique names for concurrent tasks. Shell deletion commands are denied by policy; do not clean scratch from an agent session — a systemd user tmpfiles rule (provisioned by bootstrap step 37) prunes entries older than 14 days.
- OUTPUTS: Keep files the user needs in the workspace or its designated output directory, not in `$HOME/.tmpdir/`.
- PATHS: Pass explicit paths under `$HOME/.tmpdir/` for scratch files; do not rely on implicit system temporary locations.
