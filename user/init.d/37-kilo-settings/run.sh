#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# Step 37: deploy canonical file inventory, retain extras and deselected skills.
# Selection controls installation/refresh, not removal or effective client
# discovery. Successful deployment is not proof of the active context set.
# JSONC rollback is file-scoped; earlier writes and their receipts remain.
STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_CONFIG="$STEP_DIR/_config/kilo"
SRC_KILOCODEIGNORE="$STEP_DIR/.kilocodeignore"
BOOTSTRAP_ROOT="$(cd "$STEP_DIR/../../.." && pwd)"
KILO_CONFIG="$HOME/.config/kilo"
KILO_HOME="$HOME/.kilo"

# shellcheck disable=SC1091
. "$STEP_DIR/resolve-python.sh"
PYTHON_BIN="$(resolve_kilo_python)" || exit 1
# Validate inventory, selection, redirected paths, state and destination types
# before any deployment writes or client validation.
"$PYTHON_BIN" "$STEP_DIR/context-files.py" preflight
"$STEP_DIR/migrate-kilo-jsonc.sh" --preflight "$SRC_CONFIG/kilo.jsonc" "$KILO_CONFIG/kilo.jsonc"

NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  echo 'ERROR: nvm is not installed; run 35-node and 36-kilo first.' >&2
  exit 1
fi
# shellcheck disable=SC1091
source "$NVM_DIR/nvm.sh" --no-use
nvm use --delete-prefix default >/dev/null
if ! command -v kilo >/dev/null 2>&1; then
  echo 'ERROR: kilo CLI is not available; run 36-kilo first.' >&2
  exit 1
fi

# Use the official client already supplied by step 36. No private capability
# protocol or implicit client installation; normal JSONC validation stays below.

mkdir -p "$KILO_CONFIG" "$KILO_HOME"
"$PYTHON_BIN" "$STEP_DIR/context-files.py" config
# Explicit retired files only. No legacy ownership is inferred: installations
# without authentic deployment receipts retain their old files for review.
"$PYTHON_BIN" "$STEP_DIR/context-files.py" retire

# Server definitions are create-once/user-maintained. Report no live values,
# even when the local file contains provider credentials or server arguments.
cfg_src="$SRC_CONFIG/kilo.json"
cfg_dst="$KILO_CONFIG/kilo.json"
if [[ ! -f "$cfg_dst" ]]; then
  cp "$cfg_src" "$cfg_dst"
  echo 'deployed kilo.json (new)'
elif ! cmp -s "$cfg_src" "$cfg_dst"; then
  echo 'kilo.json differs: manually review canonical server definitions; live values are not printed.'
else
  echo 'kilo.json unchanged'
fi

cfg_src="$SRC_CONFIG/kilo.jsonc"
cfg_dst="$KILO_CONFIG/kilo.jsonc"
if ! "$STEP_DIR/migrate-kilo-jsonc.sh" "$cfg_src" "$cfg_dst"; then
  echo 'JSONC rejected; earlier context writes/receipts are NOT rolled back.' >&2
  exit 1
fi

# Workspace-owned customization is preserved; never print a raw local diff.
dst="$BOOTSTRAP_ROOT/.kilocodeignore"
if [[ ! -f "$dst" ]]; then
  cp "$SRC_KILOCODEIGNORE" "$dst"
  echo 'deployed .kilocodeignore (new)'
elif ! cmp -s "$SRC_KILOCODEIGNORE" "$dst"; then
  echo '.kilocodeignore differs: review manually; existing customization preserved.'
fi

"$PYTHON_BIN" "$STEP_DIR/context-files.py" skills
echo '37-kilo-settings: canonical context deployed; extras and deselected optionals retained.'
echo 'Private per-file deployment receipts: ~/.local/state/bootstrap/kilo-context/'
echo 'JSONC validation/rollback does not restore the whole step.'
echo 'Seeded server definitions are retained; permissions do not prove tool visibility or connection state.'
echo 'Reload/restart only at the separately approved operator time.'
