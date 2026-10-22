# AGENTS.md — bootstrap

Host provisioning for fresh Debian/Ubuntu cloud VPSes. Two tiers, each an
`init.sh` + `init.d/` numbered-step system:

| Tier | Runs as | Runner | Purpose |
|------|---------|--------|---------|
| root | root (via `sudo`) | `./init.sh` | Host provisioning: apt, packages, deploy user, groups, sudo, SSH hardening, ufw, fail2ban, Docker, KVM, CrowdSec |
| user | deploy user (NOT root) | `./user/init.sh` | Per-user tooling into `$HOME`: uv/Python, Go, Node, kilo CLI, direnv, scripts, central Caddy |

Privilege separation is strict and enforced: the root runner refuses non-root,
the user runner refuses root. A step that needs root belongs in `init.d/`;
a step that touches `$HOME` belongs in `user/init.d/`. Never mix.

Chat LLM sessions must never execute privilege escalation, including `sudo`
or an equivalent direct or indirect mechanism. Root-tier commands in this
document are manual operator commands. When root access is required, give the
user exact commands to run, their working directory, expected result, and
non-privileged verification steps where possible.

## Step format (`init.d/`)

```
init.d/
  NN-name.sh            # flat-file step (rare — only for single self-contained scripts)
  NN-name/              # directory step (the norm)
    run.sh              # entry point — REQUIRED
    .requires           # optional: one capability per line (see below)
    packages.txt        # supporting files: templates, lists, snippets, assets
    ...
  NN-name.disabled/     # .disabled suffix → always skipped by the runner
  lib/                  # shared helpers — NOT a step (no numeric prefix)
    conf.sh             #   unified config reader (both tiers source this)
    common.sh           #   root check + DEBIAN_FRONTEND/NEEDRESTART exports
                        #   + env_file_value (parsed repo-root .env reads)
    env.sh              #   EE_ROOT + toolchain version pins
    user.sh             #   require_deploy_user: DEPLOY_USER resolution for
                        #   steps that act on the deploy account
```

Rules:

- **Numeric prefix `NN-`** determines execution order. Leave gaps (01, 05, 10,
  20…) for future insertion.
- Directory steps run with `cd` into their own directory — reference
  supporting files via `"$(dirname "$0")/..."` or relative paths.
- Every step: `#!/usr/bin/env bash`, `set -euo pipefail`, **idempotent**,
  **non-interactive**. Root-tier steps source `../lib/common.sh` (enforces
  root + apt non-interactive); user-tier steps source `../lib/common.sh`
  (enforces non-root + loads config + exports version pins).
- Fail loudly: non-zero exit on error. The root runner stops at the first
  failed step; the user runner collects failures and reports them at the end.

## `.requires` and `bootstrap.conf.yml`

Capabilities gate **provisioning, not runtime state** — disabling a
capability stops its steps from running but never uninstalls anything.

- A step with **no `.requires`** always runs.
- A step with `.requires` (one capability name per line, `#` comments and
  blank lines OK) runs only when **every** listed capability is `true`.
  For multiple entries, put prerequisites first and the selecting feature
  last (`docker`, then `caddy`); an enabled feature with a missing prerequisite
  fails preflight.
- Capabilities are defined in the `capabilities:` section of the conf file:

```yaml
# bootstrap.conf.yml  (gitignored — copy from example.bootstrap.conf.yml)
capabilities:
  docker: true      # 50-docker, 55-lazydocker
  caddy: true       # user/60-caddy (also requires docker → .requires lists both)
  kvm: false        # 57-kvm
  dev: false        # 06-playwright-deps + user/25-go, user/97-gh-auth-instructions,
                    # user/98-npm-shared, user/99-go-shared
  public: false     # 54-crowdsec (internet-facing hosts only)
```

- **Unlisted capabilities are disabled** (allowlist gating). Host confs may
  omit disabled features; `example.bootstrap.conf.yml` is the canonical list of
  valid names. Both runners fail before any step on a missing config or
  `capabilities:` block, malformed/unknown/duplicate capability entries, or
  unknown active `.requires` names. Other config sections remain optional.
