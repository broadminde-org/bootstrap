# `ee` to `go-shared` Migration Access Model

Status: host configuration is now implemented by bootstrap step 99
(`user/init.d/99-go-shared`); the `ee` legacy-tree cleanup remains a migration
plan awaiting operator approval.

Scope: migrate the Go shared-library consumption path from the locally hosted
`ee/shared/backend` tree to the private `broadminde-org/go-shared` repository.

Out of scope: Woodpecker CI, Renovate, automated writes, GitHub Apps, and the
future frontend/Python shared repositories. Those observations are preserved
in `/home/luke/ci/ACCESS-OBSERVATIONS.md`.

## 1. Current migration state

- `go-shared` is private, has default branch `main`, and publishes the module
  paths under `github.com/broadminde-org/go-shared`.
- The repository contains a root module plus nested modules including `web`,
  `agent`, `llmclient`, `llmapi`, and `ssh`.
- `ee/go.work` no longer includes `shared/backend`; it contains the application
  modules only.
- Current `ee` application code already imports
  `github.com/broadminde-org/go-shared` packages. The migration commit history
  records removal of `shared/backend` from the workspace and migration of the
  remaining `sshterm-demo` consumer.
- The old `ee/shared/backend` tree remains in the checkout. Remaining local
  imports are concentrated in legacy shared code, tests, historical documents,
  and tooling references; they must be classified before deletion. Packages
  with no equivalent in `go-shared` must be deliberately retained in `ee` or
  migrated as a separate project; they must not be deleted just to make the
  import search pass.
- `ee` already uses `GOPRIVATE=github.com/broadminde-org/*`, which is the right
  private-module scope for this repository.
- On `broadminde1`, the broad `github-ee` Git rewrite currently routes all
  `github.com/broadminde-org/*` fetches through the `ee` deploy key. That key
  cannot read `go-shared` and is the cause of local module-resolution failures.

## 2. Access decision

Use one dedicated **read-only SSH deploy key for the development-host runtime**
that needs to download `go-shared`.

| Setting | Value |
|---|---|
| Repository | `broadminde-org/go-shared` |
| Permission | Read-only deploy key; leave write access disabled |
| Consumer | The local/headless development user running `ee` tooling |
| Private key | Protected runtime-user SSH directory, mode `0600` |
| Git identity | A repository-specific `github-go-shared` SSH alias |
| Write path | Human PR and merge through GitHub; not this key |

This key is not a replacement for a developer’s personal GitHub identity. It
exists only to make private module downloads work in the development
environment. Developers may continue to use their own GitHub authentication on
their laptops.

Do not reuse the `ee` deploy key. Do not grant this key write access. Do not
put the private key in `ee`, `go-shared`, shell history, or a checked-in config
file.

## 3. Host configuration

The host must use an exact repository rewrite rather than an organization-wide
rewrite:

```bash
git config --global url."git@github-go-shared:broadminde-org/go-shared".insteadOf \
  https://github.com/broadminde-org/go-shared
```

This rewrite is the most specific `insteadOf` entry and wins by longest match,
so no other rewrite needs to be removed.

The `github-go-shared` SSH alias must use the dedicated key, `IdentitiesOnly
yes`, and a managed GitHub host key. It must also set a dedicated
`ControlPath ~/.ssh/cm-go-shared-%r@%h:%p` so a personal-key ControlMaster to
`github.com` is never reused by the alias. Avoid trusting an arbitrary first
connection with `StrictHostKeyChecking=accept-new`; install a verified
`known_hosts` entry as part of host setup.

The host bootstrap implementation is `bootstrap
user/init.d/99-go-shared/run.sh`, which configures go-shared only —
`ee`/`ephemeral-engineering` are no longer Go repos and are not configured by
that step. It:

1. Installs or provisions the private key for the runtime user.
2. Creates the `github-go-shared` alias and verified `known_hosts` entry.
3. Installs the exact `insteadOf` rule above.
4. Preserves `GOPRIVATE=github.com/broadminde-org/*`.
5. Verifies access with `git ls-remote` before running Go tooling.

