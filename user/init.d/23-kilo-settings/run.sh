#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 23-kilo-settings — Deploy the Kilo global context set from skeleton dirs.
#
# Deploys from two source directories that mirror the live layout:
#
#   Source                                   | Target
#   -----------------------------------------|-----------------------
#   init.d/23-kilo-settings/_config/kilo/    | ~/.config/kilo/
#   init.d/23-kilo-settings/_kilo/           | ~/.kilo/
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
#   kilo.jsonc — merged base config (instructions glob; no permissions)
#
# _kilo/ deploys:
#   skills/    — skills (each skill is a subdirectory with SKILL.md)
#
# MCP server:
#   Source:  init.d/23-kilo-settings/_config/kilo/mcp-server/  (if present)
#   Deploy:  ~/.config/kilo/mcp-server/
#   Listens: http://localhost:8766/mcp
#   Mounts:  ~/.config/kilo/standards/ (read-only)
#
# Idempotent: directories are replaced on every run so re-running
# picks up any changes committed to the skeletons. Docker Compose
# only rebuilds if sources changed (--build is passed; cached layers
# apply).
#
# Run as the deploy user (./user/init.sh 23-kilo-settings).

STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_CONFIG="$STEP_DIR/_config/kilo"
SRC_KILO="$STEP_DIR/_kilo"

KILO_CONFIG="$HOME/.config/kilo"
KILO_HOME="$HOME/.kilo"
MCP_DEPLOY="$KILO_CONFIG/mcp-server"

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

deploy_dir() {
  local name="$1"
  local src="$SRC_CONFIG/$name"
  local dst="$KILO_CONFIG/$name"

  if [[ ! -d "$src" ]]; then
    echo "  skipped $name/ (not found in skeleton)"
    return
  fi
  rm -rf "${dst}"
  cp -r "$src" "$dst"
  local count
  count="$(find "$dst" -name '*.md' | wc -l)"
  echo "  deployed $name/  (${count} .md files)"
}

echo "=== Deploying from _config/kilo/ to ~/.config/kilo/ ==="

for dir in agents commands; do
  deploy_dir "$dir"
done

# ---------------------------------------------------------------------------
# 3. Deploy kilo.json / kilo.jsonc
# ---------------------------------------------------------------------------
# Permissions are intentionally omitted from both — they accumulate naturally
# during sessions as the user approves commands. Baking them in here would
# carry stale, machine-specific allow-lists to every new host.
#
# NOTE: cp overwrites the target. That is safe for the curated keys these
# skeleton files carry (mcp, instructions, $schema), but if a skeleton file
# ever grows user-scoped keys, re-running this step will clobber the live
# file's accumulated values.

for cfg in kilo.json kilo.jsonc; do
  cfg_src="$SRC_CONFIG/$cfg"
  cfg_dst="$KILO_CONFIG/$cfg"

  if [[ ! -f "$cfg_src" ]]; then
    echo "  skipped $cfg (not found in skeleton)"
    continue
  fi
  cp "$cfg_src" "$cfg_dst"
  echo "  deployed $cfg"
done

# ---------------------------------------------------------------------------
# 4. Deploy from _kilo/  -->  ~/.kilo/
# ---------------------------------------------------------------------------

echo "=== Deploying from _kilo/ to ~/.kilo/ ==="

for dir in skills; do
  src="$SRC_KILO/$dir"
  dst="$KILO_HOME/$dir"

  if [[ ! -d "$src" ]]; then
    echo "  skipped $dir/ (not found in skeleton)"
    continue
  fi
  rm -rf "${dst}"
  cp -r "$src" "$dst"
  count="$(find "$dst" -name '*.md' | wc -l)"
  echo "  deployed $dir/  (${count} .md files)"
done

# ---------------------------------------------------------------------------
# 5. Deploy MCP server (if present)
# ---------------------------------------------------------------------------

MCP_SRC="$SRC_CONFIG/mcp-server"

if [[ ! -d "$MCP_SRC" ]]; then
  echo ""
  echo "mcp-server/ not found at $MCP_SRC — skipping MCP deploy."
else
  rm -rf "$MCP_DEPLOY"
  cp -r "$MCP_SRC" "$MCP_DEPLOY"

  # Resolve tilde in the docker-compose.yml volume mount to the actual
  # absolute home path so Docker Compose has no shell-expansion ambiguity.
  sed -i "s|~/.config/kilo/standards|${KILO_CONFIG}/standards|g" \
    "$MCP_DEPLOY/docker-compose.yml"

  echo "  deployed mcp-server/ to $MCP_DEPLOY"

  # -------------------------------------------------------------------------
  # 5a. Start the MCP server via Docker Compose
  # -------------------------------------------------------------------------

  if ! command -v docker &>/dev/null; then
    echo ""
    echo "WARNING: docker not found — MCP server not started." >&2
    echo "         Install Docker and run:" >&2
    echo "           docker compose -f $MCP_DEPLOY/docker-compose.yml up -d --build" >&2
  else
    echo "Starting host-standards MCP server..."
    docker compose -f "$MCP_DEPLOY/docker-compose.yml" up -d --build
    echo "  host-standards MCP listening at http://localhost:8766/mcp"
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "23-kilo-settings: context set deployed."
echo "  ~/.config/kilo/:  agents/ commands/ kilo.json (playwright MCP) kilo.jsonc"
echo "  ~/.kilo/:         skills/"
echo "  MCP server:       http://localhost:8766/mcp (host-standards)"
echo "  Playwright MCP:   npx @playwright/mcp (needs node/npx from 35-node)"
echo ""
echo "Restart kilo (or reload config) to pick up the new context."
