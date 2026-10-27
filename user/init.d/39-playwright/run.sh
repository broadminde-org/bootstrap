#!/usr/bin/env bash
# 39-playwright — Install per-user Playwright CLI and browser binaries.
# System libraries belong to root-tier 06-playwright-deps (also dev-gated).
# shellcheck disable=SC1091
set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  echo "ERROR: nvm is not installed; run 35-node first." >&2
  exit 1
fi
source "$NVM_DIR/nvm.sh" --no-use
nvm use --delete-prefix default >/dev/null

if ! npm list -g --depth=0 @playwright/test >/dev/null 2>&1; then
  npm install -g @playwright/test
fi

# Do not use --with-deps: installing OS libraries needs root and belongs to
# root-tier 06-playwright-deps. Re-running restores a cleared browser cache.
playwright install chromium firefox webkit
echo "Playwright CLI and browsers installed for $HOME."
