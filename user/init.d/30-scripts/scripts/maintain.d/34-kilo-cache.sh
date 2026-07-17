#!/usr/bin/env bash
# Clear Kilo package cache ($HOME/.cache/kilo/packages/). Does NOT touch bin/.
# @tier 2
# @sudo false
# @summary Clear Kilo package cache
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

CACHE_DIR="$REAL_HOME/.cache/kilo"
PACKAGES_DIR="$CACHE_DIR/packages"

if [[ ! -d "$PACKAGES_DIR" ]]; then
  log_skip "Kilo package cache not found at $PACKAGES_DIR"
  exit 0
fi

size_before="$(human_size "$PACKAGES_DIR")"
log_info "removing Kilo package cache (${size_before}) from $PACKAGES_DIR"
run_cmd rm -rf "$PACKAGES_DIR"

if [[ ! -d "$PACKAGES_DIR" ]]; then
  log_ok "removed Kilo package cache (freed ${size_before})"
else
  log_err "failed to remove Kilo package cache"
fi
