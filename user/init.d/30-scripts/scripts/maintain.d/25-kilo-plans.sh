#!/usr/bin/env bash
# Remove plan markdown files older than 30 days from ~/.kilo/plans/.
# Safe — read-only historical data; plans are small but accumulate over time.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

PLANS_DIR="$HOME/.kilo/plans"
RETENTION_DAYS=30

if [[ ! -d "$PLANS_DIR" ]]; then
  log_skip "plans directory not found at $PLANS_DIR"
  exit 0
fi

count_before=$(find "$PLANS_DIR" -maxdepth 1 -type f -name '*.md' | wc -l)

if [[ $count_before -eq 0 ]]; then
  log_info "no plan files found"
  exit 0
fi

candidates=$(find "$PLANS_DIR" -maxdepth 1 -type f -name '*.md' -mtime "+${RETENTION_DAYS}" 2>/dev/null | wc -l)

if [[ $candidates -eq 0 ]]; then
  log_info "no plan files older than $RETENTION_DAYS days"
  exit 0
fi

log_info "removing $candidates plan file(s) older than $RETENTION_DAYS days from $PLANS_DIR"
run_cmd find "$PLANS_DIR" -maxdepth 1 -type f -name '*.md' -mtime "+${RETENTION_DAYS}" -delete 2>/dev/null || true

count_after=$(find "$PLANS_DIR" -maxdepth 1 -type f -name '*.md' | wc -l)
log_ok "removed $((count_before - count_after)) plan file(s); $count_after remaining"