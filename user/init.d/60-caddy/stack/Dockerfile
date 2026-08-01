# syntax=docker/dockerfile:1
# caddy-custom: stock caddy:2 runtime with plugins compiled in via xcaddy.
# Builds the same caddy:2 image that ships on Docker Hub, then compiles
# caddy from source in the :builder stage with xcaddy and the DNS/bouncer
# plugins. Final stage is a tiny runtime image with just the custom binary.
#
# To pin a Caddy version, set CADDY_VERSION at build time, e.g.:
#   docker build --build-arg CADDY_VERSION=2.8.4 -t caddy-custom:latest .

ARG CADDY_VERSION=2.11.4

# ---------------------------------------------------------------------------
# Stage 1: compile caddy with the plugins
# ---------------------------------------------------------------------------
FROM caddy:${CADDY_VERSION}-builder AS builder

# xcaddy is pre-installed in the :builder image. The 'go install' line
# pulls xcaddy's deps into the Go module cache, then `xcaddy build`
# compiles caddy from source with the named plugins linked in.
#
# Pinned matrix (verified 2026-07-25):
#   caddy:2.11.4-builder   — Go 1.24, base Alpine 3.21
#   caddy v2.11.4          — current stable
#   acmedns v0.7.0         — requires Caddy >= v2.10.0 and Go 1.24
#                           (its go.mod declares these explicitly)
#   caddy-crowdsec-bouncer v0.13.1 — its go.mod targets caddy v2.11.3 and
#                           declares Go 1.25.7; if the builder image's Go is
#                           older, the go toolchain auto-downloads 1.25.7
#                           during build (network is available in docker
#                           build). /http also blank-imports /appsec (inert
#                           unless appsec_url is set). /layer4 is
#                           intentionally omitted (needs mholt/caddy-l4).
#   xcaddy v0.4.5          — latest; matches caddy:2.11.4-builder
RUN go install github.com/caddyserver/xcaddy/cmd/xcaddy@v0.4.5 \
 && xcaddy build v2.11.4 \
    --with github.com/caddy-dns/acmedns@v0.7.0 \
    --with github.com/hslatman/caddy-crowdsec-bouncer/http@v0.13.1

# ---------------------------------------------------------------------------
# Stage 2: slim runtime
# ---------------------------------------------------------------------------
FROM caddy:${CADDY_VERSION}

# Upgrade Alpine packages to pick up patched curl (8.20.0-r0+) and
# c-ares (1.34.8-r0+). Fixes CVE-2026-5773, CVE-2026-6253, CVE-2026-6429,
# CVE-2026-7168, CVE-2026-5545, CVE-2026-6276, CVE-2026-4873,
# CVE-2026-7009, and CVE-2026-33630 (c-ares).
# golang.org/x/crypto GO-2026-5932 is in Caddy's go.mod; no upstream fix
# yet — accept until Caddy ships a patch release.
RUN apk upgrade --no-cache

# Replace the stock caddy binary with the one built in stage 1.
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
