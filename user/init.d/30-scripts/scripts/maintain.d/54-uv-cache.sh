#!/usr/bin/env bash
# Clean the uv Python package cache ($HOME/.cache/uv).
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

if ! require_cmd uv; then
  log_skip "uv not installed"
  exit 0
fi

CACHE_DIR="$HOME/.cache/uv"

if [[ ! -d "$CACHE_DIR" ]]; then
  log_skip "uv cache directory not found at $CACHE_DIR"
  exit 0
fi

size_before="$(human_size "$CACHE_DIR")"
log_info "uv cache before: $size_before"
run_cmd uv cache clean
size_after="$(human_size "$CACHE_DIR")"
log_ok "uv cache after: $size_after"
