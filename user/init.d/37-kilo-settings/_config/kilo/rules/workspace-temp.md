# Workspace Temporary Files

## Scope
All agent tasks that create temporary files, scratch data, test artifacts, logs, screenshots, or intermediate build output.

## Rules
- NO_HOST_TEMP: Never create or write temporary files under `/tmp`, `/var/tmp`, `/dev/shm`, or another host-global temporary directory.
- WORKSPACE_TEMP: Use `<workspace>/.tmp/` for temporary files. Create it with `mkdir -p .tmp` before use and remove disposable contents when the task is complete.
- TEMP_ENV: Set `TMPDIR="$PWD/.tmp"` when invoking tools that honor `TMPDIR`; do not rely on the host's default temporary directory.
- OUTPUTS: Keep files that the user needs in the workspace or its designated output directory, not in `.tmp/`.
- PATHS: Pass explicit workspace-local paths to scripts and tools instead of using `mktemp` or implicit system temporary locations.
