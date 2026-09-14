#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

cat <<'EOF'
GitHub CLI authentication is an interactive, per-user operation.

Run this as the deploy user from an interactive terminal:

  gh auth login --hostname github.com --git-protocol ssh --web

This selects GitHub.com with SSH for Git operations. gh will prompt to
upload your SSH public key, then open the browser to complete login.
Do not run the command with sudo: the credentials must be stored for the
user who will run gh.

If gh is not installed yet, run the root-tier step first:

  sudo ../init.sh 59-gh-cli    # from user/  (repo root: sudo ./init.sh 59-gh-cli)

After login, verify the identity with:

  gh auth status
  gh api user --jq '.login + " (" + .name + ")"'
EOF
