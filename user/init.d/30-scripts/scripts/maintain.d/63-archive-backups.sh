#!/usr/bin/env bash
# Remove old backup archives (>30 days) from the archive/ directory.
# @tier 1
# @sudo false
# @summary Remove old backup archives >30d
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

ARCHIVE_DIR="$EE_ROOT/archive"
RETENTION_DAYS="${ARCHIVE_RETENTION_DAYS:-30}"

if [[ ! -d "$ARCHIVE_DIR" ]]; then
  log_skip "archive directory not found at $ARCHIVE_DIR"
  exit 0
fi

candidates=$(find "$ARCHIVE_DIR" -maxdepth 1 -type f \( -name '*.tar.gz' -o -name '*.tgz' \) -mtime "+${RETENTION_DAYS}" 2>/dev/null | wc -l)

if [[ $candidates -eq 0 ]]; then
  log_info "no archive backups older than $RETENTION_DAYS days"
  exit 0
fi

size_before="$(human_size "$ARCHIVE_DIR")"
log_info "removing $candidates archive backup(s) older than $RETENTION_DAYS days (${size_before})"
run_cmd find "$ARCHIVE_DIR" -maxdepth 1 -type f \( -name '*.tar.gz' -o -name '*.tgz' \) -mtime "+${RETENTION_DAYS}" -delete 2>/dev/null || true
size_after="$(human_size "$ARCHIVE_DIR")"
log_ok "archive backups after cleanup: $size_after (was $size_before)"
