# Plan: Extract shared dev infrastructure from ee monorepo into bootstrap

## Status: `dev` itself is too tightly coupled to extract in full

The `dev` command orchestrates a monorepo-specific dev environment (`air`, `pm2`, `docker compose`,
`isogen`, `@broadminde/shared`, healthz endpoints, port-file handoffs). Extracting it
as-is would be like extracting `npm run dev` from a specific app — the paths, commands,
and conventions are inseparable.

**However**, the **shared infrastructure** that `dev`, `stack`, `build`, and `tests` all
rely on is portable and reusable. Extracting these components first sets the stage for
extracting the other script families.

---

## File map (source → destination)

All destinations are relative to `bootstrap/user/`.

### Phase 1: Portable detectors (no dependencies)

| Source (`ee/infra/mcp/`)                          | Destination (`scripts/`)        | Notes |
|---------------------------------------------------|----------------------------------|-------|
| `detectors.d/compose.sh`                          | `detectors.d/compose.sh`        | Generic — checks for docker-compose.yml/yaml |
| `detectors.d/dockerfile.sh`                       | `detectors.d/dockerfile.sh`     | Generic — checks for Dockerfile |
| `detectors.d/go.sh`                               | `detectors.d/go.sh`             | Generic — checks for main.go, *.go files |
| `detectors.d/node.sh`                             | `detectors.d/node.sh`           | Slightly monorepo-specific (expects `frontend/package.json`) but portable |
| `detectors.d/py.sh`                               | `detectors.d/py.sh`             | Generic — checks for pyproject.toml, requirements.txt |

**NOT extracted**: `detectors.d/go-drift.sh` — enforces "Direction A" Go structure with
hardcoded Go 1.26.4, `apps/`, `shared/backend/` conventions.

### Phase 2: Portable helpers (paths resolved at runtime)

| Source (`ee/infra/mcp/`)                          | Destination (`scripts/`)        | Notes |
|---------------------------------------------------|----------------------------------|-------|
| `lib/version.sh`                                  | `lib/version.sh`                | Generic — app_version_string, build numbers, git SHA. Only depends on `$EE_ROOT` for git. |
| `internal/pm2-stats.py`                           | `lib/pm2-stats.py`              | Generic — parses `pm2 jlist` stdin, prints `uptime cpu% memMB restarts`. No dependencies. |

### Phase 3: Shared library (the key piece for future scripts)

| Source (`ee/infra/mcp/`)                          | Destination (`scripts/`)        | Notes |
|---------------------------------------------------|----------------------------------|-------|
| `lib/env.sh` (MCP-level)                          | `lib/mcp-env.sh`                | Derives `MCP_ROOT`, `EE_ROOT`, `SCRIPT_ROOT`, `APPS_ROOT`. Modified: `MCP_ROOT` points at `$HOME/scripts`; `EE_ROOT` fallback is `$HOME`; sources `project.sh` from `scripts/lib/`. |

**Key design decision**: The MCP-level `env.sh` currently sources `project.sh` from
`${SCRIPT_ROOT}/lib/project.sh`. We already have `scripts/lib/project.sh` from the
maintain extraction. The MCP-level env will source that same file.

**Already present** from maintain extraction:
- `scripts/lib/env.sh` — the "scripts-level" env (sets SCRIPT_ROOT, EE_ROOT, sources project.sh)
- `scripts/lib/project.sh` — project resolution (used by both env.sh files)
- `scripts/lib/maintain-common.sh` — logging, run_cmd, sudo_run, human_size, etc.

Note: The scripts-level `env.sh` and MCP-level `env.sh` serve different purposes:
- **scripts-level** (`scripts/lib/env.sh`): Sets `SCRIPT_ROOT` → `scripts/`, `EE_ROOT` → `scripts/`. Used by maintain.d steps.
- **MCP-level** (`scripts/lib/mcp-env.sh`): Sets `MCP_ROOT` → `scripts/` (where detectors, dev.d, etc. live), `EE_ROOT` → `$HOME` (fallback), `APPS_ROOT` → `$EE_ROOT/apps`. Used by dev.d/run.sh.

They must not collide — they use different sentinels:
- scripts-level: `_MAINTAIN_ENV_LOADED`
- MCP-level: `_MCP_ENV_LOADED`

### Phase 4: dev.d/common.sh — portable helper function extraction

`dev.d/common.sh` (287 lines) contains many portable functions (`wait_for_port`,
`wait_for_healthz`, `check_pid_port`, `kill_pid`, `rotate_log`, `own_port_pids`,
`extract_port_from_log`, `wait_for_log_pattern`, `step_event`). However, it also
expects monorepo variables (`APP_DIR`, `DEV_DIR`, `BACKEND_PORT`, `MCP_ROOT`) and
includes monorepo-specific wrappers (`compose_cmd`, `has_backend`, `has_frontend`).

**Approach**: Extract the portable core into `scripts/lib/dev-common.sh`, and keep the
ee-specific wrappers in a separate file (`scripts/dev.d/ee-common.sh`).

The portable core provides:
- `log`, `ok`, `warn`, `log_skip`, `fail` (colored output)
- `vlog`, `vrun`, `vrun_logged` (verbose-gated wrappers)
- `vtime_start`, `vtime_end` (verbose timing)
- `step_event` (JSONL structured event emitter — accepts `$STEP_EVENTS_LOG`)
- `wait_for_port`, `wait_for_healthz` (TCP/HTTP readiness)
- `wait_for_log_pattern`, `extract_port_from_log` (log parsing)
- `kill_pid`, `rotate_log`, `own_port_pids`, `check_pid_port` (process management)