- Config resolution: `<hostname>.conf.yml` (repo root) takes precedence over
  `bootstrap.conf.yml`. Both runners resolve the file the same way and export
  it as `BOOTSTRAP_CONFIG_FILE`, so step subshells that re-source `conf.sh`
  evaluate the identical capability set.

Current capability map (verify against `*/.requires` files before editing):

| Capability | Gated steps |
|---|---|
| `docker` | `init.d/50-docker`, `init.d/55-lazydocker`, `user/init.d/60-caddy` |
| `caddy` | `user/init.d/60-caddy` (with `docker`) |
| `kvm` | `init.d/57-kvm` |
| `dev` | `init.d/06-playwright-deps`, `user/init.d/25-go`, `user/init.d/97-gh-auth-instructions`, `user/init.d/98-npm-shared`, `user/init.d/99-go-shared` |
| `public` | `init.d/54-crowdsec` |
| `woodpecker` | RETIRED — `init.d/45-woodpecker-local.disabled`; the local backend agent runs as the deploy user via a user systemd unit provisioned by the ci repo's `init.d/20-agent-local` |

The conf file also has `versions:` (toolchain pins: uv, python, kilo, go,
node, caddy — `"latest"` or exact versions; partial versions for go/node), `skills:` (npx skills
agent targets), `caddy:` (wildcard zone config + `acme_email` for the ACME
account, written to `~/infra/caddy/.env` by user/60-caddy), `github:` (host credential
role for the access walk), and `portal:` (`mode: dev | image`, published to
`central.json` for app deployment steps).
See `example.bootstrap.conf.yml` for the annotated template.

## Configuration & secrets

- Project-specific parameters come from **`.env`** at the repo root
  (gitignored). Nothing host-specific is
  hardcoded in steps.
- **`.env` never stores tokens or PATs.** The GitHub classic PATs live in
  `~/.config/gh/broadminde-*.token` (0600), managed by `github-access` — see
  `docs/adr/0001-github-pat-storage.md`.
- Required bootstrap-time parameters come from the environment or the
  repo-root `.env` (parsed via `env_file_value` in `init.d/lib/common.sh` —
  never shell-sourced). Putting them in `.env` instead of on the command
  line keeps secrets like `BOOTSTRAP_PASSWORD` out of the root shell
  history.
- No step currently generates host secret files; if one ever does, generate
  it in-step, write it outside the repo or under a gitignored `secrets/`
  (0700/0600), and never commit it.

### Shared project scripts

The shared `dev` and `build` commands source a project's root `.env` as trusted
Bash. Docker Compose reads `.env` using dotenv interpolation rules instead;
Compose values must not rely on Bash expansion, command substitution, or other
shell syntax. Keep shared values in syntax accepted by both consumers. `stack`
must not introduce another incompatible `.env` parser. Never print secrets or
copy secret values into logs, generated reports, or other result artifacts.
In `build`, explicit caller environment wins over `.env` for the `IMAGE_*`
family (`IMAGE_REGISTRY`, `IMAGE_NAME`, `IMAGE_TAG`, `IMAGE_ALIAS_TAGS`), so a
throwaway-registry test can override `IMAGE_REGISTRY` without editing `.env`.

The shared script configuration variables below are optional. Unset values
retain the pre-migration behavior; examples are illustrative and belong in a
project's local `.env` (not this repository):

