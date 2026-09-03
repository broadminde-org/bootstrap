---
name: frontend-shared-access
description: >-
  Read-only git access to broadminde-org/frontend-shared through the dedicated
  github-frontend-shared SSH alias. USE FOR: cloning or updating the ee
  shared/frontend submodule, debugging frontend-shared permission errors, and
  questions about its deploy key or SSH routing. DO NOT USE FOR: publishing to
  GitHub Packages, changing frontend-shared, or general GitHub authentication.
---

# frontend-shared — Submodule Access

`broadminde-org/frontend-shared` is the private source repository for the
`ee` workspace path `shared/frontend`. The monorepo reads it through a
dedicated read-only deploy key and SSH alias. The published npm package is for
external consumers; `ee` does not need npm registry authentication.

## Routing

| Repo/URL | Resolves via | Identity |
|---|---|---|
| `git@github-frontend-shared:broadminde-org/frontend-shared.git` | Dedicated alias | `~/.ssh/frontend-shared-read` |
| `github.com/broadminde-org/frontend-shared` HTTPS URL | Exact Git rewrite | `github-frontend-shared` key |

## Rules

- Never use `github-ee` for `frontend-shared`.
- Never reuse the `ee` or `go-shared` deploy key.
- The deploy key is read-only; changes go through the repository's normal PR
  workflow.
- Do not add a broad `broadminde-org/*` rewrite for this repository.
- Do not add GitHub Packages tokens to `ee` for this submodule workflow.

## Verification

```bash
ssh -G github-frontend-shared | grep -E '^(hostname|identityfile|identitiesonly)'
git ls-remote git@github-frontend-shared:broadminde-org/frontend-shared.git HEAD
```

Provisioned by `bootstrap/user/init.d/99-go-shared`. The step also manages the
existing `go-shared` access path and must verify both repositories before it
reports success.
