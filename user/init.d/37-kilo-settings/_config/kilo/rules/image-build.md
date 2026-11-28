# Application image build context

When working on an application Dockerfile, image build or tag, Woodpecker
image publication, GHCR push, or registry validation, load the `image-build`
skill first. Its bootstrap-owned reference is the portable host standard;
the shared runner's defaults are not the production publishing policy.
