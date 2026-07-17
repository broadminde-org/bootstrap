#!/usr/bin/env bash
# 15-direnv — direnv bashrc hook + scaffolding
#
# User tier: runs as the deploy user (non-root).
# Adds `eval "$(direnv hook bash)"` to ~/.bashrc and creates a profile-level
# direnvrc scaffold. Repo-level .envrc files are owned by individual app repos
# via their init.sh scripts.
#
# Idempotent: the bashrc hook is protected by a grep check; direnvrc is
# only created if it does not already exist.

set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

# ---------------------------------------------------------------------------
# 1. Add direnv bash hook
# ---------------------------------------------------------------------------

BASHRC="$HOME/.bashrc"
if ! grep -q 'direnv hook bash' "$BASHRC" 2>/dev/null; then
  printf '\n# direnv hook\neval "$(direnv hook bash)"\n' >> "$BASHRC"
  echo "Added direnv hook to $BASHRC"
else
  echo "direnv hook already present in $BASHRC — skipping."
fi

# ---------------------------------------------------------------------------
# 2. Create profile-level direnvrc scaffold
# ---------------------------------------------------------------------------

DIRENVRC="$HOME/.config/direnv/direnvrc"
if [ ! -f "$DIRENVRC" ]; then
  mkdir -p "$(dirname "$DIRENVRC")"
  cat > "$DIRENVRC" <<'RC_EOF'
# Profile-level direnvrc — sourced automatically by direnv before any
# repo-level .envrc. Add shared helper functions and environment setup
# here that all repos should inherit.
#
# The cascade model:
#   ~/.config/direnv/direnvrc   ← profile-level (all repos inherit)
#       ↓ (direnv automatically sources this)
#   <repo>/.envrc               ← repo-level (PATH_add, env vars)
RC_EOF
  echo "Created profile-level $DIRENVRC"
else
  echo "$DIRENVRC already exists — skipping."
fi

echo "direnv configured — add a .envrc to individual repos (and run 'direnv allow') to activate."
