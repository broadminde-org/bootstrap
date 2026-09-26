# Handoff: Source RW token storage + `github-access clear`

> **Completed 2026-09-18.** Task 1 decision: both PATs live in
> `~/.config/gh/broadminde-*.token` (0600); `.env` is no longer a token store;
> legacy entries migrate out on any `github-access` run. Decision recorded in
> `docs/adr/0001-github-pat-storage.md`. Task 2 (`github-access clear
> packages|source-rw|--all`) implemented in the same pass. The task text below
> is kept as the record of the work.

Two tasks, **in order**. Task 1 is a design/investigation task that gates Task 2 —
the implementation of `clear` depends on where the source RW token authoritatively
lives after Task 1 is decided.

The parent workspace will be open alongside this repo, giving access to the
**Woodpecker (CI)** and **Renovate** configurations. Use them as primary evidence
for where automation secrets should be stored.

---

## Task 1 (FIRST): Resolve the source RW token storage problem

Read `source-rw-token-storage-problem.md` in this workspace root first — it is the
problem statement. Summary:

- `github-access source-rw` stores `BROADMINDE_SOURCE_RW_TOKEN` **only** in
  `/home/luke/bootstrap/.env` (mode 0600, gitignored). Unlike the packages PAT
  (which gets deployed to `~/.npmrc` by `user/init.d/98-npm-shared`), the source
  RW token has **no dedicated runtime location** — the script just prints "pass
  it as `GH_TOKEN` to CI".
- The doc argues a bootstrap checkout `.env` is a poor exclusive source of truth
  for a broad `repo` + `workflow` credential: couples write access to the
  bootstrap repo's presence, risks accidental sourcing/process inheritance, and
  has no ownership/rotation/audit story.
- The doc's open questions (verbatim from its Follow-Up Investigation):
  1. Should source RW ops use the operator's `gh` identity, a dedicated GitHub
     App, or a dedicated machine/service identity?
  2. Does the host have an approved secret manager / OS keyring / CI secret
     store / credential directory for this token?
  3. Which processes actually need source RW access, and can they use
     short-lived or narrowly-scoped credentials instead of a classic PAT?
  4. How should rotation, revocation, auditing, and access separation work?
  5. Should `github-access source-rw` stop writing to the bootstrap `.env`
     entirely?

### What to do

1. **Inventory the actual consumers.** Inspect the parent workspace's Woodpecker
   and Renovate configs (plus anything else in the parent that pushes to
   `broadminde-org/*` or touches `.github/workflows/`). For each consumer,
   determine: what credential it uses today, what scope it truly needs, and how
   it receives secrets (Woodpecker secret store? env file? mounted file?).
2. **Determine the authoritative owner and delivery mechanism.** Answer the
   doc's five questions against the real evidence found. Woodpecker's native
   secret store and Renovate's token mechanism are the prime candidates —
   check their docs/configs on disk, don't guess.
3. **Propose the design** and grill it with the user before implementing
   anything. Key decision points to surface explicitly:
   - Does `BROADMINDE_SOURCE_RW_TOKEN` stay in `.env` at all, or does `.env`
     become at most a bootstrap-time staging input?
   - Who owns rotation, and what is the rotation runbook?
   - Is a classic PAT even the right credential type (vs. GitHub App
     installation tokens)?
4. **Record the decision** as an ADR-style note (the repo has no ADR dir —
   propose location/format; `docs/` exists and `docs/codemap.md` is the
   architecture map).
5. Only after the user approves a direction: implement the `github-access
   source-rw` changes (and any step changes in `user/init.d/`) that deliver
   the token to its new home. Keep the validation logic
   (`validate_source_rw_token`, `check_source_rw_identity`) — it's correct and
   location-agnostic; only the storage/delivery tail changes.

---

## Task 2 (AFTER Task 1): Add `github-access clear`

`github-access` has no way to remove stored credentials — operators must
hand-edit `.env`. Add a `clear` subcommand:

```
github-access clear packages     # remove BROADMINDE_PACKAGES_TOKEN from .env + the npm artifact
github-access clear source-rw    # remove BROADMINDE_SOURCE_RW_TOKEN from wherever Task 1 put it
github-access clear --all        # both
```

**Important:** `clear source-rw` must remove the token from **all** locations
established by Task 1's design — not just `.env`. If Task 1 moves authoritative
storage to a CI secret store or credential directory, `clear` must remove it
there (and from `.env` if `.env` remains a staging location).

### Files and structure

