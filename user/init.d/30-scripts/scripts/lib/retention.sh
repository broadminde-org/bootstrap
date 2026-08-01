#!/usr/bin/env bash
# retention.sh — Shared helpers for results-directory retention / pruning.
#
# Generalized from the ee monorepo's infra/mcp/lib/retention.sh (EE_ROOT →
# PROJECT_DIR, including the safety guard). Installed by
# user/init.d/30-scripts into $HOME/scripts/lib/retention.sh.
#
# Source from any script that needs to prune old timestamped result directories
# (build-results/, test-results/, update-results/). Requires the sourcing
# script to have PROJECT_DIR set.
#
# Functions:
#   prune_results_dir <results_dir> [keep]
#       Prune old YYYYMMDD-HHMMSS timestamp directories inside <results_dir>,
#       keeping the newest <keep> entries plus the `latest` symlink target.
#       <keep> defaults to ${EE_RESULTS_KEEP:-10}. Set EE_RESULTS_KEEP=0 to
#       disable pruning entirely (early return).
#
# Algorithm:
#   1. Guard: return 0 if <results_dir> does not exist.
#   2. Safety: resolve with readlink -f; refuse if not under $PROJECT_DIR.
#   3. Collect dirs matching [0-9]{8}-[0-9]{6} (YYYYMMDD-HHMMSS).
#   4. Early return if count <= keep.
#   5. Sort descending by name (lexicographic — YYYYMMDD-HHMMSS is sortable).
#   6. Build protected set: newest N dirs + latest symlink target.
#   7. Delete unprotected dirs with rm -rf --.
#   8. Log: "✓ retention: pruned N old result(s), kept M in <dirname>"
#      (only when removed > 0).
#
# Failure mode:
#   Any error logs a warning to stderr and returns 0 — pruning never blocks
#   the caller. The whole function body is wrapped in defensive guards.

prune_results_dir() {
  local results_dir="${1:-}"
  local keep="${2:-${EE_RESULTS_KEEP:-10}}"

  # EE_RESULTS_KEEP=0 → pruning disabled
  if [[ "$keep" -eq 0 ]] 2>/dev/null; then
    return 0
  fi

  # Guard: directory must exist
  if [[ -z "$results_dir" || ! -d "$results_dir" ]]; then
    return 0
  fi

  # Safety guard: resolve and refuse paths outside PROJECT_DIR
  local resolved
  resolved="$(readlink -f "$results_dir" 2>/dev/null || echo "")"
  if [[ -z "$resolved" || "$resolved" != "${PROJECT_DIR:?PROJECT_DIR not set}"/* ]]; then
    echo "retention: refusing to prune outside PROJECT_DIR: $results_dir" >&2
    return 0
  fi

  # Collect timestamp directories (YYYYMMDD-HHMMSS)
  local ts_pattern='[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]'
  local -a all_dirs=()
  local d
  for d in "${results_dir}"/${ts_pattern}; do
    [[ -d "$d" ]] && all_dirs+=("$(basename "$d")")
  done

  local total=${#all_dirs[@]}

  # Early return if nothing to prune
  if [[ "$total" -le "$keep" ]]; then
    return 0
  fi

  # Sort descending by name (YYYYMMDD-HHMMSS is lexicographically sortable)
  local -a sorted_dirs=()
  local name
  while IFS= read -r name; do
    sorted_dirs+=("$name")
  done < <(printf '%s\n' "${all_dirs[@]}" | sort -r)

  # Build protected set: newest N + latest symlink target
  local -A protected=()
  local i
  for (( i=0; i<keep && i<total; i++ )); do
    protected["${sorted_dirs[$i]}"]=1
  done

  # Protect the `latest` symlink target (direct target, not resolved)
  local latest_link="${results_dir}/latest"
  if [[ -L "$latest_link" ]]; then
    local latest_target
    latest_target="$(readlink "$latest_link" 2>/dev/null || echo "")"
    if [[ -n "$latest_target" ]]; then
      # Strip any path component — symlink target should be a bare dirname
      latest_target="$(basename "$latest_target")"
      protected["$latest_target"]=1
    else
      echo "retention: latest symlink exists but target is empty/dangling in ${results_dir}" >&2
    fi
  fi

  # Delete unprotected directories
  local removed=0
  local kept=0
  for name in "${sorted_dirs[@]}"; do
    if [[ -z "${protected[$name]+_}" ]]; then
      rm -rf -- "${results_dir}/${name}"
      removed=$((removed + 1))
    else
      kept=$((kept + 1))
    fi
  done

  # Log only when something was pruned
  if [[ "$removed" -gt 0 ]]; then
    local dirname
    dirname="$(basename "$results_dir")"
    echo "  ✓ retention: pruned ${removed} old result(s), kept ${kept} in ${dirname}"
  fi

  return 0
}
