#!/usr/bin/env bash
# @tier 3
# @sudo false
# @summary Clear stale Cascade indexing databases >14d
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

DB_DIR="$REAL_HOME/.codeium/windsurf/database"
if [[ ! -d "$DB_DIR" ]]; then
  log_skip "Cascade database directory not found"
  exit 0
fi

before="$(human_size "$DB_DIR")"
log_info "Cascade DB before: $before"
run_cmd find "$DB_DIR" -name '*.sqlite' -mtime +14 -delete
after="$(human_size "$DB_DIR")"
log_ok "Cascade DB after: $after"
