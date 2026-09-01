# Plan: 60-caddy — split config hot-reload from image builds

Status: **ready for execution** — run on DeepSeek V4 Pro, thinking enabled (chains >10 tool calls).

## 1. Objective

Make `user/init.d/60-caddy/run.sh` rebuild the Docker image only when the image actually changes, hot-reload config-only changes via the Caddy admin API with no container recreate, and do zero work when nothing changed. Deliverables: modified `user/init.d/60-caddy/run.sh`, one-line change in `user/init.d/60-caddy/stack/Dockerfile`, new `user/init.d/60-caddy/stack/.dockerignore`.

## 2. Context

Single-file step script: `user/init.d/60-caddy/run.sh` (498 lines). Relevant existing structure:

- `run.sh:137-145` — single `changed=0` flag + `sync_file()` helper (cmp-before-write, sets `changed=1`).
- `run.sh:149-153` — syncs `Dockerfile`, `compose.yaml`, `Caddyfile.tmpl`, `bin/caddy-route`, `bin/acmedns-register` from `stack/` to `~/infra/caddy/` (live dir).
- `run.sh:212-217` — rendered-Caddyfile comparison; sets `changed=1` on diff.
- `run.sh:223-297` — wildcard zone rendering; sets `routes_changed=1` (NOTE: `routes_changed` is never initialized to 0 — it is only ever set inside these blocks and read as `${routes_changed:-0}` at `run.sh:437`).
- `run.sh:305-364` — `central_json()` writes `~/infra/caddy/central.json`; called unconditionally at line 364 with hardcoded `0` (before running state is sampled — always writes stale `running: false` on first write).
- `run.sh:374-387` — the change branch: `compose build`, wipe autosave via `compose run --rm`, rm `.last-pushed.sha256`.
- `run.sh:393-394` — `was_running` sampled AFTER the build.
- `run.sh:396-424` — running branch: `compose up -d`, 60s health wait, `caddy-route reconcile`, `central_json 1`.
- `run.sh:447-495` — post-condition checks (adapt validation, CrowdSec health, route list), gated on `was_running`.

Supporting facts (verified, do not re-derive):

- `stack/compose.yaml:26` — `./Caddyfile:/etc/caddy/Caddyfile:ro` is a **bind mount**: host-rendered Caddyfile changes are visible inside the running container with no recreate. This is what makes the hot-reload path possible.
- `stack/bin/caddy-route reconcile` (`stack/bin/caddy-route:81-169`) already adapts `/etc/caddy/Caddyfile` in-container, deep-merges routes.d snippets, and POSTs to the admin API `/load` over the unix socket — atomic, zero-downtime, keeps connections alive. It has an internal sha256 hash-skip (`.last-pushed.sha256`): running it when converged is a no-op.
- `stack/compose.yaml:10-12` — version pins live only in the Dockerfile; compose.yaml carries no build args. A compose.yaml change is service-level (ports/volumes/healthcheck/env) and applies via `compose up -d` without a rebuild.
- `stack/Dockerfile:50` — `RUN apk upgrade --no-cache` busts the layer cache on every Alpine index change.
- `stack/bin/caddy-route` and `stack/bin/acmedns-register` are **host-side** scripts, not mounted into the container — syncing them requires no Caddy action at all.
- `.env` is seeded once (`run.sh:70-76`) and operator-edited thereafter; it is NOT synced by `sync_file`. Its values flow into (a) the rendered Caddyfile (detected via the render diff) and (b) the container environment `CROWDSEC_BOUNCER_KEY` (`compose.yaml:23`), which only updates on recreate.

## 3. Acceptance criteria

All commands run from the repo root as the deploy user, container already running and healthy.

1. **Lint**: `shellcheck user/init.d/60-caddy/run.sh user/init.d/60-caddy/stack/.dockerignore 2>/dev/null; shellcheck user/init.d/60-caddy/run.sh` → exit 0, no new warnings vs. pre-change baseline (`git stash; shellcheck …; git stash pop` if unsure of baseline).
2. **Idempotent no-op**: run `./user/init.sh 60-caddy` twice back-to-back. Second run output MUST contain `No changes` and MUST NOT contain `compose build`, `Waiting for caddy`, or `Configuration changed`.
3. **No recreate on no-op**: `docker inspect -f '{{.Id}}' caddy` identical before and after the second run.
4. **Config-only hot reload**: append a comment line to `user/init.d/60-caddy/stack/Caddyfile.tmpl`, run the step. Output MUST NOT contain `compose build`; container ID MUST be unchanged; `docker exec caddy caddy adapt --config /etc/caddy/Caddyfile --adapter caddyfile` exits 0. Revert the comment, run again — same expectations.
5. **Image rebuild**: append a comment line to `user/init.d/60-caddy/stack/Dockerfile`, run the step. Output MUST show a build; container ID MUST differ afterward; container reaches `healthy`. Revert after.
6. **Compose-only change**: add a harmless label under `services.caddy` in `stack/compose.yaml` (e.g. `labels: {test.touch: "1"}`), run the step. Container ID MUST differ (recreate) but `docker images caddy-custom:latest -q` MUST be unchanged (no build). Revert after.
7. **Never auto-starts**: stop caddy (`docker stop caddy`), run the step. `docker ps -q --filter name=^caddy$` MUST be empty afterward; output MUST contain the `never starts it automatically` message. Restart with `cd ~/infra/caddy && docker compose up -d` and confirm healthy.
8. **Dockerfile**: `grep -n 'apk upgrade' user/init.d/60-caddy/stack/Dockerfile` → single line, no `--no-cache`.
9. **central.json**: after any no-op run with caddy running, `jq -r .status.running ~/infra/caddy/central.json` → `true`.

