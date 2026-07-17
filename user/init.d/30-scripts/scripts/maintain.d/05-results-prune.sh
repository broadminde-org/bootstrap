#!/usr/bin/env bash
# @tier 1
# @sudo false
# @summary Prune old results dirs and strip transient caches
#
# Phase 1 — Pruning: removes old YYYYMMDD-HHMMSS timestamped run
# directories from result folders, keeping the newest EE_RESULTS_KEEP
# entries (default 10). Delegates to infra/mcp/lib/retention.sh.
#
# Phase 2 — Cache stripping: removes .go-cache, .golangci-cache, and
# .tmp directories from inside the remaining timestamped test-results
# folders. These are transient build caches (~310MB per run) that
# regenerate on the next test — removing them does NOT delete any test
# output (.md files, raw logs, etc.).
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

RETENTION_LIB="${EE_ROOT}/infra/mcp/lib/retention.sh"
if [[ ! -f "$RETENTION_LIB" ]]; then
  log_skip "retention.sh not found at $RETENTION_LIB"
  exit 0
fi
source "$RETENTION_LIB"

KEEP="${EE_RESULTS_KEEP:-10}"

# ============================================================================
# Phase 1 — Prune old timestamped run directories by count
# ============================================================================
log_step "pruning old results directories (keep: $KEEP)"

results_dirs=()
while IFS= read -r -d '' rd; do
  results_dirs+=("$rd")
done < <(find "$EE_ROOT" -type d \( \
  -name 'test-results' -o \
  -name 'build-results' -o \
  -name 'update-results' -o \
  -name 'step-results' \
  \) -print0 2>/dev/null)

if [[ ${#results_dirs[@]} -eq 0 ]]; then
  log_skip "no results directories found — skipping prune"
else
  log_info "scanning ${#results_dirs[@]} results director(ies)"

  pruned=0
  for rd in "${results_dirs[@]}"; do
    if prune_results_dir "$rd" "$KEEP"; then
      (( pruned++ )) || true
    fi
  done

  if [[ $pruned -eq 0 ]]; then
    log_info "no results directories needed pruning"
  else
    log_ok "pruned $pruned results director(ies)"
  fi
fi

# ============================================================================
# Phase 2 — Strip transient build caches from remaining test-results dirs
# ============================================================================
log_step "stripping transient caches from test-results"

CACHE_NAMES=('.go-cache' '.golangci-cache' '.tmp')
cleaned_dirs=0
removed_caches=0

while IFS= read -r -d '' results_dir; do
  for ts_dir in "$results_dir"/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]; do
    [[ -d "$ts_dir" ]] || continue

    for cache in "${CACHE_NAMES[@]}"; do
      cache_path="$ts_dir/$cache"
      if [[ -d "$cache_path" ]]; then
        size="$(human_size "$cache_path")"
        run_cmd rm -rf "$cache_path"
        log_info "  removed $cache ($size) from $(basename "$ts_dir")"
        (( removed_caches++ )) || true
      fi
    done
    (( cleaned_dirs++ )) || true
  done
done < <(find "$EE_ROOT" -type d -name 'test-results' -print0 2>/dev/null)

if [[ $cleaned_dirs -eq 0 ]]; then
  log_info "no test-results directories found"
else
  log_ok "stripped $removed_caches cache(s) from $cleaned_dirs timestamped run director(ies)"
fi
