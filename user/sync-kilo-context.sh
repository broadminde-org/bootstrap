#!/usr/bin/env bash
set -euo pipefail

# sync-kilo-context.sh — copy the live Kilo context set into this repo.
#
# Copies agents/, commands/, and kilo.jsonc from ~/.config/kilo/ into
# init.d/23-kilo-settings/_config/kilo/ — and skills/ from ~/.kilo/
# into init.d/23-kilo-settings/_kilo/ — so the bootstrap repo stays
# current with the evolving context set.
#
# The two destination directories match Kilo's global installation
# targets per the Marketplace docs:
#   https://kilo.ai/docs/customize/marketplace#files-changed-by-installation
#
#   Type    | Global destination
#   --------|-------------------
#   Agent   | ~/.config/kilo/agents/<name>.md
#   Skill   | ~/.kilo/skills/<name>/
#   Command  | ~/.config/kilo/commands/<name>.md
#
# Also syncs kilo.jsonc so the merged config (instructions + MCP +
# permissions) is kept in version control.
#
# Supports staging names: if a source directory uses an f- prefix
# (e.g. f-agents/, f-skills/), it is synced with the prefix stripped
# in the destination.
#
# Usage:
#   ./sync-kilo-context.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DST_CONFIG="$SCRIPT_DIR/init.d/23-kilo-settings/_config/kilo"
DST_KILO="$SCRIPT_DIR/init.d/23-kilo-settings/_kilo"

# -------------------------------------------------------------------
# 1. Sync from ~/.config/kilo  -->  _config/kilo/
# -------------------------------------------------------------------

SRC_CONFIG="$HOME/.config/kilo"

if [[ ! -d "$SRC_CONFIG" ]]; then
  echo "Error: source $SRC_CONFIG not found." >&2
  exit 1
fi

mkdir -p "$DST_CONFIG"

echo "=== Syncing from ~/.config/kilo/ to _config/kilo/ ==="

# 1a. Agents
sync_dir() {
  local name="$1" src="$SRC_CONFIG/$name" dst="$DST_CONFIG/$name"

  if [[ -d "$src" ]]; then
    rm -rf "$dst"
    cp -r "$src" "$dst"
    echo "  synced $name/"
  elif [[ -d "$SRC_CONFIG/f-$name" ]]; then
    rm -rf "$dst"
    cp -r "$SRC_CONFIG/f-$name" "$dst"
    echo "  synced f-$name/ -> $name/"
  else
    echo "  skipped $name/ (not found in source)"
  fi
}

for dir in agents commands; do
  sync_dir "$dir"
done

# 1b. kilo.jsonc
if [[ -f "$SRC_CONFIG/kilo.jsonc" ]]; then
  cp "$SRC_CONFIG/kilo.jsonc" "$DST_CONFIG/kilo.jsonc"
  echo "  synced kilo.jsonc"
else
  echo "  skipped kilo.jsonc (not found in source)"
fi

# -------------------------------------------------------------------
# 2. Sync from ~/.kilo  -->  _kilo/
# -------------------------------------------------------------------

SRC_KILO="$HOME/.kilo"

if [[ ! -d "$SRC_KILO" ]]; then
  echo "Error: source $SRC_KILO not found." >&2
  exit 1
fi

mkdir -p "$DST_KILO"

echo "=== Syncing from ~/.kilo/ to _kilo/ ==="

for dir in skills; do
  src="$SRC_KILO/$dir"
  dst="$DST_KILO/$dir"

  if [[ -d "$src" ]]; then
    rm -rf "$dst"
    cp -r "$src" "$dst"
    echo "  synced $dir/"
  elif [[ -d "$SRC_KILO/f-$dir" ]]; then
    rm -rf "$dst"
    cp -r "$SRC_KILO/f-$dir" "$dst"
    echo "  synced f-$dir/ -> $dir/"
  else
    echo "  skipped $dir/ (not found in source)"
  fi
done

# -------------------------------------------------------------------
# Done
# -------------------------------------------------------------------

echo ""
echo "Done. Run 'git diff' inside bootstrap to see what changed."
