# Application container image build and publishing standard

This is the portable, bootstrap-owned contract for standalone application
repositories extracted from `ee`. Treat each application repository as the
unit of publication. The old `ee` Taco pipeline is historical, not a template
for new repositories. Consult the application's workflow for its private
dependency setup and other project-specific build requirements.

## Shared build runner

- Run `build` from the project root. It runs frontend, generation, binary, then
  Docker steps. Use `--no-docker`, `--docker-only` (requires an existing binary),
  `--no-push`, or `--tag <tag>` as appropriate.
- The Docker step requires a root `Dockerfile`; otherwise it skips the step and
  publishes nothing. Docker receives the project root as its build context.
  Inspect `.dockerignore` and the project's actual Dockerfile before changing
  what goes into an image.
- `IMAGE_NAME` overrides the project directory name. `IMAGE_REGISTRY` supplies
  the registry prefix; without it no push occurs. The runner reads the project
  root `.env` as trusted Bash; an explicit caller environment overrides `.env`
  for `IMAGE_REGISTRY`, `IMAGE_NAME`, `IMAGE_TAG`, and `IMAGE_ALIAS_TAGS`. Never
  print credentials or copy secret values into build logs or artifacts.
- The runner defaults the primary tag to `IMAGE_TAG` or `latest`. Without an
  explicit `--tag`, it also builds version and semver tags. An explicit `--tag`
  suppresses that version tag family. `IMAGE_ALIAS_TAGS` adds comma-delimited
  aliases to the built primary image. The Docker step applies OCI version and
  revision labels plus build number and build time labels, then pushes the
  registry-qualified primary and alias tags when enabled.
- The step runs an executable project-local `scripts/build-hooks/post-docker`
  after its own push. Do not push the same tags again in the hook.

The deployed runner is `~/scripts/build` and its Docker step is
`~/scripts/build.d/40-docker.sh`; their provisioning sources are
`bootstrap/user/init.d/30-scripts/scripts/build` and
`bootstrap/user/init.d/30-scripts/scripts/build.d/40-docker.sh`.

## Production publication

- Name the image `${REGISTRY}/${IMAGE_NAME}`. Supply `REGISTRY` through a
  Woodpecker organization secret (intended namespace:
  `ghcr.io/broadminde-org`). Set `IMAGE_NAME` to the application's stable
  name; the local backend's checkout directory may be `workspace`.
- On a successful main-branch publication, push
  `sha-<first 8 characters of CI_COMMIT_SHA>` and the rolling `main` alias.
  Use `build --tag "sha-${CI_COMMIT_SHA:0:8}"` with `IMAGE_ALIAS_TAGS=main`.
  Do not use `latest` or invent semver tags for this flow. A SHA tag identifies
  a commit, but is neither a digest nor an enforced immutable GHCR tag.
- Gate publication to pushes on `main` and manual runs, not pull requests.
  Use Woodpecker `CI_*` variables rather than forge-specific variables. Select
  `backend: local` explicitly, set `IMAGE_NAME` and `PATH`, and authenticate to
  `ghcr.io` inside the workflow using mapped `REGISTRY` and `GHCR_TOKEN`
  secrets. The login username belongs to the token-owning GitHub account, not
  the organization; update it if the credential changes.
- For the existing local-backend pattern, pin the clone plugin image and set
  `lfs: false` (the plugin defaults it on, while git-lfs is not installed).
  Its isolated HOME needs application-appropriate access to private Go modules
  and npm packages. Do not copy another app's frontend or Swagger settings.
- `GHCR_TOKEN` is an org-level classic PAT historically documented with
  package write and private-source access. Its exposure and personal-account
  ownership are accepted historical risks, not precedent to expand access.
  A deploy host pulling private packages needs read access. For a new package,
  check visibility, repository linkage, and pull-host authentication.

## Verification and live-test boundary

1. Static inspection or mocked commands prove command construction, not
   publication.
2. `build --no-push` proves a local image builds; even a registry-qualified
   local tag is not a remote publication.
3. For the standard live-push test, use a disposable loopback `registry:2`,
   override `IMAGE_REGISTRY=localhost:<port>`, and build with pushing enabled
   and an explicit test tag. Verify via the registry API and access log that
   each expected tag is pushed exactly once, no version/semver tags appear,
   the SHA and alias tags resolve to the same digest, and a pull succeeds.
   Remove the disposable registry afterward. This tests real pushes without
   touching GHCR, but proves nothing about GHCR-specific credentials or access.
4. Publish to GHCR only with explicit approval of the target package, tags,
   and pull check. Verify the Woodpecker run, registry tags/digest, an
   authenticated pull from the intended host, and an application-appropriate
   check. A local `docker run --rm` does not delete a remote tag or package.

There is no disposable GHCR namespace or package for tag-set tests. Do not
publish test tags to a production package or treat a historical smoke-test
package as scratch: at current credential scopes, test tags cannot be cleanly
deleted. Once a package's credential, visibility, linkage, and pull access
have been established, tag-set changes can use the local registry test and
observation of the next real production publish.
