# Shell Environment & Init Systems

## Scope
Shell scripts, init.d systems, environment files, provisioning scripts.

## Init System Tier Model

### Tier 1: Host Provisioning (root-level)
- Group memberships (`usermod -aG`)
- Sudoers config
- Docker engine install
- System packages (`apt-get install`)

### Tier 2: App Tier (unprivileged user)
- Docker containers
- Application configs
- Service health checks

### Idempotency Pattern
Every initialization step must be safe to re-run:
1. CHECK_CURRENT → compare actual state vs desired
2. SKIP_IF_MATCH → if state matches, log "skipped" and return 0
3. APPLY → if state differs, apply the change
4. VERIFY → confirm the change took effect

## Env File Lifecycle

### Source of Truth
- `.env.example` is the canonical environment variable template
- `.env` and `.env.secrets` are GENERATED from `.env.example` at init time
- `.env` is ALWAYS in `.gitignore`

### Template Rendering
- Template files (`.tpl`, `.example`, `.template`) are the source of truth
- Rendered config files are output only — never hand-edit them
- Use `envsubst` or equivalent for template variable substitution
- Track rendered output freshness with a diff check after render

## Shell Script Rules
- CHECK_BEFORE_TOUCH: `-e`, `-d`, `-f` tests before creating
- DIR_LISTING: Use `read` tool for directory listings, not `ls`
- SYNTAX_CHECK: Run `bash -n` after every edit
- NO_HARDCODE: Paths and values from env vars or config, never inline
- SOURCE_SAFE: `source ./relative/path.sh` not bare `source thing.sh` from `$PATH`
- SCREAM_CASE: Environment variables in UPPER_CASE. Local variables in lower_case.
