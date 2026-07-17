#!/usr/bin/env bash
set -euo pipefail

# sync-kilo-context.sh — copy the live Kilo context set into this repo.
#
# Copies agents/, rules/, skills/, and commands/ from ~/.config/kilo/
# into user/opencode/ so the bootstrap repo stays
# current with the evolving context set.
#
# Usage:
#   ./sync-kilo-context.sh

SRC="$HOME/.config/kilo"
DST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/opencode"

if [[ ! -d "$SRC" ]]; then
  echo "Error: source $SRC not found." >&2
  exit 1
fi

if [[ ! -d "$DST" ]]; then
  echo "Error: destination $DST not found." >&2
  exit 1
fi

for dir in agents rules skills commands; do
  if [[ -d "$SRC/$dir" ]]; then
    cp -r "$SRC/$dir/." "$DST/$dir/"
    echo "  copied $dir/"
  fi
done

echo "Done. Run 'git diff' inside bootstrap to see what changed."
