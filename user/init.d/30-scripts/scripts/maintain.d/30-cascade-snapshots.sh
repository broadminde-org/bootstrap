#!/usr/bin/env bash
# Clear stale Cascade snapshots (>24h old).
# @tier 1
# @sudo false
# @summary Clear stale Cascade snapshots >24h
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

CASCADE_DIR="$REAL_HOME/.codeium/windsurf/cascade"
if [[ ! -d "$CASCADE_DIR" ]]; then
  log_skip "Cascade directory not found"
  exit 0
fi

before="$(human_size "$CASCADE_DIR")"
log_info "Cascade snapshots before: $before"
run_cmd find "$CASCADE_DIR" -name '*.tmp' -type f -mtime +1 -delete
after="$(human_size "$CASCADE_DIR")"
log_ok "Cascade snapshots after: $after"
