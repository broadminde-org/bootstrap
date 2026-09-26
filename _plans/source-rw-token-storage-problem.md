# Source RW Token Storage Problem

> **Resolved 2026-09-18** — see `docs/adr/0001-github-pat-storage.md`. Both
> PATs now live in `~/.config/gh/broadminde-*.token` (0600); `.env` is no
> longer a token store, and legacy entries are migrated out on the next
> `github-access` run. This document is kept as the problem record.

## Finding

`github-access source-rw` stores `BROADMINDE_SOURCE_RW_TOKEN` only in the
bootstrap checkout's `.env` file:

```text
$BOOTSTRAP_ROOT/.env
```

On this host, that resolves to `/home/luke/bootstrap/.env`. The helper validates
the token and writes it there through `write_env_value`, with file mode `0600`.

Unlike the GitHub Packages token, the source RW token is not deployed to a
dedicated credential store, SSH configuration, service account, or other
runtime location. The script only prints guidance to pass it explicitly to CI
or commands as `GH_TOKEN` or `BROADMINDE_SOURCE_RW_TOKEN`.

## Why This Is a Problem

The source RW PAT is a broad credential with `repo` and `workflow` scopes. A
bootstrap checkout `.env` file is a poor exclusive source of truth for this
credential because:

- It couples source write access to the presence and location of the bootstrap
  repository.
- Any process or tooling that sources the repository `.env` can receive a
  broad write credential unintentionally.
- The token has no dedicated runtime ownership, rotation path, or service
  identity boundary.
- CI and automation cannot consume it unless each caller is separately wired
  to read or export the bootstrap `.env` value.
- The token is not integrated with the `gh` credential store, an OS keyring, or
  a CI secret manager.

The file is gitignored, but gitignore only prevents normal Git tracking. It
does not solve local filesystem exposure, accidental sourcing, backups,
process inheritance, or the broader question of where automation credentials
should live.

## Current Credential Split

| Credential | Current persistent location | Runtime use |
| --- | --- | --- |
| Packages PAT | `$BOOTSTRAP_ROOT/.env` and `~/.npmrc` | npm/GitHub Packages |
| Source RW PAT | `$BOOTSTRAP_ROOT/.env` only | Explicit `GH_TOKEN` or environment export |
| Read-only deploy keys | `~/.ssh/*-shared-read` | Git fetches from shared repositories |
| Operator `gh` login | GitHub CLI credential store/keyring | Interactive GitHub API and CLI use |

## Follow-Up Investigation

The next design should determine the authoritative owner and delivery
mechanism for source RW automation credentials. In particular, investigate:

1. Whether source RW operations should use the operator's existing `gh`
   identity, a dedicated GitHub App, or a dedicated machine/service identity.
2. Whether the host has an approved secret manager, OS keyring, CI secret store,
   or service-specific credential directory for this token.
3. Which processes actually need source RW access and whether they can receive
   short-lived or narrowly scoped credentials instead of a classic PAT.
4. How rotation, revocation, auditing, and access separation should work.
5. Whether `github-access source-rw` should stop writing the token to the
   bootstrap repository `.env` entirely.

No token value is included in this document.
