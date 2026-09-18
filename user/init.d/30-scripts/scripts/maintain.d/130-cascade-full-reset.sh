#!/usr/bin/env bash
# @tier 3
# @sudo false
# @summary Full reset of Cascade indexing databases
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

DB_DIR="$REAL_HOME/.codeium/windsurf/database"
if [[ ! -d "$DB_DIR" ]]; then
  log_skip "Cascade database directory not found"
  exit 0
fi

# Running-process guard — deleting the DB under a live editor corrupts
# its indexing state. (kilo_running is the Kilo equivalent; Cascade
# state belongs to the Windsurf editor.)
if pgrep -u "${SUDO_USER:-$USER}" -fi 'windsurf' >/dev/null 2>&1; then
  log_warn "Windsurf process is running — cannot reset Cascade databases while active"
  log_info "stop Windsurf first, then re-run"
  exit 0
fi

run_cmd rm -rf "$DB_DIR"
log_ok "Cascade databases fully reset"
