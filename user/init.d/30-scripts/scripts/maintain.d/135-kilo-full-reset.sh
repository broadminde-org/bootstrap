#!/usr/bin/env bash
# @tier 3
# @sudo false
# @summary Wipe Kilo state directory entirely
#
# EXTREMELY DISRUPTIVE: total loss of agent state, session history, storage, and tool outputs.
# Only runs when explicitly enabled via --all flag.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

KILO_STATE_DIR="$REAL_HOME/.local/share/kilo"

if [[ ! -d "$KILO_STATE_DIR" ]]; then
  log_skip "Kilo state directory not found at $KILO_STATE_DIR"
  exit 0
fi

# Check if Kilo process is running
if pgrep -u "${SUDO_USER:-$USER}" -f 'kilo serve' >/dev/null 2>&1; then
  log_warn "Kilo process is running — cannot reset state while agent is active"
  log_info "stop Kilo first, then re-run with --all --only 45"
  exit 0
fi

size_total=$(du -sh "$KILO_STATE_DIR" 2>/dev/null | awk '{print $1}')

log_warn "WARNING: about to delete ALL Kilo state at $KILO_STATE_DIR (${size_total})"
log_info "this includes: logs, database, storage, snapshots, and tool output"

run_cmd rm -rf "$KILO_STATE_DIR" 2>/dev/null || {
  log_err "failed to remove $KILO_STATE_DIR"
  exit 1
}

log_ok "Kilo state directory deleted (${size_total} freed)"
log_info "Kilo will recreate state directories on next start"