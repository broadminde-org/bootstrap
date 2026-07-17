#!/usr/bin/env bash
# Remove VSCodium crash/state dump directories older than 7 days.
# Safe — historical telemetry data; crash dumps are small but accumulate.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

DUMP_DIR="$HOME/.local/state/VSCodium"
RETENTION_DAYS=7

if [[ ! -d "$DUMP_DIR" ]]; then
  log_skip "VSCodium state directory not found at $DUMP_DIR"
  exit 0
fi

# Find date-stamped dump directories (e.g., 2026-05-25T... or similar)
count_before=$(find "$DUMP_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)

if [[ $count_before -eq 0 ]]; then
  log_info "no VSCodium dump directories found"
  exit 0
fi

candidates=$(find "$DUMP_DIR" -mindepth 1 -maxdepth 1 -type d -mtime "+${RETENTION_DAYS}" 2>/dev/null | wc -l)

if [[ $candidates -eq 0 ]]; then
  log_info "no VSCodium dump directories older than $RETENTION_DAYS days"
  exit 0
fi

log_info "removing $candidates VSCodium dump directory(ies) older than $RETENTION_DAYS days from $DUMP_DIR"
run_cmd find "$DUMP_DIR" -mindepth 1 -maxdepth 1 -type d -mtime "+${RETENTION_DAYS}" -exec rm -rf {} + 2>/dev/null || true

count_after=$(find "$DUMP_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
log_ok "removed $((count_before - count_after)) dump directory(ies); $count_after remaining"