#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 23-kilo-context — Deploy the Kilo global context set to ~/.config/kilo/
#
# Copies the full context set from bootstrap/user/opencode/ into
# ~/.config/kilo/, installs the merged kilo.jsonc (instructions glob +
# MCP config + permission block), deploys the host-standards MCP server
# as a Docker Compose project, and starts it.
#
# Context directories deployed:
#   agents/    — agent definitions loaded by kilo
#   commands/  — slash commands
#   rules/     — instruction files (loaded via kilo.jsonc instructions glob)
#   skills/    — skills (each skill is a subdirectory with SKILL.md)
#   standards/ — reference docs served by the host-standards MCP server
#
# MCP server:
#   Source:  bootstrap/user/opencode/mcp-server/
#   Deploy:  ~/.config/kilo/mcp-server/
#   Listens: http://localhost:8766/mcp
#   Mounts:  ~/.config/kilo/standards/ (read-only)
#
# Idempotent: context directories are replaced on every run so re-running
# picks up any changes made to files in user/opencode/. Docker Compose
# only rebuilds if sources changed (--build is passed; cached layers apply).
#
# Run as the deploy user (./user/init.sh 23-kilo-context).

STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCODE_DIR="$(cd "$STEP_DIR/../../opencode" && pwd)"
KILO_CONFIG="$HOME/.config/kilo"
MCP_DEPLOY="$KILO_CONFIG/mcp-server"

# ---------------------------------------------------------------------------
# 1. Ensure ~/.config/kilo exists
# ---------------------------------------------------------------------------

mkdir -p "$KILO_CONFIG"
echo "Config dir: $KILO_CONFIG"

# ---------------------------------------------------------------------------
# 2. Deploy context directories
# ---------------------------------------------------------------------------

for dir in agents commands rules skills standards; do
  src="$OPENCODE_DIR/$dir"
  if [[ ! -d "$src" ]]; then
    echo "  WARNING: $src not found — skipping $dir/." >&2
    continue
  fi
  rm -rf "${KILO_CONFIG:?}/$dir"
  cp -r "$src" "$KILO_CONFIG/$dir"
  count="$(find "$KILO_CONFIG/$dir" -name '*.md' | wc -l)"
  echo "  deployed $dir/  (${count} .md files)"
done

# ---------------------------------------------------------------------------
# 3. Deploy kilo.jsonc (instructions glob + MCP config)
# ---------------------------------------------------------------------------
# Permissions are intentionally omitted — they accumulate naturally during
# sessions as the user approves commands. Baking them in here would carry
# stale, machine-specific allow-lists to every new host.

KILO_JSON_SRC="$OPENCODE_DIR/kilo.jsonc"
KILO_JSON="$KILO_CONFIG/kilo.jsonc"

if [[ ! -f "$KILO_JSON_SRC" ]]; then
  echo "ERROR: $KILO_JSON_SRC not found." >&2
  exit 1
fi

cp "$KILO_JSON_SRC" "$KILO_JSON"
echo "  deployed kilo.jsonc"

# ---------------------------------------------------------------------------
# 4. Deploy MCP server docker compose project
# ---------------------------------------------------------------------------

MCP_SRC="$OPENCODE_DIR/mcp-server"

if [[ ! -d "$MCP_SRC" ]]; then
  echo "WARNING: mcp-server/ not found at $MCP_SRC — skipping MCP deploy." >&2
  echo "         The host-standards MCP server will not be available." >&2
else
  rm -rf "$MCP_DEPLOY"
  cp -r "$MCP_SRC" "$MCP_DEPLOY"

  # Resolve tilde in the docker-compose.yml volume mount to the actual
  # absolute home path so Docker Compose has no shell-expansion ambiguity.
  sed -i "s|~/.config/kilo/standards|${KILO_CONFIG}/standards|g" \
    "$MCP_DEPLOY/docker-compose.yml"

  echo "  deployed mcp-server/ to $MCP_DEPLOY"

  # -------------------------------------------------------------------------
  # 5. Start the MCP server via Docker Compose
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
echo "23-kilo-context: context set deployed to $KILO_CONFIG"
echo "  context:      agents/ commands/ rules/ skills/ standards/"
echo "  config:       $KILO_CONFIG/kilo.jsonc"
echo "  MCP server:   http://localhost:8766/mcp (host-standards)"
echo ""
echo "Restart kilo (or reload config) to pick up the new context and MCP connection."
