#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# Step 37: deploy canonical file inventory, retain extras and deselected skills.
# JSONC rollback is file-scoped; earlier writes and their receipts remain.
STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_CONFIG="$STEP_DIR/_config/kilo"
SRC_KILOCODEIGNORE="$STEP_DIR/.kilocodeignore"
BOOTSTRAP_ROOT="$(cd "$STEP_DIR/../../.." && pwd)"
KILO_CONFIG="$HOME/.config/kilo"
KILO_HOME="$HOME/.kilo"

command -v python3 >/dev/null 2>&1 || {
  echo 'ERROR: existing Python 3.10+ is required; run user step 20 first.' >&2
  exit 1
}
# Validate inventory, selection, redirected paths, state and destination types
# before any deployment writes or client validation.
python3 "$STEP_DIR/context-files.py" preflight
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

# Semantic feature admission precedes all context writes/retirement/receipts.
# This protocol is implemented by the corrected client, not inferred from a
# package version or permissively accepted unknown frontmatter. Never echo probe
# output: an unsupported executable may emit local configuration or credentials.
# pipefail requires BOTH successful client status and exact bytes. No arbitrary
# client output enters shell variables/arguments, including under inherited -x.
if ! kilo capabilities strict-custom-roles-v1 2>/dev/null |
    cmp -s - <(printf '%s\n' 'kilo-capability:strict-custom-roles-v1'); then
  echo 'ERROR: corrected strict-custom-roles-v1 client required; no context deployed. Installation and qualification require separate approval.' >&2
  exit 1
fi

mkdir -p "$KILO_CONFIG" "$KILO_HOME"
python3 "$STEP_DIR/context-files.py" config
# Explicit retired files only. No legacy ownership is inferred: installations
# without authentic deployment receipts retain their old files for review.
python3 "$STEP_DIR/context-files.py" retire

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

python3 "$STEP_DIR/context-files.py" skills
echo '37-kilo-settings: canonical context deployed; extras and deselected optionals retained.'
echo 'Private per-file deployment receipts: ~/.local/state/bootstrap/kilo-context/'
echo 'JSONC validation/rollback does not restore the whole step.'
echo 'Seeded server definitions are retained; permissions do not prove tool visibility or connection state.'
echo 'Reload/restart only at the separately approved operator time.'