## 4. Risk analysis

| # | Risk | Mitigation in design | Acceptance check |
|---|---|---|---|
| R1 | Lifecycle violation: step starts a stopped container (explicit invariant, `run.sh:9-13`) | Every apply branch gated on `was_running=1`; stopped branch only prints instructions | #7 |
| R2 | Config-only path recreates container → drops all edge connections (the bug being fixed) | Config branch runs `caddy-route reconcile` only; never `compose up -d`/`build` | #3, #4 |
| R3 | `.env` edits to `CROWDSEC_BOUNCER_KEY` are invisible to file sync; container env only updates on recreate → stale key after rotation | When step 2 (`run.sh:83-106`) writes a new bouncer key, set `compose_changed=1` so the container is recreated with the new env | code inspection: key-write path sets the flag |
| R4 | Wiping autosave on config-only change loses the pushed config on next restart (autosave wipe exists to defeat stale `--resume`, `run.sh:379-384`) | Autosave wipe + `.last-pushed.sha256` removal gated on `image_changed` only | #4 passes; `~/infra/caddy/.last-pushed.sha256` still exists after config-only run |
| R5 | `routes_changed` currently uninitialized (`run.sh:262,283,295` set it; `run.sh:437` reads `${routes_changed:-0}`) — folding into new flags must not lose wildcard-change detection | Wildcard render/remove sets `config_changed=1`; delete the separate `routes_changed` variable entirely | `grep -n routes_changed user/init.d/60-caddy/run.sh` → no matches |
| R6 | `central_json` written before `was_running` is sampled (`run.sh:364` vs 393) → permanently stale `running: false`; also rewritten every no-op run | Write `central.json` exactly once at the end with the final `was_running` value; skip the write when no change flags are set AND the existing file's `.status.running` already equals the final value | #9 |
| R7 | Adding `.dockerignore` to the sync set: its changes must NOT trigger a rebuild (build-context-only file) | `.dockerignore` synced but sets no change flag | code inspection: its `sync_file` call passes a flag name that no branch consumes, or syncs without setting any flag |

## 5. Steps (dependency order)

Run on Pro with thinking enabled. Discovery steps are read-only; if any cited line number does not match reality, STOP and re-plan — do not improvise around drift.

### Step 0 — Discovery (read-only)

Read `user/init.d/60-caddy/run.sh` in full. Confirm the anchors in §2 match. STOP and re-plan if the file has diverged structurally (e.g. `sync_file` gone, step numbering changed).

### Step 1 — Diagnose the spurious `changed=1`

Add temporary verbose output to `sync_file` (print `new:`/`diff:`/`ok:` per file with the dst path) and to the rendered-Caddyfile comparison (print which branch fired). Run `./user/init.sh 60-caddy` twice with no source edits.

- If the second run reports all `ok` and prints `No changes`: the spurious trigger does not reproduce in the current tree; remove the temporary verbosity, note the finding in the commit message, proceed to Step 2.
- If a specific file reports `diff` on the second run: STOP. Report which file and the `diff` output (`diff <src> <dst>`). Do not proceed — a nondeterministic render or sync must be root-caused first, otherwise the new flags inherit the bug.

Keep the per-file `ok/diff/new` logging permanently (one line per file) — it is the diagnostic surface for future runs and costs nothing.

### Step 2 — Split the change flag

Replace the single `changed` with three flags, all initialized to 0 where `changed=0` sits today (`run.sh:137`):

- `image_changed` — set only by the `Dockerfile` sync.
- `compose_changed` — set by the `compose.yaml` sync, and by the bouncer-key write in step 2 of the script (R3).
- `config_changed` — set by `Caddyfile.tmpl` sync, the rendered-Caddyfile write, all wildcard-zone render/remove sites (replacing `routes_changed` — delete that variable, R5), and the two `bin/*` syncs.

Sync `.dockerignore` (new, Step 4) without setting any flag (R7).

Every site that today reads `changed` or `routes_changed` must be audited and switched to the correct flag: `run.sh:374` (change branch), `run.sh:437` (stopped-container hint — fires when `config_changed` or `image_changed` or `compose_changed`).

### Step 3 — Rebuild policy branches

