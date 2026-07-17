#!/usr/bin/env bash
# @tier 3
# @sudo false
# @summary Clear Go module cache
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

if ! require_cmd go; then
  log_skip "go not installed"
  exit 0
fi

before="$(human_size "$(go env GOMODCACHE 2>/dev/null)")"
log_info "GOMODCACHE before: $before"
user_run go clean -modcache
after="$(human_size "$(go env GOMODCACHE 2>/dev/null)")"
log_ok "GOMODCACHE after: $after"
