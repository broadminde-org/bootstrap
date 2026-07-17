#!/usr/bin/env bash
# Remove old Kilo session diff and session share JSON files (>14 days).
# Safe — historical session data; current sessions are unaffected.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

STORAGE_DIR="$HOME/.local/share/kilo/storage"
RETENTION_DAYS=14

total_removed=0

clean_storage_subdir() {
  local subdir="$1"
  local pattern="$2"
  local target_dir="$STORAGE_DIR/$subdir"

  if [[ ! -d "$target_dir" ]]; then
    log_skip "$subdir directory not found at $target_dir"
    return
  fi

  local count_before
  count_before=$(find "$target_dir" -maxdepth 1 -type f -name "$pattern" 2>/dev/null | wc -l)

  if [[ $count_before -eq 0 ]]; then
    log_info "no $pattern files found in $subdir"
    return
  fi

  local candidates
  candidates=$(find "$target_dir" -maxdepth 1 -type f -name "$pattern" -mtime "+${RETENTION_DAYS}" 2>/dev/null | wc -l)

  if [[ $candidates -eq 0 ]]; then
    log_info "no $pattern files older than $RETENTION_DAYS days in $subdir"
    return
  fi

  local size_before
  size_before="$(human_size "$target_dir")"
  log_info "removing $candidates $pattern file(s) older than $RETENTION_DAYS days from $subdir (${size_before})"
  run_cmd find "$target_dir" -maxdepth 1 -type f -name "$pattern" -mtime "+${RETENTION_DAYS}" -delete 2>/dev/null || true

  local count_after
  count_after=$(find "$target_dir" -maxdepth 1 -type f -name "$pattern" 2>/dev/null | wc -l)
  local removed=$((count_before - count_after))
  total_removed=$((total_removed + removed))
  log_ok "removed $removed $pattern file(s) from $subdir; $count_after remaining"
}

clean_storage_subdir "session_diff" "ses_*.json"
clean_storage_subdir "session_share" "*"

if [[ $total_removed -eq 0 ]]; then
  log_info "no Kilo storage files to clean"
else
  log_ok "total Kilo storage files removed: $total_removed"
fi
