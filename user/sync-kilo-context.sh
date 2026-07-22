#!/usr/bin/env bash
set -euo pipefail

# sync-kilo-context.sh — copy the live Kilo context set into this repo.
#
# Copies agents/, rules/, skills/, commands/, standards/, and mcp-server/
# from ~/.config/kilo/ into user/opencode/ so the bootstrap repo stays
# current with the evolving context set.
#
# Supports both the active names (agents/, rules/, etc.) and the
# staging names (f-agents/, f-rules/, etc.) used while the context set
# is being edited. The f- prefix is stripped in the destination.
#
# Also syncs kilo.jsonc so the merged config (instructions + MCP +
# permissions) is kept in version control.
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

for dir in agents rules skills commands standards mcp-server; do
  if [[ -d "$SRC/$dir" ]]; then
    rm -rf "$DST/$dir"
    cp -r "$SRC/$dir" "$DST/$dir"
    echo "  synced $dir/"
  elif [[ -d "$SRC/f-$dir" ]]; then
    rm -rf "$DST/$dir"
    cp -r "$SRC/f-$dir" "$DST/$dir"
    echo "  synced f-$dir/ -> $dir/"
  else
    echo "  skipped $dir/ (not found in source)"
  fi
done

# Sync kilo.jsonc (merged config: instructions + MCP + permissions)
if [[ -f "$SRC/kilo.jsonc" ]]; then
  cp "$SRC/kilo.jsonc" "$DST/kilo.jsonc"
  echo "  synced kilo.jsonc"
fi

echo "Done. Run 'git diff' inside bootstrap to see what changed."
