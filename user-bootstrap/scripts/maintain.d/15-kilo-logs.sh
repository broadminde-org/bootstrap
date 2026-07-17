#!/usr/bin/env bash
# Remove Kilo log files older than 7 days.
# Safe — Kilo holds the current log via open file handle; old rotated copies can be removed.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

KILO_LOG_DIR="$HOME/.local/share/kilo/log"
RETENTION_DAYS=7

if [[ ! -d "$KILO_LOG_DIR" ]]; then
  log_skip "Kilo log directory not found at $KILO_LOG_DIR"
  exit 0
fi

# Count candidates before removal
count_before=$(find "$KILO_LOG_DIR" -maxdepth 1 -type f -name '*.log' | wc -l)

if [[ $count_before -eq 0 ]]; then
  log_info "no Kilo log files found"
  exit 0
fi

# Use -mtime and exclude .log-history tracking file
candidates=$(find "$KILO_LOG_DIR" -maxdepth 1 -type f -name '*.log' -mtime "+${RETENTION_DAYS}" ! -name '.log-history' 2>/dev/null | wc -l)

if [[ $candidates -eq 0 ]]; then
  log_info "no Kilo logs older than $RETENTION_DAYS days"
  exit 0
fi

log_info "removing $candidates Kilo log file(s) older than $RETENTION_DAYS days from $KILO_LOG_DIR"
run_cmd find "$KILO_LOG_DIR" -maxdepth 1 -type f -name '*.log' -mtime "+${RETENTION_DAYS}" ! -name '.log-history' -delete 2>/dev/null || true

count_after=$(find "$KILO_LOG_DIR" -maxdepth 1 -type f -name '*.log' | wc -l)
log_ok "removed $((count_before - count_after)) Kilo log file(s); $count_after remaining"