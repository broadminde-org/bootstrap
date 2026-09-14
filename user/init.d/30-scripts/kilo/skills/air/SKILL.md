---
name: air
description: >-
  Live-reload Go backends with Air on this host. USE FOR: creating or editing
  a project .air.toml, wiring a Go backend into the host `dev` runner
  (auto-port via .dev/backend.port, /healthz health check), debugging
  air/dev up failures (port-file timeout, build-errors.log), choosing
  between root .air.toml and backend/.air.toml. DO NOT USE FOR: production
  deploys (air is dev-only), Python/uv backends (dev precedence:
  DEV_BACKEND_CMD > air > uv), or non-Go file watchers.
---

# Air — Go live reload on this host

Air (`~/go/bin/air`, installed by bootstrap `user/init.d/25-go`) rebuilds and
restarts a Go backend on file change. The host `dev` runner
(`scripts/dev` → `dev.d/40-air.sh`) owns its lifecycle: config detection,
logging, pidfile, port allocation, and health gating.

## TL;DR

1. Copy the canonical template from the bootstrap checkout into the project
   (on this host the checkout is `~/bootstrap`):

   ```bash
   cp ~/bootstrap/user/init.d/30-scripts/templates/air.toml.template .air.toml
   # template assumes the Go module is in backend/; if it's at the repo root,
   # edit cmd to "go build -buildvcs=false -o .dev/tmp/<app> ."
   ```

2. Replace every `<app>` placeholder with the binary name.
3. Make the Go backend satisfy the contract below (port file + health endpoint).
4. `dev up`.

Never run `air init` for projects on this host — the upstream default diverges
from the host contract (`tmp/` instead of `.dev/tmp`, no port-file awareness).

## Where the config lives

| Location | When |
|---|---|
| `<project>/.air.toml` | Default. Root wins when both exist. |
| `<project>/backend/.air.toml` | Only when the Go module lives in `backend/` and no root config exists. `40-air.sh` then runs air from `backend/` — edit `cmd` to build `.` and expect `.dev/tmp` under `backend/`, not the project root. |
| `<project>/.config/air.toml` | **Never.** Upstream air accepts it; the host `has_air()` check doesn't. |
| `~/.config/air/...` | **Does not exist.** Air has no global/user config; it searches CWD only. |

Runtime details: `dev` starts air via `setsid air`, logs to
`.dev/backend.log`, tracks `.dev/backend.pid`, and health-waits. Backend
selection precedence: `DEV_BACKEND_CMD` > air > uv.

## The `dev` contract (mandatory for auto-port)

When `LISTEN_ADDR` is unset or ends in `:0`, `dev` allocates a free port and
exports `BACKEND_PORT_FILE=.dev/backend.port`. The Go process MUST:

1. Listen on `LISTEN_ADDR`.
2. Write the resolved port to `os.Getenv("BACKEND_PORT_FILE")` after
   `net.Listen` succeeds.
3. Serve `200 OK` on `${DEV_HEALTH_PATH:-/healthz}`.

Minimal Go snippet:

```go
ln, err := net.Listen("tcp", os.Getenv("LISTEN_ADDR")) // e.g. ":0"
if err != nil { log.Fatal(err) }

if pf := os.Getenv("BACKEND_PORT_FILE"); pf != "" {
    port := ln.Addr().(*net.TCPAddr).Port
    if err := os.WriteFile(pf, []byte(strconv.Itoa(port)), 0o644); err != nil {
        log.Fatalf("write port file: %v", err)
    }
}

mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
    w.WriteHeader(http.StatusOK)
})
log.Fatal(http.Serve(ln, mux))
```

With a pinned port (`LISTEN_ADDR=:8090`) the port file is not required, but
`/healthz` still is.

## Canonical .air.toml template

The template source of truth is
`bootstrap/user/init.d/30-scripts/templates/air.toml.template`. Key decisions
it encodes:

- `tmp_dir = ".dev/tmp"` — keeps air state inside the gitignored `.dev/` dir
  that `dev` already owns.
- `entrypoint = ["./.dev/tmp/<app>"]` — modern form. Do NOT use `bin`: air
  warns `build.bin is deprecated; set build.entrypoint instead`.
- `cmd = "go build -buildvcs=false ..."` — worktrees/detached checkouts must
  not fail the build.
- `send_interrupt = true` + `kill_delay = "2s"` — graceful shutdown so the
  backend releases its port before air kills it. (Some older project configs
  set `send_interrupt = false`; that is drift, not a convention.)
- `delay = 1000`, `stop_on_error = true`, `exclude_unchanged = false`.
- No `[proxy]` (Vite owns browser reload), no `env_files` (direnv owns env).

Full field reference: https://github.com/air-verse/air/blob/master/air_example.toml

## Escape hatches

- **`[[build.rules]]`** — run a command on matched file changes WITHOUT a Go
  rebuild (templ/sqlc/go generate, asset pipelines). A file matched by a rule
  never triggers a rebuild; if the rule's output is watched (e.g. generated
  `.go`), the rebuild follows naturally.
- **Debug**: `air -d` prints watcher/build/runner detail. Air's own build log
  is `.dev/tmp/build-errors.log`; the runner log is `.dev/backend.log`.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Backend did not write port file at .dev/backend.port` | Go process doesn't write `BACKEND_PORT_FILE` | Add the snippet above; confirm `LISTEN_ADDR` is `:0` or unset |
| `Backend exited before writing port file` | Build failure or panic at startup | Read `.dev/backend.log` and `.dev/tmp/build-errors.log` |
| Port already in use after restart | Stale `.dev/backend.pid` or `send_interrupt = false` | `dev down`; check for orphan processes on the port; use the template's `send_interrupt = true` |
| `dev` says "No .air.toml found" | Config named/located wrong | Must be `.air.toml` at root or `backend/`; `.config/air.toml` is NOT detected |
| `[warning] build.bin is deprecated` | Old config uses `bin` | Switch to `entrypoint = ["<path>"]` |

## Rules agents must not break

- Always name the file `.air.toml` (root or `backend/`), never `.config/air.toml`.
- Never create or reference `~/.config/air/` — air has no global config.
- Never use deprecated `build.bin` in new files.
- Never enable `[proxy]` — it conflicts with Vite's port and reload.
- Never set `env_files` — direnv owns environment on this host.
- Keep `tmp_dir` under `.dev/`.
- Air is dev-only; never wire it into Docker images, CI, or production.
