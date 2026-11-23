#!/usr/bin/env bash
set -euo pipefail

# Preview known canonical file changes without printing live values. Apply only
# reviewed non-sensitive paths; JSON/JSONC, unknown/feature-owned resources,
# deletions and agent permission frontmatter are never imported.
# From any CWD:
#   /path/to/bootstrap/user/sync-kilo-context.sh
#   /path/to/bootstrap/user/sync-kilo-context.sh --apply config/rules/example.md
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/init.d/37-kilo-settings/context-files.py"
if [[ "${1:-}" == --apply ]]; then
  shift
  exec python3 "$HELPER" apply "$@"
elif [[ "${1:-}" == --preview ]]; then
  shift
fi
exec python3 "$HELPER" preview "$@"
