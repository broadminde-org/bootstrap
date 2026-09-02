---
name: go-shared-access
description: >-
  Read-only access to the private broadminde-org/go-shared Go module on this
  host via the github-go-shared SSH deploy-key alias. USE FOR: cloning or
  `go get` of github.com/broadminde-org/go-shared, debugging `Permission
  denied (publickey)` on broadminde-org Go modules, questions about the
  github-go-shared alias or the go-shared deploy key. DO NOT USE FOR: general
  GitHub auth, other organizations' repos, or write access to go-shared (PRs
  use the user's personal GitHub identity).
---

# go-shared — Module Access

`github.com/broadminde-org/go-shared` is a private Go module consumed by
`ee` apps. On this host it is fetched read-only through a dedicated deploy-key
SSH alias; every other GitHub repo uses the user's personal identity.

## TL;DR routing table

| Repo/URL | Resolves via | Identity |
|---|---|---|
| `github.com/broadminde-org/go-shared` | `git@github-go-shared:…` rewrite | `~/.ssh/go-shared-read` (read-only deploy key) |
| everything else on github.com | catch-all `git@github.com:` rewrite | forwarded Secretive key (user's personal identity) |

## Rules agents must not break

- Never repoint `github-go-shared` to plain `github.com` or `github-ee`.
- Never reuse the ee deploy key for go-shared.
- Never add write access to the go-shared deploy key; go-shared changes go
  through PRs from the user's personal identity.
- Do not modify global `url.*.insteadOf` entries other than the go-shared
  one; the go-shared rewrite is the most specific and wins by longest match.
- `GOPRIVATE=github.com/broadminde-org/*` is intentional; do not widen or
  remove it.

## How it works

The alias is defined in `~/.ssh/hosts.d/github-go-shared.conf` with the
dedicated key, `IdentitiesOnly yes`, a dedicated `UserKnownHostsFile`
(`~/.ssh/known_hosts-go-shared`), and a dedicated ControlPath. The distinct
ControlPath matters: if the alias shared the plain `github.com` ControlPath,
a personal-key ControlMaster could be reused by the alias, silently
authenticating as the user and masking a missing deploy-key registration.
Provisioned by `bootstrap user/init.d/99-go-shared`.

## Verification

```bash
ssh -G github-go-shared | grep -E '^(hostname|identityfile|identitiesonly)'
git ls-remote git@github-go-shared:broadminde-org/go-shared.git HEAD
```

## Full spec

`~/go-shared/ACCESS-MODEL.md` — access decision, key lifecycle, rotation,
and revocation.

## Key facts

- One deploy key per host.
- Read-only (write access disabled).
- Private key mode `0600`.
- Registered at https://github.com/broadminde-org/go-shared/settings/keys.
