#!/usr/bin/env bash
# Remove old Node.js versions installed via NVM, keeping only the active/default version.
# @tier 2
# @sudo false
# @summary Remove old Node.js versions via NVM
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

NVM_DIR="${NVM_DIR:-$REAL_HOME/.nvm}"
VERSIONS_DIR="$NVM_DIR/versions/node"

if [[ ! -d "$VERSIONS_DIR" ]]; then log_skip "NVM versions directory not found at $VERSIONS_DIR"; exit 0; fi

# Determine active version. NVM aliases may omit the 'v' prefix, and the
# alias/default may be stale — prefer `node --version` when NVM is loaded.
active=""
if command -v node >/dev/null 2>&1; then
  active="$(node --version)"  # e.g. v24.15.0
fi
# Also read alias/default as a fallback (normalise: add 'v' prefix if missing)
alias_ver=""
if [[ -f "$NVM_DIR/alias/default" ]]; then
  alias_ver="$(cat "$NVM_DIR/alias/default")"
  [[ "$alias_ver" == v* ]] || alias_ver="v$alias_ver"
fi

removed=0
for ver_dir in "$VERSIONS_DIR"/*; do
  [[ -d "$ver_dir" ]] || continue
  ver="$(basename "$ver_dir")"
  if [[ (-n "$active" && "$ver" == "$active") || (-n "$alias_ver" && "$ver" == "$alias_ver") ]]; then
    log_info "keeping active version: $ver"
    continue
  fi
  size="$(human_size "$ver_dir")"
  log_info "removing old NVM version: $ver ($size)"
  run_cmd rm -rf "$ver_dir"
  removed=$((removed + 1))
done

if [[ $removed -eq 0 ]]; then log_info "no old NVM versions to remove"; else log_ok "removed $removed old NVM version(s)"; fi
