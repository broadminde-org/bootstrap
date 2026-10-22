#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 37-kilo-settings — Deploy the Kilo global context set from skeleton dirs.
#
# Deploys from two source directories that mirror the live layout:
#
#   Source                                   | Target
#   -----------------------------------------|-----------------------
#   init.d/37-kilo-settings/_config/kilo/    | ~/.config/kilo/
#   init.d/37-kilo-settings/_kilo/           | ~/.kilo/
#
# This matches Kilo's Marketplace installation conventions:
#
#   Type    | Global destination
#   --------|-------------------
#   Agent   | ~/.config/kilo/agents/<name>.md
#   Command | ~/.config/kilo/commands/<name>.md
#   Skill   | ~/.kilo/skills/<name>/
#
# _config/kilo/ deploys:
#   agents/    — agent definitions (marketplace agents)
#   commands/  — slash commands
#   kilo.json  — MCP servers. Mirrors what the Kilo Marketplace installs
#                for the Playwright MCP (@playwright/mcp via npx; node/npx
#                is provided by 35-node). Also carries the Svelte docs MCP
#                as a remote server (https://mcp.svelte.dev/mcp — hosted by
#                the Svelte team, always tracks current docs, no local deps,
#                degrades gracefully when offline). Kilo deep-merges this
#                with kilo.jsonc, so the two files stay separate concerns.
#   kilo.jsonc — instructions glob (rules/) plus permissions
#
# ~/.config/kilo/rules/ is loaded globally by the instructions glob in
# kilo.jsonc. It includes the no-privilege-escalation policy for chat LLM
# sessions. Keep this set small: rules are present in every agent context.
#
# _kilo/ deploys:
#   skills/    — skills (each skill is a subdirectory with SKILL.md)
#
# Skills that document a specific provisioned feature live with that
# feature's step instead of here, so they share the step's capability
# gating — e.g. the central-caddy skill deploys from 60-caddy/kilo/skills/
# (gated on docker + caddy), not from this skeleton.
#
# Idempotent: directories are synced without deletion — user-installed agents,
# commands, and skills survive re-runs. kilo.json is copied once and remains a
# manual merge. kilo.jsonc is copied on first install; existing files receive a
# narrow, validated migration of the managed instructions and privilege-denial
# settings. Unfamiliar or conflicting JSONC is rejected for manual review.
#
# Run as the deploy user (./user/init.sh 37-kilo-settings).

STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_CONFIG="$STEP_DIR/_config/kilo"
SRC_KILO="$STEP_DIR/_kilo"
SRC_KILOCODEIGNORE="$STEP_DIR/.kilocodeignore"
BOOTSTRAP_ROOT="$(cd "$STEP_DIR/../../.." && pwd)"

KILO_CONFIG="$HOME/.config/kilo"
KILO_HOME="$HOME/.kilo"

# ---------------------------------------------------------------------------
# 1. Ensure target dirs exist
# ---------------------------------------------------------------------------

mkdir -p "$KILO_CONFIG"
echo "Config dir: $KILO_CONFIG"

mkdir -p "$KILO_HOME"
echo "Kilo home dir: $KILO_HOME"

# ---------------------------------------------------------------------------
# 2. Deploy from _config/kilo/  -->  ~/.config/kilo/
# ---------------------------------------------------------------------------

echo "=== Deploying from _config/kilo/ to ~/.config/kilo/ ==="

for dir in agents commands rules; do
  if [[ -d "$SRC_CONFIG/$dir" ]]; then
    sync_dir_preserve "$SRC_CONFIG/$dir" "$KILO_CONFIG/$dir"
  else
    echo "  skipped $dir/ (not found in skeleton)"
  fi
done

# ---------------------------------------------------------------------------
# 3. Deploy kilo.json / kilo.jsonc
# ---------------------------------------------------------------------------
# Kilo deep-merges kilo.json with kilo.jsonc. MCP server configuration lives in
# kilo.json; permissions such as permission.bash: allow live in kilo.jsonc.
#
# kilo.json is create-once because its MCP settings are locally customizable.
cfg_src="$SRC_CONFIG/kilo.json"
cfg_dst="$KILO_CONFIG/kilo.json"
if [[ ! -f "$cfg_src" ]]; then
  echo "  skipped kilo.json (not found in skeleton)"
elif [[ ! -f "$cfg_dst" ]]; then
  cp "$cfg_src" "$cfg_dst"
  echo "  deployed kilo.json (new)"
elif ! cmp -s "$cfg_src" "$cfg_dst"; then
    echo ""
    echo "  WARNING: skeleton kilo.json differs from $cfg_dst"
    echo "  Diff (skeleton -> live):"
    diff -u "$cfg_dst" "$cfg_src" || true
    echo ""
    echo "  Review the diff above and merge changes into $cfg_dst manually."
    echo "  This warning will appear on every re-run until the files match."
else
  echo "  kilo.json unchanged"
fi

# kilo.jsonc preserves local formatting and permissions while automatically
# migrating only the recognized policy subset. The helper validates the live
# effective config and rolls back atomically on failure.
cfg_src="$SRC_CONFIG/kilo.jsonc"
cfg_dst="$KILO_CONFIG/kilo.jsonc"
if [[ ! -f "$cfg_src" ]]; then
  echo "  skipped kilo.jsonc (not found in skeleton)"
elif ! "$STEP_DIR/migrate-kilo-jsonc.sh" "$cfg_src" "$cfg_dst"; then
  echo "  kilo.jsonc rejected; review the manual-merge guidance above." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 4. Deploy Bootstrap workspace indexing exclusions
# ---------------------------------------------------------------------------
# .kilocodeignore is workspace-scoped rather than global Kilo configuration.
# Preserve a locally customized file and show the diff for manual merging.
if [[ -f "$SRC_KILOCODEIGNORE" ]]; then
  dst="$BOOTSTRAP_ROOT/.kilocodeignore"
  if [[ ! -f "$dst" ]]; then
    cp "$SRC_KILOCODEIGNORE" "$dst"
    echo "  deployed .kilocodeignore (new)"
  elif ! cmp -s "$SRC_KILOCODEIGNORE" "$dst"; then
    echo ""
    echo "  WARNING: skeleton .kilocodeignore differs from $dst"
    echo "  Diff (live -> skeleton):"
    diff -u "$dst" "$SRC_KILOCODEIGNORE" || true
    echo ""
    echo "  Review the diff above and merge changes into $dst manually."
  else
    echo "  .kilocodeignore unchanged"
  fi
else
  echo "  skipped .kilocodeignore (not found in skeleton)"
fi

# ---------------------------------------------------------------------------
# 5. Deploy from _kilo/  -->  ~/.kilo/
# ---------------------------------------------------------------------------

echo "=== Deploying from _kilo/ to ~/.kilo/ ==="

if [[ -d "$SRC_KILO/skills" ]]; then
  sync_dir_preserve "$SRC_KILO/skills" "$KILO_HOME/skills"
else
  echo "  skipped skills/ (not found in skeleton)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "37-kilo-settings: context set deployed."
echo "  ~/.config/kilo/:  agents/ commands/ rules/ kilo.json (MCP) kilo.jsonc"
echo "  LLM privilege:     rules/privilege-escalation.md (manual handoff required)"
echo "  ~/.kilo/:         skills/"
echo "  Bootstrap:        $BOOTSTRAP_ROOT/.kilocodeignore"
echo "  Playwright MCP:   npx @playwright/mcp (needs node/npx from 35-node)"
echo ""
echo "Restart kilo (or reload config) to pick up the new context."
