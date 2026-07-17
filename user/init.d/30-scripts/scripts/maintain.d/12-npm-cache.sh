#!/usr/bin/env bash
# Clean the npm package cache (~/.npm/_cacache).
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

if ! require_cmd npm; then
  log_skip "npm not installed"
  exit 0
fi

CACHE_DIR="$HOME/.npm/_cacache"

if [[ ! -d "$CACHE_DIR" ]]; then
  log_skip "npm cache directory not found at $CACHE_DIR"
  exit 0
fi

size_before="$(human_size "$CACHE_DIR")"
log_info "npm cache before: $size_before"
run_cmd npm cache clean --force
size_after="$(human_size "$CACHE_DIR")"
log_ok "npm cache after: $size_after"
