#!/usr/bin/env bash
# Clean the uv Python package cache ($HOME/.cache/uv).
# @tier 2
# @sudo false
# @summary Clean uv Python package cache
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

if ! require_cmd uv; then
  log_skip "uv not installed"
  exit 0
fi

CACHE_DIR="$REAL_HOME/.cache/uv"

if [[ ! -d "$CACHE_DIR" ]]; then
  log_skip "uv cache directory not found at $CACHE_DIR"
  exit 0
fi

size_before="$(human_size "$CACHE_DIR")"
log_info "uv cache before: $size_before"
# --force removes the cache even when another uv process holds its lock;
# no interactive prompt exists in that path, so no `yes |` cargo-cult.
# Tier 2: cache regenerates on next `uv sync`/`uv pip install`.
user_run uv cache clean --force 2>/dev/null
size_after="$(human_size "$CACHE_DIR")"
log_ok "uv cache after: $size_after"
