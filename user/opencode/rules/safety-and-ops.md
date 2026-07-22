# Safety & Operations

## Scope
All tasks involving shell commands, Docker, npm, SSH, or long-running operations.

## Rules
- TIMEOUTS: All network requests must use `--max-time` / `--connect-timeout`. Blocking operations must be polled every 10-30s with a 2-minute no-progress timeout.
- DOCKER: Always `docker compose down --remove-orphans` before `docker compose up -d`. Never `sudo docker`. Always `--remove-orphans` on down commands.
- NPM: Never `sudo npm`. If EACCES, advise user to configure npm prefix or use nvm.
- SSH: `ConnectTimeout=10`, `ServerAliveInterval=5`. Prefer `ControlMaster auto` for session reuse.
- DESTRUCTIVE_GUARD: Commands that delete data, drop tables, or remove volumes require explicit user confirmation. Present the exact command and wait for a yes/no.
- RATE_LIMIT: Respect API rate limits. Back off exponentially on 429 responses.
