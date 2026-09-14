#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 30-scripts — Install user scripts and their runners.
#
# scripts/ and script-runners/ live alongside this run.sh inside the
# init.d/30-scripts/ step directory.
#
# Copies the scripts/ directory to $HOME/scripts/ so they are available
# at a predictable path. Copies each executable in script-runners/ into
# $HOME/.local/bin/ so scripts can be invoked by name.
#
# Idempotent: scripts are synced without deletion — user-added scripts survive
# re-runs. Runners are overwritten individually by name.
#
# Run as the deploy user (./user/init.sh 30-scripts).
#
# Also deploys the air agent skill (kilo/skills/ -> ~/.kilo/skills/) and ships
# the canonical .air.toml template (templates/air.toml.template) consumed by
# that skill.

SCRIPTS_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts"
RUNNERS_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/script-runners"
SCRIPTS_DST="$HOME/scripts"
RUNNERS_DST="$HOME/.local/bin"

# Deploy the air agent skill (~/.kilo/skills/). Plain files; sync_dir_preserve
# never deletes, so user-installed skills survive re-runs. Same pattern as
# user/init.d/99-go-shared/run.sh.
sync_dir_preserve "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/kilo/skills" "$HOME/.kilo/skills"

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------

if ! command -v uv >/dev/null 2>&1 && [[ ! -x "$HOME/.local/bin/uv" ]]; then
  echo "ERROR: uv is required but was not found." >&2
  echo "       Re-run after 20-python installs uv." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. Copy scripts/ to $HOME/scripts/
# ---------------------------------------------------------------------------

if [ ! -d "$SCRIPTS_SRC" ]; then
  echo "ERROR: scripts/ not found at ${SCRIPTS_SRC}" >&2
  exit 1
fi

sync_dir_preserve "$SCRIPTS_SRC" "$SCRIPTS_DST"

# ---------------------------------------------------------------------------
# 2. Install runners into $HOME/.local/bin/
# ---------------------------------------------------------------------------

if [ ! -d "$RUNNERS_SRC" ]; then
  echo "ERROR: script-runners/ not found at ${RUNNERS_SRC}" >&2
  exit 1
fi

mkdir -p "$RUNNERS_DST"

runner_count=0
for runner in "$RUNNERS_SRC"/*; do
  if [ ! -f "$runner" ] || [ ! -x "$runner" ]; then
    continue
  fi
  base="$(basename "$runner")"
  cp "$runner" "$RUNNERS_DST/$base"
  echo "  installed runner: ${base}"
  ((runner_count++)) || true
done

if [ "$runner_count" -eq 0 ]; then
  echo "WARNING: No executable runners found in ${RUNNERS_SRC}" >&2
fi

echo "Scripts installed — run 'kilo-session-report --help' to verify."
