---
name: image-build
description: Build and publish application Docker images using this host's shared build runner and Woodpecker/GHCR conventions. USE FOR Dockerfile changes, image names or tags, IMAGE_* configuration, CI image publication, registry push tests, and build or publish failures. DO NOT USE FOR Docker Compose runtime orchestration, host Docker provisioning, or generic container cleanup.
---

# Application image builds

Read [references/image-publishing.md](references/image-publishing.md) before
changing a Dockerfile, build invocation, image tags, or publication workflow.
That reference is the bootstrap-owned portable contract; inspect the actual
project and installed `build` runner for local specifics. Do not assume a
checkout of the `ci` repository exists on the target host.

Run `build` from the project root. For production publication, use a stable
`IMAGE_NAME`, `build --tag "sha-${CI_COMMIT_SHA:0:8}"`, and
`IMAGE_ALIAS_TAGS=main`; never mistake the runner's default `latest` and
version tags for the production CI policy. Validate without pushing to GHCR
unless the user explicitly approves the package, tags, and pull check.
