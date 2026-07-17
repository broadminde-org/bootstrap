#!/usr/bin/env bash
# Delete VSCodium cached extension VSIX archives.
# Safe — extension download cache; extensions are re-downloaded on demand.
# @tier 2
# @sudo false
# @summary Delete VSCodium cached extension VSIX
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

CACHE_DIR="$REAL_HOME/.vscodium-server/data/CachedExtensionVSIXs"

if [[ ! -d "$CACHE_DIR" ]]; then
  log_skip "VSCodium VSIX cache directory not found at $CACHE_DIR"
  exit 0
fi

count_before=$(find "$CACHE_DIR" -type f 2>/dev/null | wc -l)
size_before=$(du -sh "$CACHE_DIR" 2>/dev/null | awk '{print $1}')

if [[ $count_before -eq 0 ]]; then
  log_info "VSCodium VSIX cache is already empty"
  exit 0
fi

log_info "removing $count_before cached VSIX file(s) (${size_before}) from $CACHE_DIR"
run_cmd rm -rf "$CACHE_DIR"/* 2>/dev/null || true

# Verify
count_after=$(find "$CACHE_DIR" -type f 2>/dev/null | wc -l)
log_ok "cleared VSCodium VSIX cache ($count_before files, ${size_before}); $count_after remaining"