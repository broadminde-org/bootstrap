#!/usr/bin/env bash
# Report Go cache and module cache sizes.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

if ! require_cmd go; then
  log_skip "go not installed"
  exit 0
fi

log_info "Global Go cache: $(human_size "$(go env GOCACHE 2>/dev/null)")"
log_info "Global module cache: $(human_size "$(go env GOMODCACHE 2>/dev/null)")"
