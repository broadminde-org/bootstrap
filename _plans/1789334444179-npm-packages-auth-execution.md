# Plan — Provision GitHub Packages npm auth via bootstrap user init step

**Executor:** GPT 5.6 Luna. **Workspace:** `~/bootstrap` (this repo), as user `luke` on broadminde1 (linux). Host-level user tooling — do not touch ee, portal, go-shared, or frontend-shared.
**Supersedes:** `~/bootstrap/1789334444179-npm-packages-auth-handoff.md` (all open items resolved below against live host state on 2026-09-14).
**Review fixes applied (2026-09-14):** verification 5 outer-shell PATH capture; nvm fallback for non-interactive runs; anchored `authToken` grep; `$HOME`-local `mktemp` (true atomic `mv`); leak-proof token grep; script-relative `.env`; `${VAR:-}` under `set -u`; README tree confirmed as the docs target.

## Resolved decisions (no open questions — execute as written)

| Item | Decision | Basis |
|---|---|---|
| Step placement | **New step** `user/init.d/98-npm-shared.sh` (flat file) | `99-go-shared` is exclusively SSH/git deploy-key wiring (verified by reading it); npm auth shares no machinery. 98 runs at the end of user provisioning so missing-token instructions are shown last. |
| Token source | **Repo-root `.env`** (`~/bootstrap/.env` on this host), resolved script-relative by the step (`$(dirname "$0")/../../.env`) and sourced by the step itself. Ship `.env.example` + gitignore entry. | No root `.env` exists today (verified); nothing sources one. The step must source the file itself to work non-interactively under `init.sh`. Script-relative resolution survives a relocated clone (init-d skill: ".env at the project root"). |
| PAT | **User creates a fine-grained PAT upfront** (Prerequisite). The existing `gh` PAT is insufficient. | Verified: `GET /user/packages?package_type=npm` and `GET /orgs/broadminde-org/packages?package_type=npm` both return **403** with the current `gh auth token`. (The `package_type` query param is required — without it the endpoints return 422, not 403.) |
| Auth mechanism | User-level `~/.npmrc`, exactly two managed keys, `chmod 600` | Per handoff; correct. Project `.npmrc` files stay registry-mapping-only (portal plan already aligned). |

## Context

`~/portal` consumes `@broadminde-org/frontend` from GitHub Packages (`npm.pkg.github.com`) as an external consumer. No npm auth exists on this host (`~/.npmrc` absent — verified). ee's sancus/fintek install the same package with `workspaces=false` and no auth — a user-level token repairs them too.

## Prerequisite (user action BEFORE the step can pass)

The user must create a **fine-grained GitHub PAT** with **Packages: read** on the `broadminde-org` organization and place it in `~/bootstrap/.env`:

```
GITHUB_PACKAGES_TOKEN=github_pat_...
```

If the step runs without it, it prints loud skip instructions and exits 0 (does not break full bootstrap runs). The executor must still implement and test everything else; final verification (step 6 below) requires the real token.

## Implementation

### 1. `~/bootstrap/.gitignore`

Add under the `# Config` section:

```
.env
```

### 2. `~/bootstrap/.env.example` (new file)

```
# GitHub Packages npm auth for @broadminde-org/* (read by user/init.d/98-npm-shared.sh)
# Fine-grained PAT with Packages: read on the broadminde-org organization.
# Create at: https://github.com/settings/personal-access-tokens
# GITHUB_PACKAGES_TOKEN=github_pat_...
```

### 3. `user/init.d/98-npm-shared.sh` (new flat-file step)

Contract, in order:

1. `#!/usr/bin/env bash`, `set -euo pipefail`. Source `$(dirname "$0")/lib/common.sh` (non-root guard + conf load).
2. `umask 077` for the remainder; never `set -x`; never echo the token.
3. **Load token:** resolve the repo root script-relative (`REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"` — equals `~/bootstrap` on this host). If `$REPO_ROOT/.env` exists, source it (`set -a; . ...; set +a` guard not needed — single var; source in a subshell-free way but do not re-export). Test with `${GITHUB_PACKAGES_TOKEN:-}` — a bare `$GITHUB_PACKAGES_TOKEN` reference aborts under `set -u`. If unset/empty after sourcing: print the loud skip block (what the step does, how to create the PAT at `https://github.com/settings/personal-access-tokens` with Packages: read on broadminde-org, where to put it — `~/bootstrap/.env`) and `exit 0`.
4. **Prereq check:** if `command -v npm` fails and `$HOME/.nvm/nvm.sh` exists, source it with `--no-use` and run `nvm use default` first — nvm only puts npm on PATH via `~/.bashrc` (interactive shells), so `ssh host '~/bootstrap/user/init.sh 98'` and cron runs would otherwise exit 1 with a misleading message. Then `command -v npm` or exit 1 with "run 35-node first".
5. **Manage `~/.npmrc`:** create if absent. Idempotent line-based upsert of exactly these two keys; preserve all other existing lines; do not duplicate:
   - `@broadminde-org:registry=https://npm.pkg.github.com`
   - `//npm.pkg.github.com/:_authToken=${GITHUB_PACKAGES_TOKEN}` (expanded value)
   Implementation: `tmp="$(mktemp "$HOME/.npmrc.XXXXXX")"` and `trap 'rm -f "$tmp"' EXIT` (temp in `$HOME`, not `/tmp` — `/tmp` is tmpfs on this host, so a `/tmp`→`$HOME` `mv` is copy+unlink, not atomic). Read the existing file line-by-line into the temp (skip lines matching the two exact key prefixes), append the two canonical lines, `chmod 600` the temp. If `cmp -s "$tmp" ~/.npmrc` succeeds and existing perms are already `600`, delete the temp and touch nothing (clean no-op for idempotency, mtime unchanged); otherwise `mv` over `~/.npmrc`.