Variables these functions need from caller:
- `DEV_VERBOSE`: `true`/`false`, defaults to `false`
- `STEP_EVENTS_LOG`: path to JSONL log file (optional, `step_event` is a no-op if unset)
- `USER`: current user (for `own_port_pids`)

The ee-specific wrappers (`compose_cmd`, `compose_cmd_all_profiles`, `has_backend`,
`has_frontend`, `has_compose`, `has_infra_services`) remain in a shim that sources
the portable core and adds monorepo-specific glue.

### Phase 5: New script-runners/maintain.d interaction

The maintain runner already delegates to `$HOME/scripts/maintain.d/run.sh`. No changes
needed — `30-scripts/run.sh` copies all of `scripts/` → `$HOME/scripts/` on init.

---

## Files to create/modify

### Create:

```
bootstrap/user/scripts/
├── detectors.d/
│   ├── compose.sh          # cp ee/infra/mcp/detectors.d/compose.sh
│   ├── dockerfile.sh       # cp ee/infra/mcp/detectors.d/dockerfile.sh
│   ├── go.sh               # cp ee/infra/mcp/detectors.d/go.sh
│   ├── node.sh             # cp ee/infra/mcp/detectors.d/node.sh
│   └── py.sh               # cp ee/infra/mcp/detectors.d/py.sh
├── lib/
│   ├── version.sh          # cp ee/infra/mcp/lib/version.sh (already generic)
│   ├── pm2-stats.py        # cp ee/infra/mcp/internal/pm2-stats.py
│   ├── mcp-env.sh          # NEW: MCP-level env.sh adapted for bootstrap
│   └── dev-common.sh       # NEW: portable core of dev.d/common.sh
```

### Modify:

```
bootstrap/user/
└── _plans/
    └── extract-dev-infra.md   # THIS FILE
```

---

## Detailed file plans

### `scripts/lib/mcp-env.sh`

Purpose: Derive path variables the way the MCP env.sh does, but adapted for bootstrap.

```bash
# Sets: MCP_ROOT, EE_ROOT (fallback), SCRIPT_ROOT, APPS_ROOT, INIT_ROOT, PM2_HOME
# Sentinels: _MCP_ENV_LOADED (does not collide with _MAINTAIN_ENV_LOADED)
# Sources: project.sh from scripts/lib/project.sh
# MCP_ROOT → $HOME/scripts (where detectors.d, dev.d, etc. live)
# EE_ROOT fallback → $HOME (if not already set by caller)
```

### `scripts/lib/dev-common.sh`

Purpose: Portable dev helper functions extracted from `ee/infra/mcp/dev.d/common.sh`.

Functions to include (same as ee version):
- Colored logging: `log`, `ok`, `warn`, `log_skip`, `fail`
- Verbose helpers: `vlog`, `vrun`, `vrun_logged`, `vtime_start`, `vtime_end`, `verbose_setx`
- Structured events: `step_event`
- Readiness: `wait_for_port`, `wait_for_log_pattern`, `extract_port_from_log`, `wait_for_healthz`
- Process management: `kill_pid`, `rotate_log`, `own_port_pids`, `check_pid_port`

Functions to OMIT (ee-specific wrappers):
- `compose_cmd`, `compose_cmd_all_profiles` — requires `APP_DIR`, `AUTH_DEV_MODE`
- `has_backend`, `has_frontend`, `has_compose`, `has_infra_services` — requires `MCP_ROOT/detectors.d`

These omitted functions should live in a separate `scripts/lib/ee-dev-common.sh` that
sources `dev-common.sh` and adds the monorepo-specific glue. But that file stays in
the ee monorepo — it's not part of the bootstrap.

---

## What stays in the ee monorepo (NOT extracted)

| File | Reason |
|------|--------|
| `scripts/dev` | Wrapper hardcodes `$MCP_ROOT/dev.d/run.sh` path; ee-specific |
| `dev.d/run.sh` | Orchestrator for ee apps; expects `apps/`, `docker-compose.yml`, `.env`, detectors |
| `dev.d/_run_one.sh` | MCP-internal step runner; references `$APPS_ROOT/$APP` |
| `dev.d/10-infra.sh` through `50-vite.sh` | All coupled to ee app structure, tooling, port-file conventions |
| `detectors.d/go-drift.sh` | Enforces ee-specific Go structure |
| `internal/seed-dev-users.py` | ee-specific dev user seeding |

---

## What this enables for future extractions

After this extraction:
- `stack` will find `detectors.d/compose.sh`, `scripts/lib/dev-common.sh`, and `scripts/lib/mcp-env.sh` already in place
- `build` will find `detectors.d/dockerfile.sh`, `detectors.d/go.sh`, `scripts/lib/version.sh` already in place
- `tests` will find `detectors.d/go.sh`, `detectors.d/py.sh`, `detectors.d/node.sh` already in place

The infra families (dev, stack, build, tests, update) share ~80% of their library code.
Extracting the shared lib layer once avoids duplicating it across each family extraction.

---

## Execution order

1. Copy 5 detectors (compose, dockerfile, go, node, py) verbatim
2. Copy `lib/version.sh` verbatim
3. Copy `internal/pm2-stats.py` → `lib/pm2-stats.py` verbatim
4. Write `lib/mcp-env.sh` (adapted MCP-level env)
5. Write `lib/dev-common.sh` (portable core extracted from dev.d/common.sh)
6. Syntax-check all new files
