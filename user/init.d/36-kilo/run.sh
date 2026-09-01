#!/usr/bin/env bash
# 36-kilo — Install the Kilo CLI from npm.
#
# This step runs after 35-node, which installs Node.js and npm. npm is the
# authoritative Kilo CLI distribution channel.
#
# KILO_VERSION accepts "latest" or an exact npm package version (no "v" prefix).
# The step is idempotent and cleans up stale Kilo CLI installs.

set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

PACKAGE='@kilocode/cli'
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  echo "ERROR: nvm is not installed; 35-node must run before 36-kilo." >&2
  exit 1
fi

# Re-select the Node version that 35-node installed.
source "$NVM_DIR/nvm.sh" --no-use
nvm use --delete-prefix "$EE_NODE_VERSION" >/dev/null

# Remove legacy native binary installs (from the former GitHub-release step).
rm -f "$HOME/.local/bin/kilo" "$HOME/.kilo/bin/kilo"

# Remove stale Kilo CLI from other nvm-managed Node trees. Global npm packages
# are Node-version-local, so an old tree can shadow the current one.
current_node_root="$(dirname "$(dirname "$(command -v node)")")"
for node_root in "$NVM_DIR"/versions/node/*/; do
  [[ -d "$node_root" ]] || continue
  [[ "$node_root" == "$current_node_root/" || "$node_root" == "$current_node_root" ]] && continue
  rm -rf "$node_root/lib/node_modules/$PACKAGE" "$node_root/bin/kilo"
done

# Resolve "latest" to a concrete version for the install command.
if [[ "$KILO_VERSION" == "latest" ]]; then
  KILO_VERSION="$(npm view "$PACKAGE" version --silent)"
fi

if [[ -z "$KILO_VERSION" ]]; then
  echo "ERROR: could not resolve ${PACKAGE} version." >&2
  exit 1
fi

# Install (idempotent — npm skips if already at this version).
echo "Installing ${PACKAGE}@${KILO_VERSION}..."
npm install --global "${PACKAGE}@${KILO_VERSION}"

kilo --version
