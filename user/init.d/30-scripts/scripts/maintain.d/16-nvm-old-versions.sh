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
# Also read alias/default as a fallback (normalise: add 'v' prefix if
# missing). Only numeric aliases resolve to an installed dir — symbolic
# aliases (lts/*, node, stable) do not and must not be treated as one.
alias_ver=""
if [[ -f "$NVM_DIR/alias/default" ]]; then
  raw_alias="$(cat "$NVM_DIR/alias/default")"
  if [[ "$raw_alias" =~ ^v?[0-9] ]]; then
    alias_ver="$raw_alias"
    [[ "$alias_ver" == v* ]] || alias_ver="v$alias_ver"
  fi
fi

# Total-deletion guard: with neither reference resolvable, every installed
# version would fail the keep-match below and ALL of them would be removed.
if [[ -z "$active" && -z "$alias_ver" ]]; then
  log_skip "cannot determine the active Node version (no node on PATH, no resolvable ~/.nvm/alias/default) — refusing to prune"
  exit 0
fi

# Keep-match: exact, or prefix-match a partial alias against installed
# dirs (alias "24" / "v24" keeps installed "v24.15.0").
is_keeper() {
  local ver="$1" keeper
  for keeper in "$active" "$alias_ver"; do
    [[ -z "$keeper" ]] && continue
    if [[ "$ver" == "$keeper" || "$ver" == "$keeper".* ]]; then
      return 0
    fi
  done
  return 1
}

removed=0
for ver_dir in "$VERSIONS_DIR"/*; do
  [[ -d "$ver_dir" ]] || continue
  ver="$(basename "$ver_dir")"
  if is_keeper "$ver"; then
    log_info "keeping active version: $ver"
    continue
  fi
  size="$(human_size "$ver_dir")"
  log_info "removing old NVM version: $ver ($size)"
  run_cmd rm -rf "$ver_dir"
  removed=$((removed + 1))
done

if [[ $removed -eq 0 ]]; then log_info "no old NVM versions to remove"; else log_ok "removed $removed old NVM version(s)"; fi
