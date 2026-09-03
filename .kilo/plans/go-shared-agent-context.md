# Plan: go-shared Agent Context

## Goal

Give host-wide agents (Kilo CLI / Kilo Code) the context they need to work
safely with `broadminde-org/go-shared` module access, and bring go-shared's
own repo docs in line with the step-99 implementation.

## Background (verified state as of 2026-09-02)

- `user/init.d/99-go-shared/run.sh` provisions read-only deploy-key access to
  `broadminde-org/go-shared` via the SSH alias `github-go-shared`. It was
  recently cleaned: all `ee`/`ephemeral-engineering` handling was removed, a
  dedicated `ControlPath ~/.ssh/cm-go-shared-%r@%h:%p` was added to the
  generated host block, and the failure path now prints the public key inline.
  It has been run successfully on this host (key registered, ls-remote passes).
- Host Git identity model:
  - Manual/interactive git on this host authenticates with the user's
    forwarded Secretive key (macOS). Catch-all rewrite
    `url.git@github.com:.insteadof https://github.com/` routes plain HTTPS
    GitHub URLs to it. `Host github.com` in `~/.ssh/hosts.d/github` has
    `IdentitiesOnly no`.
  - `github-go-shared` uses `~/.ssh/go-shared-read` (read-only deploy key),
    `IdentitiesOnly yes`, dedicated `UserKnownHostsFile`, dedicated
    ControlPath.
  - `GOPRIVATE=github.com/broadminde-org/*` (shell profile + `~/.config/go/env`).
  - Stale ee-era rewrites remain in the live global gitconfig
    (`url.git@github-ee:broadminde-org/.insteadof` and the
    `ephemeral-engineering` one). They are inert (longest-match wins) and are
    intentionally left alone for now — do NOT remove them in this plan.
- The full access spec lives in `~/go-shared/ACCESS-MODEL.md`, but agents
  working in other repos never see it, and its §3 is now stale (still shows
  the org-wide unset + ee rewrite).
- Bootstrap convention (established by `60-caddy`): a skill documenting a
  provisioned feature lives with its step (`<step>/kilo/skills/`) and is
  deployed to `~/.kilo/skills/` via `sync_dir_preserve`, NOT via
  `37-kilo-settings`. Step 99 follows this pattern.
- Housekeeping: `code-skeptic copy.md` is a stray duplicate in both the
  skeleton and live config; the `37-kilo-settings/run.sh` header comment
  advertises a kilo.jsonc "instructions glob" that does not exist.

## Constraints

- Follow existing file/style conventions. Minimal diffs.
- Do NOT modify live `~/.ssh/*`, live gitconfig, or `~/.kilocode/`.
- Do NOT push or commit in `~/go-shared`; leave changes in the working tree
  for user review.
- Do NOT run the real step 99 against the live home; use the sandbox
  verification below.
- Do not re-add any `ee`/`ephemeral-engineering` configuration to step 99.

## Tasks

### 1. New skill: `user/init.d/99-go-shared/kilo/skills/go-shared-access/SKILL.md`

Model the format on `~/.kilo/skills/central-caddy/SKILL.md` (read it first).
YAML frontmatter: `name: go-shared-access`, and a `description` with explicit
USE FOR / DO NOT USE FOR triggers, e.g. "USE FOR: cloning or `go get` of
`github.com/broadminde-org/go-shared`, debugging `Permission denied
(publickey)` on broadminde-org Go modules, questions about the
github-go-shared alias or go-shared deploy key. DO NOT USE FOR: general
GitHub auth, other orgs' repos, or write access to go-shared (PRs use the
user's personal GitHub identity)."

Body sections:

