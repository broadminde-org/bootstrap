#!/usr/bin/env bash
# Clear Go build cache. Does NOT touch the module cache (would force re-download).
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

if ! require_cmd go; then
  log_skip "go not installed"
  exit 0
fi

before="$(human_size "$(go env GOCACHE 2>/dev/null)")"
log_info "GOCACHE before: $before"
run_cmd go clean -cache
after="$(human_size "$(go env GOCACHE 2>/dev/null)")"
log_ok "GOCACHE after: $after"
