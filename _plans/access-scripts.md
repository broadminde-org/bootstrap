# bootstrap-access / github-access — how the interactive credential setup works

Two scripts, two layers. Both ship from `user/init.d/30-scripts/scripts/`, are
deployed to `~/scripts/` by the `30-scripts` step, and have `~/.local/bin/`
wrappers so they run by name. Both must run as the deploy user, never root.
Both source shared helpers (`log/ok/warn/fail`, `require_deploy_user`,
`resolve_bootstrap_root`, `file_env_value`/`write_env_value`) from
`scripts/lib/access-common.sh`.

## Layers

### bootstrap-access — the host-level wizard (no arguments)

Entry point after both bootstrap tiers complete. It:

1. Resolves `BOOTSTRAP_ROOT` (env var → source checkout → `~/bootstrap`).
2. Loads the active conf via `resolve_conf_file` from `init.d/lib/conf.sh`
   (`<hostname>.conf.yml` beats `bootstrap.conf.yml`; same helper the
   `init.sh` runners use).
3. Walks **only the enabled capabilities that need interactive credentials**,
   verifying current state before each prompt (idempotent, safe to re-run):

   | Capability | Stage |
   |---|---|
   | `dev` | `gh` login (via `github-access auth`) → deploy keys → packages PAT → optional source-RW PAT |
   | `docker` + `caddy` | ACME email into `~/infra/caddy/.env`, acme-dns registration when `caddy.wildcards` is set, then re-runs `user/init.sh 60-caddy` |
   | `docker`/`kvm`/`public` alone | nothing — reports "no interactive credentials needed" and exits 0 |

4. The dev stage's credential breadth comes from the conf's `github:` section,
   not from prompts:
   - `github.packages_write: true` → `github-access packages --write` (publish hosts).
   - `github.source_rw: true` → `github-access source-rw` (push/PR hosts).

   Both default to `false` when the keys are unlisted. `github-access`
   validates the stored PAT's scopes on every run, so widening a host is:
   flip the conf key, re-run the walk, paste the replacement token.

`bootstrap-access` owns no GitHub logic itself — every GitHub operation is
delegated to `github-access`.

### github-access — the GitHub domain tool (subcommands)

```
github-access setup [--ci]     # auth + deploy-keys + packages [--write + source-rw]
github-access auth             # gh login only
github-access deploy-keys      # re-runs user/init.sh 99-go-shared
github-access packages [--write]
github-access source-rw
github-access clear packages|source-rw|--all   # remove stored tokens
github-access status           # full credential inventory
```

What it actually does:

- **auth**: `gh auth login --web --git-protocol ssh` if not already
  authenticated. The operator's `gh` login serves human API/issue/PR use and
  lets `99-go-shared` register deploy keys via `gh api`.
- **deploy-keys**: gates on the `dev` capability, then delegates to
  `user/init.sh 99-go-shared`, which creates per-repo read-only SSH deploy
  keys (`~/.ssh/go-shared-read`, `~/.ssh/frontend-shared-read`) and registers
  them through the GitHub API when the operator has repo admin permission.
- **packages**: guides classic-PAT creation (prefilled URL:
  `read:packages`, plus `write:packages` with `--write`), validates scopes by
  reading the `X-Oauth-Scopes` response header from `gh api user --include`,
  stores the token in `~/.config/gh/broadminde-packages.token` (0600, atomic
  write), then re-runs `98-npm-shared` which writes `~/.npmrc` (0600) and
  verifies against the live npm registry. `read:packages` is mandatory in both
  modes — GitHub treats `write:packages` as independent (a write-only token
  passes the token page but cannot pull), and an empty paste is re-prompted
  once rather than sent to validation.
- **source-rw**: same flow for the broader automation PAT (`repo`,
  `workflow`), stored in `~/.config/gh/broadminde-source-rw.token`,
  additionally verifying push permission on
  `broadminde-org/go-shared` and `broadminde-org/frontend-shared`.
- **clear**: removes the stored token file, any legacy `bootstrap/.env`
  entry, and — for packages — the managed lines in `~/.npmrc` (the file
  itself is removed when it held nothing else). No confirmation prompts.

## Credential model

| Credential | Storage | Scopes | Purpose |
|---|---|---|---|
| Operator `gh` auth | gh credential store | gh defaults | Human/API workflows, deploy-key registration |
| Per-repo deploy keys | `~/.ssh/*-shared-read` | read-only | Source fetches of go-shared / frontend-shared |
| `BROADMINDE_PACKAGES_TOKEN` | `~/.config/gh/broadminde-packages.token` → `~/.npmrc` | `read:packages` (+ `write:packages` on publish hosts) | npm/GHCR package pulls (and publishes) |
| `BROADMINDE_SOURCE_RW_TOKEN` | `~/.config/gh/broadminde-source-rw.token` | `repo`, `workflow` | CI/source pushes, issues, PRs |

Constraints that shaped the design:

- GitHub Packages' npm registry **requires a classic PAT** — fine-grained PATs
  and gh's OAuth token don't work there. `gh` cannot mint PATs, so the script
  guides creation via a prefilled URL and validates the paste.
- Tokens are split by blast radius: the broad `repo`-scoped token is never
  written to `~/.npmrc`.
- Classic PATs never live in the bootstrap checkout: `bootstrap/.env` is not
  a credential store (ADR 0001). A legacy `.env` entry found on any
  `github-access` run is migrated to the token file and removed from `.env`.
- The retired `GITHUB_PACKAGES_TOKEN` name is no longer read as a token
  source; `status` and `clear packages` still detect and remove a stranded
  copy in a legacy `.env`.
- Project-level `.npmrc` files must never carry `_authToken`; auth lives only
  in user-level `~/.npmrc` (a project file would override it with an empty
  token → 401).

## Why credentials are not capability-gated

`capabilities:` in `bootstrap.conf.yml` gate **provisioning steps**
(`.requires` files), never runtime state. Credential breadth is a host-role
decision, so it lives in the conf's `github:` section (`packages_write`,
`source_rw`) — read by `bootstrap-access` to drive the walk
non-interactively. Neither key mints a token: flipping one and re-running the
walk validates the stored PAT against the new scope and prompts only for a
replacement paste when the stored token falls short. The `--write` / `--ci`
flags remain for ad-hoc use of `github-access` outside the walk.

## Key file locations

| Path | What |
|---|---|
| `user/init.d/30-scripts/scripts/{bootstrap-access,github-access}` | source of truth |
| `user/init.d/30-scripts/scripts/lib/access-common.sh` | shared helpers |
| `user/init.d/30-scripts/script-runners/*` | `~/.local/bin` wrappers |
| `~/scripts/…` | deployed copies |
| `~/.config/gh/broadminde-*.token` | stored PATs (0600) — the authoritative store |
| `~/.npmrc` | derived npm auth (0600), written by `98-npm-shared` |
| `~/infra/caddy/.env`, `acmedns.json` | caddy stage state |

## Open design question (parked for a dedicated session)

The current RW approach — one classic PAT widened with `write:packages` on
publish hosts, plus a separate `repo,workflow` classic PAT for source
automation — works but has known friction: classic PATs are account-wide and
long-lived, and scope upgrades happen by editing the token in place (same
string) or rotating it. The per-run decision prompts are resolved: the conf's
`github:` section (`packages_write` / `source_rw`) now drives the walk
non-interactively. Remaining alternatives worth exploring: fine-grained PATs
where supported (GHCR yes, npm registry no), or GitHub App installation
tokens for CI.
