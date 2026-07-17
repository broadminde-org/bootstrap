#!/usr/bin/env bash
# @tier 1
# @sudo false
# @summary Remove stale Kilo logs, plans, and session storage files
# Cleanup: logs >7d, plans >30d, session storage >14d.
# Combines former 15-kilo-logs.sh, 25-kilo-plans.sh, 32-kilo-storage.sh into a single step.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

EE_ROOT="$(detect_ee_root)"
total_removed=0
total_sections_run=0

# ---------------------------------------------------------------------------
# Section 1 — Kilo logs (>7d)
# ---------------------------------------------------------------------------
KILO_LOG_DIR="$REAL_HOME/.local/share/kilo/log"
RETENTION_LOGS=7

log_step "Kilo state cleanup — logs (>${RETENTION_LOGS}d), plans (>30d), storage (>14d)"

if [[ ! -d "$KILO_LOG_DIR" ]]; then
  log_skip "Kilo log directory not found at $KILO_LOG_DIR"
else
  count_before=$(find "$KILO_LOG_DIR" -maxdepth 1 -type f -name '*.log' | wc -l)
  if [[ $count_before -eq 0 ]]; then
    log_info "no Kilo log files found"
    total_sections_run=$((total_sections_run + 1))
  else
    candidates=$(find "$KILO_LOG_DIR" -maxdepth 1 -type f -name '*.log' -mtime "+${RETENTION_LOGS}" ! -name '.log-history' 2>/dev/null | wc -l)
    if [[ $candidates -eq 0 ]]; then
      log_info "no Kilo logs older than $RETENTION_LOGS days"
    else
      log_info "removing $candidates Kilo log file(s) older than $RETENTION_LOGS days from $KILO_LOG_DIR"
      run_cmd find "$KILO_LOG_DIR" -maxdepth 1 -type f -name '*.log' -mtime "+${RETENTION_LOGS}" ! -name '.log-history' -delete 2>/dev/null || true
      count_after=$(find "$KILO_LOG_DIR" -maxdepth 1 -type f -name '*.log' | wc -l)
      local_removed=$((count_before - count_after))
      total_removed=$((total_removed + local_removed))
      log_ok "removed $local_removed Kilo log file(s); $count_after remaining"
    fi
    total_sections_run=$((total_sections_run + 1))
  fi
fi

# ---------------------------------------------------------------------------
# Section 2 — Kilo plans (>30d)
# ---------------------------------------------------------------------------
PLANS_DIR="$EE_ROOT/.kilo/plans"
RETENTION_PLANS=30

if [[ ! -d "$PLANS_DIR" ]]; then
  log_skip "plans directory not found at $PLANS_DIR"
else
  count_before=$(find "$PLANS_DIR" -maxdepth 1 -type f -name '*.md' | wc -l)
  if [[ $count_before -eq 0 ]]; then
    log_info "no plan files found"
    total_sections_run=$((total_sections_run + 1))
  else
    candidates=$(find "$PLANS_DIR" -maxdepth 1 -type f -name '*.md' -mtime "+${RETENTION_PLANS}" 2>/dev/null | wc -l)
    if [[ $candidates -eq 0 ]]; then
      log_info "no plan files older than $RETENTION_PLANS days"
    else
      log_info "removing $candidates plan file(s) older than $RETENTION_PLANS days from $PLANS_DIR"
      run_cmd find "$PLANS_DIR" -maxdepth 1 -type f -name '*.md' -mtime "+${RETENTION_PLANS}" -delete 2>/dev/null || true
      count_after=$(find "$PLANS_DIR" -maxdepth 1 -type f -name '*.md' | wc -l)
      local_removed=$((count_before - count_after))
      total_removed=$((total_removed + local_removed))
      log_ok "removed $local_removed plan file(s); $count_after remaining"
    fi
    total_sections_run=$((total_sections_run + 1))
  fi
fi

# ---------------------------------------------------------------------------
# Section 3 — Kilo session storage (>14d)
# ---------------------------------------------------------------------------
STORAGE_DIR="$REAL_HOME/.local/share/kilo/storage"
RETENTION_STORAGE=14

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
  candidates=$(find "$target_dir" -maxdepth 1 -type f -name "$pattern" -mtime "+${RETENTION_STORAGE}" 2>/dev/null | wc -l)

  if [[ $candidates -eq 0 ]]; then
    log_info "no $pattern files older than $RETENTION_STORAGE days in $subdir"
    return
  fi

  local size_before
  size_before="$(human_size "$target_dir")"
  log_info "removing $candidates $pattern file(s) older than $RETENTION_STORAGE days from $subdir (${size_before})"
  run_cmd find "$target_dir" -maxdepth 1 -type f -name "$pattern" -mtime "+${RETENTION_STORAGE}" -delete 2>/dev/null || true

  local count_after
  count_after=$(find "$target_dir" -maxdepth 1 -type f -name "$pattern" 2>/dev/null | wc -l)
  local removed=$((count_before - count_after))
  total_removed=$((total_removed + removed))
  log_ok "removed $removed $pattern file(s) from $subdir; $count_after remaining"
}

clean_storage_subdir "session_diff" "ses_*.json"
clean_storage_subdir "session_share" "*"
total_sections_run=$((total_sections_run + 1))

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------
if [[ $total_removed -eq 0 ]]; then
  log_info "no stale Kilo state files to clean (${total_sections_run} section(s) checked)"
else
  log_ok "total stale Kilo state files removed: $total_removed (${total_sections_run} section(s) checked)"
fi