- Source of truth: `user/init.d/30-scripts/scripts/github-access`
  (NOT `~/scripts/github-access` — that's the deployed copy).
- Deployment: `./user/init.sh 30-scripts` syncs `scripts/` → `~/scripts/` via
  `sync_dir_preserve`. Always edit source, then redeploy, then verify the
  deployed copy contains the change (`grep`).
- Shared helpers sourced from `lib/access-common.sh` (deployed at
  `~/scripts/lib/`): `log`, `ok`, `warn`, `fail`, `require_deploy_user`,
  `resolve_bootstrap_root`, `file_env_value`, `write_env_value`.
- Current commands dispatched in `main()`: `setup [--ci]`, `auth`,
  `deploy-keys`, `packages|npm [--write]`, `source-rw`, `status`, `help`.
- Key vars: `ENV_FILE="$BOOTSTRAP_ROOT/.env"`,
  `PACKAGES_TOKEN_VAR="BROADMINDE_PACKAGES_TOKEN"`,
  `SOURCE_RW_TOKEN_VAR="BROADMINDE_SOURCE_RW_TOKEN"`,
  `SOURCE_RW_REPOS=("broadminde-org/go-shared" "broadminde-org/frontend-shared")`.

### Implementation requirements

1. **Removing an env line**: no existing helper — `write_env_value` only
   adds/replaces. Add `delete_env_value <file> <name>` to
   `user/init.d/30-scripts/scripts/lib/access-common.sh`, same atomic pattern
   as `write_env_value` (mktemp in same dir, `grep -vE "^${name}="`,
   chmod 600, mv). Succeeds silently when the entry or file doesn't exist.
2. **packages clear** must also remove the artifact `~/.npmrc` (written by
   `user/init.d/98-npm-shared`). First read `user/init.d/98-npm-shared/run.sh`
   to see exactly what it writes — if `~/.npmrc` contains only the
   `npm.pkg.github.com` auth, delete the file; if it's shared config, delete
   only the token line(s) with sed and report which you did.
3. **`status`**: no change needed; it already reports present/missing.
4. Update `usage()` (add `clear` under Commands) and the header comment's
   credential-model section.
5. After clearing, print what was removed and warn that re-running
   98-npm-shared (or the Task-1 delivery step) will fail/skip until a new
   token is set.
6. Style: `set -euo pipefail` compatible, shellcheck-clean,
   `reject_extra_args`-style validation, `exit 2` on bad usage. **No
   confirmation prompts** — the user hates interactive confirmation for
   obvious actions (see the earlier `confirm_store_token` removal). Just do
   it and report.
7. Do NOT add GitHub-side PAT revocation (out of scope; the user regenerates
   tokens manually).

### Verification

- `shellcheck` clean on both edited files.
- `./user/init.sh 30-scripts` deploys; `grep` the deployed
  `~/scripts/github-access` and `~/scripts/lib/access-common.sh`.
- Functional test WITHOUT touching real credentials: `BOOTSTRAP_ROOT` is
  honored, so point it at a scratch dir (`TMPDIR="$PWD/.tmp"` per workspace
  rules; `mkdir -p .tmp` first) — e.g. `BOOTSTRAP_ROOT=$PWD/.tmp/fake` with a
  fake `.env`; run `github-access clear packages`; verify the line is gone
  and other lines survive. Note `require_bootstrap` needs
  `user/init.sh` under BOOTSTRAP_ROOT — check what `clear` actually needs and
  don't require the full checkout for a pure `.env` edit (only
  `run_user_step` paths need the runner; design accordingly).
- Clean up `.tmp/` scratch when done (a global permission rule denies `rm` in
  bash — if blocked, leave the files and say so).

---

## Behavior notes from prior sessions (already fixed, don't regress)

- `token_scopes` uses `tolower()`, not gawk `IGNORECASE` (host awk is
  **mawk**, which silently ignores `IGNORECASE`; `gh` prints headers in
  canonical case like `X-Oauth-Scopes:`).
- `validate_package_token` accepts `write:packages` as implying read —
  GitHub omits implied scopes from `X-Oauth-Scopes` (verified live:
  a `repo, write:packages` token pulls packages fine).
- No store-confirmation prompts — tokens are stored unconditionally after
  validation.
- `configure_source_rw` calls `check_source_rw_identity` before prompting
  (warns, doesn't abort, when the gh identity lacks push; aborts only when gh
  is unauthenticated).
- gh identity on this host: `Luke-Williams9`, verified `push=true` on both
  source repos.
- Both access scripts live in the same `scripts/` dir; `bootstrap-access`
  delegates GitHub work to `github-access` — if `clear` should be reachable
  via `bootstrap-access`, note it, but the natural surface is
  `github-access clear`.

When done with both tasks: summarize the storage decision (with the ADR
location), the `clear` implementation, functional test results, and confirm
deployed copies are updated. Do not git-commit anything.
