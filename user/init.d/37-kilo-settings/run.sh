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
# Skills that document a specific provisioned feature live with that
# feature's step instead of here, so they share the step's capability
# gating — e.g. the central-caddy skill deploys from 60-caddy/kilo/skills/
# (gated on docker + caddy), not from this skeleton.
#
# MCP server:
#   Source:  init.d/23-kilo-settings/_config/kilo/mcp-server/  (if present)
#   Deploy:  ~/.config/kilo/mcp-server/
#   Listens: http://localhost:8766/mcp
#   Mounts:  ~/.config/kilo/standards/ (read-only)
#
# Idempotent: directories are synced without deletion — user-installed agents,
# commands, and skills survive re-runs. kilo.json/kilo.jsonc are copied once; on
# re-runs a diff is shown instead of overwriting, to protect accumulated
# permissions. Docker Compose only rebuilds if sources changed (--build is
# passed; cached layers apply).
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

echo "=== Deploying from _config/kilo/ to ~/.config/kilo/ ==="

for dir in agents commands; do
  sync_dir_preserve "$SRC_CONFIG/$dir" "$KILO_CONFIG/$dir"
done

# ---------------------------------------------------------------------------
# 3. Deploy kilo.json / kilo.jsonc
# ---------------------------------------------------------------------------
# Kilo deep-merges kilo.json with kilo.jsonc. Permissions are intentionally
# omitted from both — they accumulate naturally during sessions.
#
# On first run: copy the skeleton file. On re-run: if the source differs from
# the live file show a diff and a warning so the user can merge manually.
for cfg in kilo.json kilo.jsonc; do
  cfg_src="$SRC_CONFIG/$cfg"
  cfg_dst="$KILO_CONFIG/$cfg"

  if [[ ! -f "$cfg_src" ]]; then
    echo "  skipped $cfg (not found in skeleton)"
    continue
  fi

  if [[ ! -f "$cfg_dst" ]]; then
    cp "$cfg_src" "$cfg_dst"
    echo "  deployed $cfg (new)"
  elif ! cmp -s "$cfg_src" "$cfg_dst"; then
    echo ""
    echo "  WARNING: skeleton $cfg differs from $cfg_dst"
    echo "  Diff (skeleton -> live):"
    diff -u "$cfg_dst" "$cfg_src" || true
    echo ""
    echo "  Review the diff above and merge changes into $cfg_dst manually."
    echo "  This warning will appear on every re-run until the files match."
  else
    echo "  $cfg unchanged"
  fi
done

# ---------------------------------------------------------------------------
# 4. Deploy from _kilo/  -->  ~/.kilo/
# ---------------------------------------------------------------------------

echo "=== Deploying from _kilo/ to ~/.kilo/ ==="

sync_dir_preserve "$SRC_KILO/skills" "$KILO_HOME/skills"

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
