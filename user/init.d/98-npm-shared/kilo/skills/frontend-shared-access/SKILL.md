---
name: frontend-shared-access
description: >-
  Read-only access to broadminde-org/frontend-shared source through the
  github-frontend-shared SSH alias and to the published @broadminde-org/frontend
  npm package through the user-level GitHub Packages registry configuration. USE
  FOR: cloning or updating the ee shared/frontend submodule, installing or
  debugging @broadminde-org/frontend, frontend-shared permission errors, and
  questions about its deploy key, npm auth, or routing. DO NOT USE FOR: changing
  frontend-shared, adding project-level package tokens, or general GitHub auth.
---

# frontend-shared — Source and Package Access

`broadminde-org/frontend-shared` has two read-only consumption paths:

- The `ee` workspace path `shared/frontend` reads the private source repository
  through a dedicated SSH deploy key and alias.
- External consumers install the published `@broadminde-org/frontend` package
  from GitHub Packages using the user-level `~/.npmrc` managed by step 98.

## Source routing

| Repo/URL | Resolves via | Identity |
|---|---|---|
| `git@github-frontend-shared:broadminde-org/frontend-shared.git` | Dedicated alias | `~/.ssh/frontend-shared-read` |
| `github.com/broadminde-org/frontend-shared` HTTPS URL | Exact Git rewrite | `github-frontend-shared` key |

## Package routing

| Package | Registry | Auth |
|---|---|---|
| `@broadminde-org/frontend` | `https://npm.pkg.github.com` | User-level `~/.npmrc`, provisioned by `98-npm-shared` |

Use `npm view @broadminde-org/frontend version` with no token environment
variable to verify the host-level configuration. Do not add
`_authToken=${BROADMINDE_PACKAGES_TOKEN}` to a project `.npmrc`; project-level auth
can override the working user configuration with an empty token.

The token is a classic PAT with `read:packages` on consume-only hosts and
`write:packages` on publish hosts. The preferred setup path is
`~/scripts/github-access packages [--write]`, which prints the token-creation
URL, stores the token in `~/.config/gh/broadminde-packages.token` (mode 0600),
and runs step 98. Step 98 still deploys this skill when the token is absent
but skips the npm configuration — if `~/.npmrc` has no `_authToken` line, run
the helper and re-run `user/init.sh 98`. A 401 from the verify command means
the PAT lacks `read:packages` or the package is not published.

## Rules

- Never use `github-ee` for `frontend-shared`. A broad
  `git@github-ee:broadminde-org/` rewrite exists for the org's other repos;
  only the exact `frontend-shared` rewrite wins over it by longest-match
  precedence — never delete the exact rewrite.
- Never reuse the `ee` or `go-shared` deploy key.
- Both the deploy key and package token are read-only; changes go through the
  repository's normal PR or publishing workflow.
- Do not add a broad `broadminde-org/*` Git rewrite for this repository.
- Do not add GitHub Packages tokens to `ee` project files for this workflow.

## Verification

```bash
ssh -G github-frontend-shared | grep -E '^(hostname|identityfile|identitiesonly)'
git ls-remote git@github-frontend-shared:broadminde-org/frontend-shared.git HEAD
npm view @broadminde-org/frontend version
```

The SSH source path is provisioned by `bootstrap/user/init.d/99-go-shared`.
The package path and this skill are deployed by
`bootstrap/user/init.d/98-npm-shared`.