Replace the `run.sh:374-441` logic with four mutually exclusive paths. Ordering constraint: `was_running` must be sampled once AFTER any build (the existing comment at `run.sh:389-392` explains why — keep that comment and behavior), but BEFORE that, no branch may take any action that assumes container state.

1. **`image_changed=1`** (regardless of other flags): existing behavior — `compose build`; autosave wipe + `.last-pushed.sha256` removal (R4); if `was_running`: `compose up -d`, 60s health wait (keep existing loop), `caddy-route reconcile`.
2. **`image_changed=0, compose_changed=1`**: no build. If `was_running`: `compose up -d` (recreates with new service config), 60s health wait, `caddy-route reconcile`.
3. **`image_changed=0, compose_changed=0, config_changed=1`**: no build, no recreate, no health wait. If `was_running`: `caddy-route reconcile` (its internal hash-skip makes a converged push a no-op), then the adapt post-condition check (existing `run.sh:452-458`) and CrowdSec check (existing `run.sh:466-487`).
4. **All zero**: print `No changes — caddy stack is up to date.` Do NOT write central.json unless the recorded running state is stale (R6). Do NOT run post-condition checks.

Not-running behavior (any flag combination): keep the existing stopped branch (`run.sh:425-441`) verbatim except the hint condition from Step 2. The step NEVER starts a stopped container (R1).

### Step 4 — Dockerfile + .dockerignore

- `stack/Dockerfile:50`: delete `--no-cache` from the `apk upgrade` line. Leave the CVE comment block above it untouched.
- Create `stack/.dockerignore` excluding exactly: `/logs`, `/routes.d`, `/*.json`, `/.env`, `/.last-pushed.sha256`. Add the `sync_file` call for it per Step 2 (no flag).
- Note: this Dockerfile edit itself sets `image_changed` on the next run — expected; that run is the one full rebuild.

### Step 5 — central.json timing (R6)

Delete the unconditional `central_json 0` call (`run.sh:364`) and the `central_json 1` call inside the running branch (`run.sh:424`). Call `central_json` exactly once, after the final `was_running` is known, passing that value — but only when (any change flag set) OR (existing `central.json` missing) OR (`jq -r .status.running` of the existing file differs from the final value). Otherwise skip silently.

### Step 6 — Verify

Run every acceptance criterion in §3, in order. Criteria 4–6 each end by reverting the probe edit and re-running, leaving the tree clean (`git status` shows only the intended three files modified/added).

## 6. Stop conditions & escalation

- Same acceptance check fails 3 consecutive times → stop, report the check, the command output, and the diff so far. Do not attempt a fourth variant.
- Step 1 reveals a nondeterministic render/sync → stop and report before restructuring.
- Any cited anchor in §2 is absent or moved → stop and re-plan.
- Never silence a failing check by deleting it, loosening it, or special-casing the probe. Never edit files outside the three in the manifest. No scope creep: do not refactor unrelated parts of run.sh, do not restyle, do not "improve" caddy-route.

## 7. Assumptions & open questions

- Caddy's `POST /load` is atomic and keeps existing connections alive (documented Caddy behavior; the existing reconcile already relies on it).
- The host has `shellcheck` installed. If missing, note it and skip criterion 1 — do not install anything.
- The operator's live dir `~/infra/caddy` may contain a `compose.override.yaml` (see `run.sh:60-61`); the compose-changed detection only covers the synced `compose.yaml`. Overrides are operator-managed and out of scope.
- Assumed acceptable: a `bin/caddy-route` edit sets `config_changed` and triggers a reconcile that hash-skips to a no-op. Harmless; avoids a fourth flag for a rare case.

## 8. Self-check gate (executor must complete before finishing)

Re-read §1. For each acceptance criterion 1–9, paste the command you ran and the relevant output line proving it passed. List every assumption you made that is not in §7. If any criterion lacks evidence, the task is not done.

## 9. Non-negotiables

1. The step NEVER starts a stopped container. Every apply path is gated on `was_running=1`.
2. Config-only changes MUST NOT run `compose build` or `compose up -d` — hot-reload via `caddy-route reconcile` only.
3. Nothing-changed runs do zero work: no build, no reconcile, no central.json rewrite (unless state-stale), no post-condition checks.
4. Autosave wipe and `.last-pushed.sha256` removal happen only on `image_changed=1`.
5. Follow the existing file's style: bash strictures already present, comment-heavy step banners, `echo` operator messaging. Match, don't reinvent.

## File manifest

| File | Change |
|---|---|
| `user/init.d/60-caddy/run.sh` | Split flags, four rebuild-policy branches, per-file sync logging, central.json timing fix, delete `routes_changed` |
| `user/init.d/60-caddy/stack/Dockerfile` | Remove `--no-cache` from `apk upgrade` (line 50) |
| `user/init.d/60-caddy/stack/.dockerignore` | New: `/logs`, `/routes.d`, `/*.json`, `/.env`, `/.last-pushed.sha256` |
