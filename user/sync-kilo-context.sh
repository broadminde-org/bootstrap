#!/usr/bin/env bash
set -euo pipefail

# sync-kilo-context.sh — copy the live Kilo context set into this repo.
#
# Copies agents/, commands/, and kilo.jsonc from ~/.config/kilo/ into
# init.d/37-kilo-settings/_config/kilo/ — and skills/ from ~/.kilo/
# into init.d/37-kilo-settings/_kilo/ — so the bootstrap repo stays
# current with the evolving context set.
#
# Exception: skills that are mastered by a feature step (because they
# document that feature and share its capability gating) are routed to
# their owning step instead of the 37-kilo-settings skeleton:
#
#   ~/.kilo/skills/air/            ->  init.d/30-scripts/kilo/skills/air/
#   ~/.kilo/skills/central-caddy/  ->  init.d/60-caddy/kilo/skills/central-caddy/
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
DST_CONFIG="$SCRIPT_DIR/init.d/37-kilo-settings/_config/kilo"
DST_KILO="$SCRIPT_DIR/init.d/37-kilo-settings/_kilo"

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

# 1a. Agents / commands / rules. This is an intentional wholesale mirror
# (rm -rf + cp -r), unlike sync_dir_preserve() in the user-tier lib:
# deleted context files must disappear from the repo too.
sync_dir() {
  local name="$1"
  local src="$SRC_CONFIG/$name"
  local dst="$DST_CONFIG/$name"

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

for dir in agents commands rules; do
  sync_dir "$dir"
done

# 1b. kilo.jsonc + kilo.json (deep-merged by Kilo; both are context).
for cfg in kilo.jsonc kilo.json; do
  if [[ -f "$SRC_CONFIG/$cfg" ]]; then
    cp "$SRC_CONFIG/$cfg" "$DST_CONFIG/$cfg"
    echo "  synced $cfg"
  else
    echo "  skipped $cfg (not found in source)"
  fi
done

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

# Skills — same intentional wholesale mirror as section 1a (deleted
# skills must disappear from the repo). Single directory, so a plain
# block instead of a loop.
src="$SRC_KILO/skills"
dst="$DST_KILO/skills"

if [[ -d "$src" ]]; then
  rm -rf "$dst"
  cp -r "$src" "$dst"
  echo "  synced skills/"
elif [[ -d "$SRC_KILO/f-skills" ]]; then
  rm -rf "$dst"
  cp -r "$SRC_KILO/f-skills" "$dst"
  echo "  synced f-skills/ -> skills/"
else
  echo "  skipped skills/ (not found in source)"
fi

# Route feature-step skills out of the 37 skeleton to their owning step.
# The live ~/.kilo/skills/ namespace is flat, so the whole-dir copy above
# pulls these in — move each to the step that masters it.
route_skill() {
  local skill="$1" step="$2"
  local src="$DST_KILO/skills/$skill"
  local dst="$SCRIPT_DIR/init.d/$step/kilo/skills/$skill"

  if [[ -d "$src" ]]; then
    mkdir -p "$(dirname "$dst")"
    rm -rf "$dst"
    mv "$src" "$dst"
    echo "  routed skills/$skill -> $step/kilo/skills/"
  fi
}

route_skill air 30-scripts
route_skill central-caddy 60-caddy
route_skill frontend-shared-access 98-npm-shared

# -------------------------------------------------------------------
# Done
# -------------------------------------------------------------------

echo ""
echo "Done. Run 'git diff' inside bootstrap to see what changed."
