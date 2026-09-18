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
    API, the GitHub Packages token (validated, stored in
    ~/.config/gh/broadminde-packages.token, and written to ~/.npmrc by
    user/init.d/98-npm-shared; hosts whose conf sets
    github.packages_write: true get write:packages for publishing), and —
    when the conf sets github.source_rw: true — the separate source RW
    token (repo, workflow), stored in ~/.config/gh/broadminde-source-rw.token;
  - caddy: the ACME account email for ~/infra/caddy/.env, plus acme-dns
    registration when the conf declares wildcard zones.

Capabilities without interactive credentials (docker, kvm, public) are
reported and skipped. Re-running is safe: every stage verifies current state
before prompting.

Do not run the helper with sudo: gh credentials, SSH keys, npm auth, and
PAT files are stored for the user who runs it. Tokens never live in the
bootstrap checkout (docs/adr/0001-github-pat-storage.md).

The GitHub stages delegate to ~/scripts/github-access, which is also the
entry point for redoing one piece:

  ~/scripts/github-access setup [--ci]   # gh + deploy keys + packages [+ source-rw]
  ~/scripts/github-access status         # full credential status
EOF
