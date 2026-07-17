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

run_cmd rm -rf "$DB_DIR"
log_ok "Cascade databases fully reset"