| Variable | Default and behavior | Example |
|---|---|---|
| `FRONTEND_DEV_HOST` | `::`; dual-stack Vite bind default (pre-existing behavior) | `127.0.0.1` |
| `FRONTEND_PORT` | Unset; Vite auto-selects a port and shared `dev` parses/exports it. When set, Vite uses that strict port. | `5173` |
| `FRONTEND_HMR_HOST` | Unset; preserves the project's existing HMR behavior | `portal.dev.example.net` |
| `FRONTEND_HMR_PROTOCOL` | Unset; preserves the project's existing HMR behavior | `wss` |
| `FRONTEND_HMR_CLIENT_PORT` | Unset; preserves the project's existing HMR behavior | `443` |
| `DEV_CADDY_HOST_PREFIX` | Unset; no central-Caddy discovery. When set, derives `FRONTEND_HMR_HOST` from `central.json` unless the host is explicit. | `portal.dev` |
| `CI_TEST_GO_DIR` | `.`; root-level Go detection | `backend` |
| `CI_TEST_NODE_DIR` | `.`; root-level Node detection | `frontend` |
| `CI_TEST_PYTHON_DIR` | `.`; root-level Python detection | `python` |
| `CI_TEST_NODE_CHECK_SCRIPT` | `check`; default Node check script | `lint` |
| `CI_TEST_NODE_BUILD_SCRIPT` | `build`; default Node build script | `build:ci` |
| `CI_TEST_NODE_E2E_SCRIPT` | `test:e2e`; default Node E2E script | `test:browser` |
| `BUILD_SWAG_VERSION` | Unset; preserves existing Swagger executable selection | `v1.16.4` |
| `BUILD_SWAG_DIR` | `backend`; Swagger working directory | `api` |
| `BUILD_SWAG_MAIN` | `main.go`; Swagger entry point | `cmd/server.go` |
| `BUILD_SWAG_OUTPUT` | `docs/swagger`; generated output directory | `api/openapi` |
| `BUILD_SWAG_PARSE_DEPENDENCY` | `true`; preserves existing dependency parsing | `false` |
| `BUILD_SWAG_PARSE_INTERNAL` | `true`; preserves existing internal parsing | `false` |
| `BUILD_SWAG_REQUIRED_PATHS` | Empty; no additional required path checks. Separate multiple exact paths with commas. | `/api/health,/api/config` |
| `BUILD_GENERATE_STRICT` | `false`; generation failures retain compatibility behavior | `true` |
| `IMAGE_ALIAS_TAGS` | Empty; no extra image aliases. Separate aliases with commas. | `main,stable` |

`stack config` prints Docker Compose's effective configuration using the
resolved project files and profiles, and accepts Compose config flags. Treat
its output as potentially sensitive because Compose interpolation can include
secret values; do not capture or publish it in result artifacts.

## Runner CLI (both tiers, identical)

```bash
./init.sh              # all steps in numeric order
./init.sh --from 25    # step 25 onward
./init.sh 25           # only step 25   (also accepts "50-docker")
./init.sh --help
```

Selector semantics: numbers are compared numerically (`5` matches `05-…`);
a bare selector that matches no step is a hard error (a typo must never
become a full run or a silent no-op), as is any unrecognized argument or
a missing/non-numeric `--from` operand.

## Adding a new step

1. Pick the next free number; leave gaps.
2. Use the **directory format** (`NN-name/run.sh`) as soon as the step needs
   any supporting file — flat files only for truly self-contained scripts.
3. Write it idempotent and non-interactive; `set -euo pipefail`; fail loudly.
4. Root tier → `init.d/`, user tier → `user/init.d/`. If it needs root it's
   root-tier; if it touches `$HOME` it's user-tier. No exceptions.
5. Read parameters from the environment or repo-root `.env` (parsed via
   `env_file_value`); steps acting on the deploy account resolve it via
   `require_deploy_user` from `init.d/lib/user.sh`, never raw `SUDO_USER`.
6. Add `.requires` only if the step depends on an optional capability; add
   the capability flag to `example.bootstrap.conf.yml`, this file's table,
   **and every host conf** — an unlisted capability is disabled, so a new
   capability activates nowhere until each host opts in.

## Testing

No general automated test suite exists; individual steps may carry focused
static checks. Verify provisioning behavior on a disposable VM. Every step
must be safe to re-run. The operator manually tests both selectors:

```bash
sudo ./init.sh 50-docker     # single step
sudo ./init.sh --from 50     # resume from a point
```

## Conventions

- Steps and libs carry `shellcheck` annotations; keep them clean.
- Compare-before-write for any managed file (sudoers, profile blocks,
  Caddyfile); validate before activating (`visudo -c`, `sshd -t`).
- Supporting data files (`packages.txt`, `groups.txt`, `commands.txt`) are
  one-entry-per-line with `#` comments — prefer editing the data file over
  editing the script.
- The user tier's `lib/common.sh` provides `sync_dir_preserve()` for
  deploying file trees into `$HOME` without deleting user extras.
- `README.md` documents the system for humans; `docs/codemap.md` is a deeper
  architecture map. Keep both in sync when adding/removing steps or
  capabilities.
