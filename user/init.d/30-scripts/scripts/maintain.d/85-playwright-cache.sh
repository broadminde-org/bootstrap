#!/usr/bin/env bash
# @tier 3
# @sudo false
# @summary Remove Playwright browser binaries from user cache
#
# Removes $REAL_HOME/.cache/ms-playwright/ only.
# Does NOT touch system-level Playwright installs.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

CACHE_DIR="$REAL_HOME/.cache/ms-playwright"

if [[ ! -d "$CACHE_DIR" ]]; then
  log_skip "Playwright cache directory not found at $CACHE_DIR"
  exit 0
fi

size_before="$(human_size "$CACHE_DIR")"
log_info "removing Playwright browser cache (${size_before}) from $CACHE_DIR"
log_warn "'npx playwright install' will be needed before running E2E tests"
run_cmd rm -rf "$CACHE_DIR"

if [[ ! -d "$CACHE_DIR" ]]; then
  log_ok "removed Playwright browser cache (freed ${size_before})"
else
  log_err "failed to remove Playwright browser cache"
fi