1. **TL;DR routing table** — which URL resolves to which identity:

   | Repo/URL | Resolves via | Identity |
   |---|---|---|
   | `github.com/broadminde-org/go-shared` | `git@github-go-shared:…` rewrite | `~/.ssh/go-shared-read` (read-only deploy key) |
   | everything else on github.com | catch-all `git@github.com:` rewrite | forwarded Secretive key (user's personal identity) |

2. **Rules agents must not break**:
   - Never repoint `github-go-shared` to plain `github.com` or `github-ee`.
   - Never reuse the ee deploy key for go-shared.
   - Never add write access to the go-shared deploy key; go-shared changes go
     through PRs from the user's personal identity.
   - Do not modify global `url.*.insteadOf` entries other than the go-shared
     one; the go-shared rewrite is the most specific and wins by longest
     match.
   - `GOPRIVATE=github.com/broadminde-org/*` is intentional; do not widen or
     remove it.
3. **How it works** (brief): alias in `~/.ssh/hosts.d/github-go-shared.conf`
   (`IdentityFile`, `IdentitiesOnly yes`, dedicated `UserKnownHostsFile`
   `~/.ssh/known_hosts-go-shared`, dedicated ControlPath so a personal-key
   ControlMaster to github.com is never reused by the alias — that would
   silently authenticate as the user and mask a missing deploy-key
   registration). Provisioned by `bootstrap user/init.d/99-go-shared`.
4. **Verification commands**:
   ```bash
   ssh -G github-go-shared | grep -E '^(hostname|identityfile|identitiesonly)'
   git ls-remote git@github-go-shared:broadminde-org/go-shared.git HEAD
   ```
5. **Full spec**: `~/go-shared/ACCESS-MODEL.md` (access decision, key
   lifecycle, rotation, revocation).
6. **Key facts**: one deploy key per host, read-only, private key mode 0600,
   registered at https://github.com/broadminde-org/go-shared/settings/keys.

### 2. Wire deployment into `user/init.d/99-go-shared/run.sh`

- Immediately after sourcing `lib/common.sh` and the readonly declarations
  (before the key/known_hosts work), add a skill-deploy block mirroring
  60-caddy's "Step 0":

  ```bash
  # Deploy the go-shared-access agent skill (~/.kilo/skills/). Plain files with
  # no dependency on the deploy key, so a host whose key is not yet registered
  # still gets the context. sync_dir_preserve never deletes.
  sync_dir_preserve "$(dirname "$0")/kilo/skills" "$HOME/.kilo/skills"
  ```

  (Check the exact signature of `sync_dir_preserve` in
  `user/init.d/lib/common.sh` and copy 60-caddy's usage verbatim.)
- Update the step header comment to mention the skill deploy, as 60-caddy's
  header does.

### 3. Create `~/go-shared/AGENTS.md` (repo-local, NOT via bootstrap)

Bootstrap must never write into a git clone; this file is created directly in
the working tree and left uncommitted for the user to review/commit. Thin
contributor-facing context:

- Module path `github.com/broadminde-org/go-shared`; root module plus nested
  modules (`web`, `agent`, `llmclient`, `llmapi`, `ssh`); `go 1.26.4`;
  `go.work` present.
- README.md is the authority for package selection (two auth architectures;
  read it before adding imports).
- Validation: `gofmt -l .`, `go vet ./...`, `go test ./...` per module
  (respect go.work; use `GOWORK=off` when verifying versioned consumption).
- Access boundary: this clone authenticates with the user's personal GitHub
  identity (forwarded agent). The `github-go-shared` deploy key is read-only
  and exists only for module downloads on provisioned hosts — never use it
  for pushes. All changes land via PR per `ACCESS-MODEL.md` §6.
- Never commit private keys or credentials; the deploy key private material
  must never enter this repo.

### 4. Update `~/go-shared/ACCESS-MODEL.md` §3 (same repo, same uncommitted batch)

- Replace the three-command git-config snippet (org-wide unset + ee rewrite +
  go-shared rewrite) with only the go-shared rewrite:

  ```bash
  git config --global url."git@github-go-shared:broadminde-org/go-shared".insteadOf \
    https://github.com/broadminde-org/go-shared
  ```

  Add one sentence: the go-shared rewrite is the most specific `insteadOf`
  and wins by longest match, so no other rewrite needs to be removed.
- In the alias description, add the dedicated `ControlPath
  ~/.ssh/cm-go-shared-%r@%h:%p` requirement and its rationale (prevent a
  personal-key ControlMaster being reused by the alias).
- State that the host bootstrap implementation is
  `bootstrap user/init.d/99-go-shared/run.sh`, which configures go-shared
  only — `ee`/`ephemeral-engineering` are no longer Go repos and are not
  configured by that step.
- Update the document Status line: host configuration is now implemented by
  bootstrap step 99 (the migration-plan status for ee tree cleanup is
  unchanged).
- Do not otherwise restructure the document.

### 5. Bootstrap cleanups

- Delete `user/init.d/37-kilo-settings/_config/kilo/agents/code-skeptic copy.md`.
- Delete live `~/.config/kilo/agents/code-skeptic copy.md`.
- In `user/init.d/37-kilo-settings/run.sh`, fix the stale header comment for
  kilo.jsonc (line ~32): it currently claims an "instructions glob"; the file
  actually only carries permissions (`permission.bash: allow`). Make the
  comment match reality; do not add an instructions glob.

## Verification

1. `bash -n` and `shellcheck` clean on `user/init.d/99-go-shared/run.sh`.
2. Sandboxed step-99 run (temp HOME so live state is untouched):

   ```bash
   rm -rf /tmp/kilo/gs-test && mkdir -p /tmp/kilo/gs-test/.ssh
   printf 'Include ~/.ssh/hosts.d/*\nHost *\n    ServerAliveInterval 30\n' \
     > /tmp/kilo/gs-test/.ssh/config
   chmod 700 /tmp/kilo/gs-test/.ssh && chmod 600 /tmp/kilo/gs-test/.ssh/config
   HOME=/tmp/kilo/gs-test bash user/init.d/99-go-shared/run.sh
   ```

   Expected: skill lands at `/tmp/kilo/gs-test/.kilo/skills/go-shared-access/SKILL.md`;
   run proceeds through keygen/known_hosts/host config/git config and fails
   only at the final `git ls-remote` (sandbox key is unregistered) with the
   ACTION REQUIRED block printing the public key. Clean up `/tmp/kilo/gs-test`
   afterwards.
3. `grep -in 'ee\b\|ephemeral\|github-ee' user/init.d/99-go-shared/run.sh`
   returns nothing.
4. `git -C ~/go-shared status --short` shows only `AGENTS.md` (new) and
   `ACCESS-MODEL.md` (modified); nothing committed or pushed.
5. `git -C ~/bootstrap diff --stat` shows only: new skill file, step-99
   run.sh edits, deletion of the skeleton `code-skeptic copy.md`, and the
   37-kilo-settings comment fix.

## Out of scope

- Removing the stale ee-era rewrites from the live global gitconfig.
- The 7 remaining broken symlinks in `~/.kilocode/skills/`
  (async-python-patterns, design-an-interface, django-celery-expert,
  django-expert, fastapi-expert, python-mcp-server-generator,
  sqlalchemy-postgres).
- Reinstalling a Go skill set via `40-npx-skills`.
- The duplicate live `Host github-ee` block in `~/.ssh/config` vs
  `~/.ssh/hosts.d/github` (manual cleanup, previously reported).
