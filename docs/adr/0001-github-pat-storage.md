# ADR 0001: GitHub PAT storage outside the bootstrap checkout

- Status: accepted (2026-09-18)
- Deciders: luke
- Supersedes: the interim design documented in
  `source-rw-token-storage-problem.md` (repo root)

## Context

`github-access` manages two classic PATs: `BROADMINDE_PACKAGES_TOKEN`
(`read:packages`, plus `write:packages` on publish hosts) and
`BROADMINDE_SOURCE_RW_TOKEN` (`repo`, `workflow`, on CI/update hosts). Both
were stored only in the bootstrap checkout's `.env` (mode 0600, gitignored).

That was a poor exclusive store for broad credentials:

- it couples credential availability to the presence and location of the
  bootstrap checkout;
- anything that sources or archives the repo `.env` receives broad write
  credentials unintentionally;
- the tokens had no dedicated runtime ownership, rotation path, or audit
  boundary, and no automation consumed them from there anyway.

A consumer inventory (2026-09-18) confirmed nothing read the source-RW token
from `.env`: operator `gh` use carries its own identity, git pushes use SSH
keys, Renovate mints GitHub App installation tokens, Woodpecker pipelines
receive secrets via the Woodpecker secret store (operator-pasted), and the
local-backend agent fetches private modules with a read-only deploy key.

## Decision

1. **Authoritative storage for both PATs is a dedicated token file per
   credential under `~/.config/gh/`** (mode 0600, one token per file):
   - `~/.config/gh/broadminde-packages.token`
   - `~/.config/gh/broadminde-source-rw.token`

   `~/.config/gh` is gh's own credential directory; gh only ever manages
   `hosts.yml`/`config.yml` and never touches foreign files, so the token
   files are safe from `gh auth` operations. (True integration into gh's
   credential store is impossible: gh holds exactly one token per
   host+user, and both PATs belong to the same account as the operator
   login.)

2. **The bootstrap checkout `.env` is never a token store.** `github-access`
   no longer writes tokens there. A legacy `.env` entry found on any run is
   migrated — validated, written to the token file, then deleted from
   `.env`. `user/init.d/98-npm-shared` reads the packages token from the
   environment, then the token file, then (transitionally) legacy `.env`.

3. **CI receives the source-RW PAT by an operator pasting it into the CI
   secret store** (Woodpecker repo secrets, write-only) — the same delivery
   path Renovate's GitHub App PEM already uses. No host file needs to be
   readable by CI.

4. **`github-access clear packages|source-rw|--all`** removes the token
   file, any legacy `.env` entry, and — for packages — the managed lines in
   `~/.npmrc` (the file itself when it held nothing else). GitHub-side
   revocation stays manual.

5. **Classic PATs are kept** (rejected: retiring them). Upcoming CI
   automation needs them configured now. A later move to a dedicated GitHub
   App for push automation — per-repo permissions, 1h installation tokens,
   bot attribution — remains the desired end state, following the proven
   `renovator/scripts/mint-github-app-token.sh` pattern; it is a separate
   change.

## Consequences

- Token access no longer depends on the bootstrap checkout; `source-rw`,
  `status`, and `clear` work without it.
- The `workflow`-scope constraint applies only to PAT/OAuth pushes; SSH and
  GitHub App paths are unaffected.
- Rotation: create a new classic PAT in GitHub, run `github-access
  packages [--write]` / `source-rw`, paste it; the stored file is replaced
  after validation. For CI consumers, update the Woodpecker secret.
- Read-only hosts (`github.source_rw` unset/false) never hold the source-RW
  token at all.
