#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

cat <<'EOF'
Interactive, per-user credential setup is driven by the capabilities enabled
in this host's bootstrap.conf.yml.

After both bootstrap tiers complete, run this as the deploy user:

  ~/scripts/bootstrap-access

It takes no arguments. Reading the active conf, it walks each enabled
capability that needs credentials:

  - gh login (required by the dev capability);
  - dev: read-only go-shared and frontend-shared deploy keys via the GitHub
    API, package auth in ~/.npmrc, and — when the conf sets
    github.source_rw: true — the separate source RW token (repo, workflow),
    stored in ~/.config/gh/broadminde-source-rw.token;
  - docker: optional private GHCR access when github.packages_read or
    github.packages_write is true; package auth is stored in
    ~/.docker/config.json for pulls (and publishing when write is enabled);
  - caddy: the ACME account email for ~/infra/caddy/.env, plus acme-dns
    registration when the conf declares wildcard zones.

Docker hosts without a private GHCR role, plus kvm and public, need no
interactive credentials. Re-running is safe: every stage verifies current
state before prompting.

Do not run the helper with sudo: gh credentials, SSH keys, npm/Docker auth, and
PAT files are stored for the user who runs it. Tokens never live in the
bootstrap checkout (docs/adr/0001-github-pat-storage.md).

The GitHub stages delegate to ~/scripts/github-access, which is also the
entry point for redoing one piece:

  ~/scripts/github-access setup [--ci]   # gh + deploy keys + packages [+ source-rw]
  ~/scripts/github-access status         # full credential status
EOF