If more than one development host needs access, generate a separate key per
host or trust domain. GitHub permits multiple deploy keys on a repository; this
keeps revocation localized.

## 4. `ee` migration procedure

The repository migration is a source and module-graph change, not an access
grant to every path in `ee`.

1. Inventory all live Go imports, `go.mod` requirements, `go.work` entries,
   `replace` directives, build scripts, Docker build contexts, and tests that
   still reference `github.com/broadminde-org/ee/shared/backend`.
2. For each live consumer, map the old import to the corresponding
   `github.com/broadminde-org/go-shared` package. Do not mechanically rename
   paths where package layout or API behavior differs.
3. Add the correct root or nested `go-shared` module requirement to the
   consumer’s `go.mod`. Use released module versions and matching per-module
   tags; do not add a local `replace` pointing at a checkout.
4. Remove obsolete local `replace` directives and keep `ee/go.work` limited to
   modules that are actually maintained in the `ee` checkout.
5. Run `go mod tidy` in each affected module and `go work sync` from the `ee`
   root. Go-managed files such as `go.sum` must be updated by Go tooling, not
   hand-edited.
6. Build and test each affected application both with the workspace enabled
   and with `GOWORK=off`. The latter verifies that the application is genuinely
   consuming versioned `go-shared` modules rather than an accidental local
   workspace copy.
7. Remove the old `ee/shared/backend` source only after the inventory is empty
   and the independent-module checks pass. Historical plans and codemaps may
   retain references when clearly marked as historical; live instructions and
   scripts must point to `go-shared`.

## 5. Acceptance checks

Run these from `/home/luke/ee` after host access is configured:

```bash
# The dedicated key can read the repository.
GIT_SSH_COMMAND='ssh -i ~/.ssh/go-shared-read -o IdentitiesOnly=yes' \
  git ls-remote git@github-go-shared:broadminde-org/go-shared.git

# No live Go source or module metadata still consumes the old path.
rg -n 'github.com/broadminde-org/ee/shared/backend' \
  --glob '*.go' --glob 'go.mod' --glob 'go.work' --glob '*.sh' \
  --glob '*.yaml' --glob '*.yml' --glob '!shared/backend/**'

# Private module resolution works without a local replacement.
GOWORK=off GOPRIVATE=github.com/broadminde-org/* \
  go list -m github.com/broadminde-org/go-shared/web@latest

# Workspace metadata validation.
go work sync

# Independent-module validation (run once per affected module).
for mod in apps/enki apps/fintek apps/isogen apps/kilomodels \
  apps/kvm-ctl/backend apps/larga-site apps/netgnostic apps/sancus \
  apps/sshterm-demo apps/taco; do
  (cd "$mod" && GOWORK=off go test ./...)
done
```

The `rg` command must return no live-consumer matches. Historical documentation
matches are acceptable only if they describe the retired layout and do not
direct developers toward it.

## 6. Write and review boundary

The read-only deploy key cannot create branches, tags, commits, or pull
requests. Extraction or other improvements to `go-shared` follow this human
workflow:

1. A developer prepares the change using their personal GitHub identity.
2. The change is submitted as a pull request to `go-shared`.
3. Repository CI and an independent review gate the merge.
4. A maintainer merges and publishes the relevant module tag.
5. `ee` updates its module requirement in a separate change.

Branch protection and required checks are repository governance and must be
configured before relying on this workflow. They are deliberately not part of
the deploy-key credential.

## 7. Key lifecycle

- Record the host/trust-domain owner and creation date when the key is added.
- Keep the private key readable only by its runtime user.
- Rotate by adding a replacement key, verifying module downloads, then removing
  the old deploy key.
- Revoke the key immediately if the host or user account is compromised.
- Never use the same key for write access or for a different repository.