6. **Verify (fail loudly):**
   - `npm view @broadminde-org/frontend version` prints a version. On failure: print "PAT lacks Packages: read on broadminde-org, or the package is not published — fix `~/bootstrap/.env` and re-run" and `exit 1`.
   - Env-independence: `env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/local/bin:$(dirname "$(command -v npm)")" npm view @broadminde-org/frontend version` must succeed. (Include npm's own dir in PATH because npm is nvm-installed, not in `/usr/bin`.)
   - `grep -cF '//npm.pkg.github.com/:_authToken=' ~/.npmrc` equals `1` (anchored to the managed key — a future second-registry token in `~/.npmrc` must not fail this check); `stat -c %a ~/.npmrc` equals `600`. Else `exit 1`.
7. Success line: `npm auth for @broadminde-org/* configured in ~/.npmrc and verified.`

### 4. README touch-up (required — the list exists)

`~/bootstrap/README.md` contains the user `init.d/` step tree, including `98-npm-shared.sh` near the end of provisioning.

## Verification (run manually after implementing)

1. `bash -n user/init.d/98-npm-shared.sh` and `shellcheck` if available.
2. **Skip path:** with no `.env` (or token empty), run `user/init.sh 98` → prints skip instructions, exit 0.
3. **Real path:** with token in `.env`, run `user/init.sh 98` → exit 0, prints success line.
4. **Idempotency:** run `user/init.sh 98` again → clean no-op, exit 0, `~/.npmrc` mtime unchanged.
5. Env-independence, with the npm dir captured in the **outer** shell (nvm's npm is invisible inside the stripped env — `$(command -v npm)` evaluated in there fails):
   ```
   NPMDIR="$(dirname "$(command -v npm)")"
   env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/local/bin:$NPMDIR" npm view @broadminde-org/frontend version
   ```
   Prints a version.
6. `grep -cF '//npm.pkg.github.com/:_authToken=' ~/.npmrc` → `1`; `stat -c %a ~/.npmrc` → `600`.
7. `git status` in `~/bootstrap` → `.env` not listed (ignored); no token in any tracked file. Run it so the token can never be printed:
   ```
   tok="$(grep '^GITHUB_PACKAGES_TOKEN=' .env | cut -d= -f2-)"
   if [[ -n "$tok" ]] && ! git grep -qF "$tok" -- . ':(exclude).env'; then echo PASS; else echo FAIL; fi
   ```
   (`git grep -q` suppresses match output; `cut -d= -f2-` keeps any `=` in the token; empty token → FAIL instead of `grep -F ""` matching everything.)

## Acceptance criteria

- [ ] `user/init.sh 98` runs non-interactively, idempotent, `set -euo pipefail`
- [ ] Skip path exits 0 with instructions when token absent; verification failure exits non-zero when token present but invalid
- [ ] `npm view @broadminde-org/frontend version` works in a fresh env as user luke
- [ ] `.env.example` documents `GITHUB_PACKAGES_TOKEN`; `.env` gitignored
- [ ] README.md user `init.d/` tree includes `98-npm-shared.sh`
- [ ] Token never in stdout, logs, or any git-tracked file; `~/.npmrc` is 600
- [ ] Final report states: step `98-npm-shared.sh` created, and that the pre-existing gh PAT was verified insufficient (403) so a new PAT is required

## References

- init-d skill: `/home/luke/.kilo/skills/init-d/SKILL.md`
- Existing step for house style: `~/bootstrap/user/init.d/99-go-shared/run.sh`
- Consumer plan (do not modify): `/home/luke/bootstrap/1789334444179-portal-web-shell-standalone.md`
- Package: `@broadminde-org/frontend` v2.0.0, `publishConfig.registry=https://npm.pkg.github.com` (`/home/luke/ee/shared/frontend/package.json`)
