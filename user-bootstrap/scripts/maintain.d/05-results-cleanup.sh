#!/usr/bin/env bash
# Prune old timestamped run directories from results folders.
# Delegates to the shared retention.sh library (infra/mcp/lib/retention.sh)
# which filters by YYYYMMDD-HHMMSS name pattern, sorts lexicographically,
# and respects EE_RESULTS_KEEP (default 10, 0 = disabled).
# Types: test-results, build-results, update-results, step-results.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

# Source the canonical retention library
RETENTION_LIB="${EE_ROOT}/infra/mcp/lib/retention.sh"
if [[ ! -f "$RETENTION_LIB" ]]; then
  log_skip "retention.sh not found at $RETENTION_LIB"
  exit 0
fi
source "$RETENTION_LIB"

KEEP="${EE_RESULTS_KEEP:-10}"

# --- Main ---

# Find all results directories recursively under EE_ROOT.
# Covers: apps/*, apps/*/frontend, apps/shared, apps/shared/backend/*,
#         shared, shared/backend/*, apps/_all, and any nested locations.
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
  log_skip "no results directories found"
  exit 0
fi

log_info "scanning ${#results_dirs[@]} results director(ies) (keep: $KEEP)"

pruned=0
for rd in "${results_dirs[@]}"; do
  if prune_results_dir "$rd" "$KEEP"; then
    # prune_results_dir logs its own output; count directories that had work done
    (( pruned++ )) || true
  fi
done

if [[ $pruned -eq 0 ]]; then
  log_info "no results directories to prune"
else
  log_ok "scanned $pruned results director(ies)"
fi
