#!/usr/bin/env bash
set -euo pipefail

# Preview known canonical file changes without printing live values. Apply only
# reviewed non-sensitive paths; JSON/JSONC, unknown/feature-owned resources,
# deletions and agent permission frontmatter are never imported.
# From any CWD:
#   /path/to/bootstrap/user/sync-kilo-context.sh
#   /path/to/bootstrap/user/sync-kilo-context.sh --apply config/rules/example.md
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP_DIR="$SCRIPT_DIR/init.d/37-kilo-settings"
HELPER="$STEP_DIR/context-files.py"
# shellcheck disable=SC1091
. "$STEP_DIR/resolve-python.sh"
PYTHON_BIN="$(resolve_kilo_python)" || exit 1
if [[ "${1:-}" == --apply ]]; then
  shift
  exec "$PYTHON_BIN" "$HELPER" apply "$@"
elif [[ "${1:-}" == --preview ]]; then
  shift
fi
exec "$PYTHON_BIN" "$HELPER" preview "$@"
