#!/usr/bin/env bash
set -euo pipefail

# maintain.d/run.sh — System maintenance and diagnostics orchestrator
#
# Usage:
#   maintain [N] [--tier N] [--all] [--from N] [--dry-run] [--list]
#   maintain check [--list]

#
#   N (bare number)  Run step N only, bypasses tiers
#   --tier N / -t N  Run steps up to tier N (default: 1), cumulative
#   all              Subcommand: run all tiers (alias for --tier 3)
#   --all            Flag alias for --tier 3
#   --from N         Run steps with number >= N, respects tier
#   --dry-run        Print actions without executing
#   --list           List steps with tier, sudo, and summary
#   check            Run diagnose.d steps (read-only); only --list is supported

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/env.sh"
source "${SCRIPT_ROOT}/lib/maintain-common.sh"

# -- Subcommand --
SUBCOMMAND="run"

# -- Options --
LIST_ONLY=0
DRY_RUN=0
TARGET_STEP=""       # bare number — step N only
FROM=""              # --from N
REQUESTED_TIER=1     # --tier N  (default 1)

# -- parse_metadata — read @tier/@sudo/@summary from lines 2-4 of a step script --
parse_metadata() {
  local step="$1" kind="$2"
  local val
  if [[ "$kind" == "summary" ]]; then
    val="$(grep '^# @summary ' "$step" 2>/dev/null | sed 's/^# @summary //')" || true
  else
    val="$(grep "^# @${kind} " "$step" 2>/dev/null | awk '{print $3}')" || true
  fi
  printf '%s' "${val:-}"
}

# -- step_num — extract numeric prefix from filename --
step_num() {
  printf '%s' "${1%%-*}"
}

# -- Parse CLI args --
while [[ $# -gt 0 ]]; do
  case "$1" in
    check|all)
      SUBCOMMAND="$1"
      if [[ "$SUBCOMMAND" == "all" ]]; then REQUESTED_TIER=3; fi
      shift
      ;;
    --list)   LIST_ONLY=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --from)   FROM="$2"; shift 2 ;;
    -t|--tier)
      REQUESTED_TIER="$2"
      [[ "$REQUESTED_TIER" =~ ^[0-9]+$ ]] || { echo "Invalid tier: $REQUESTED_TIER" >&2; exit 1; }
      shift 2
      ;;
    --only)
      echo "--only is removed; use bare step number instead (e.g. 'maintain 50')" >&2
      exit 1
      ;;
    --all)     REQUESTED_TIER=3; shift ;;
    --with-sudo)
      echo "--with-sudo is removed; run 'sudo maintain' when root is needed" >&2
      exit 1
      ;;
    -h|--help)
      cat <<'EOF'
Usage: maintain [N] [--tier N] [--all] [--from N] [--dry-run] [--list]
       maintain check [--list]

  N                Run step N only (e.g. maintain 50), bypasses tiers
  --tier N / -t N  Run steps up to tier N (default: 1), cumulative
  all              Subcommand: run all steps (alias for --tier 3)
  --all            Flag alias for --tier 3 (run all steps)
  --from N         Run steps with number >= N, respects tier
  --dry-run        Print actions without executing
  --list           List steps with metadata
  check            Run diagnose.d steps (read-only)

Examples:
  maintain                  # run tier-1 steps
  maintain --tier 2         # run tier-1 AND tier-2 steps
  maintain 50               # run only step 50 regardless of tier
  maintain --from 70        # run steps >=70, up to tier 1
  maintain --dry-run        # show what would run
  maintain --list           # show all steps with tier/sudo/summary
  maintain check --list     # show diagnostic steps
EOF
      exit 0
      ;;
    *)
      # Bare number — step N only
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        TARGET_STEP="$1"
        shift
      else
        echo "Unknown arg: $1" >&2; exit 1
      fi
      ;;
  esac
done

# -- For 'check', only --list is supported; reject other filters --
if [[ "$SUBCOMMAND" == "check" ]]; then
  if [[ "$LIST_ONLY" -eq 0 ]]; then
    if [[ -n "$TARGET_STEP" ]]; then
      echo "check does not support a bare step number; use 'maintain <N>' for action steps" >&2
      exit 1
    fi
    if [[ -n "$FROM" ]]; then
      echo "check does not support --from; use 'maintain check --list' to see diagnostics" >&2
      exit 1
    fi
    if [[ "$REQUESTED_TIER" -ne 1 ]]; then
      echo "check does not support --tier" >&2
      exit 1
    fi
  fi
fi

export DRY_RUN

# -- Determine step directories --
if [[ "$SUBCOMMAND" == "run" || "$SUBCOMMAND" == "all" ]]; then
  STEPS_DIR="${SCRIPT_ROOT}/maintain.d"
  LIST_HEADER="Action steps"
else
  STEPS_DIR="${SCRIPT_ROOT}/diagnose.d"
  LIST_HEADER="Diagnostic steps"
fi

# -- collect_steps — gather [0-9]*-*.sh from the steps directory --
collect_steps() {
  find "$STEPS_DIR" -maxdepth 1 -type f -name '[0-9]*-*.sh' -printf '%f\n' 2>/dev/null | sort -t- -k1,1n
}

# -- format_summary — extract summary from @summary metadata or filename --
format_summary() {
  local step_path="$1"
  local summary
  summary="$(parse_metadata "$step_path" "summary")"
  if [[ -n "$summary" ]]; then
    printf '%s' "$summary"
  else
    # Fallback: strip numeric prefix and .sh suffix
    local name="${step_path##*/}"
    name="${name#[0-9][0-9]-}"
    name="${name%.sh}"
    printf '%s' "$name"
  fi
}

# -- List mode --
if [[ $LIST_ONLY -eq 1 ]]; then
  printf '%s%s%s (%s):\n' "$BOLD" "$LIST_HEADER" "$NC" "$STEPS_DIR"
  printf '%4s %5s %5s %-23s %s\n' "  #" "Tier" "Sudo" "Name" "Summary"
  printf '%4s %5s %5s %-23s %s\n' "---" "----" "----" "----" "-------"

  while IFS= read -r step_file; do
    step_path="$STEPS_DIR/$step_file"
    num="" tier="" sudo_meta="" summary_str=""

    num="$(step_num "$step_file")"
    tier="$(parse_metadata "$step_path" "tier")"
    tier="${tier:-1}"
    sudo_meta="$(parse_metadata "$step_path" "sudo")"
    [[ "$sudo_meta" == "true" ]] && sudo_meta="yes" || sudo_meta="no"
    summary_str="$(format_summary "$step_path")"

    printf '%3s %-5s %-5s %-23s %s\n' "$num" "$tier" "$sudo_meta" "${step_file%.sh}" "$summary_str"
  done < <(collect_steps)
  exit 0
fi

# -- Run steps --
mapfile -t steps < <(collect_steps)

if [[ ${#steps[@]} -eq 0 ]]; then
  echo "No steps found in $STEPS_DIR." >&2
  exit 1
fi

failed=0
ran=0
skipped=0

for step_file in "${steps[@]}"; do
  step_path="$STEPS_DIR/$step_file"
  num="$(step_num "$step_file")"
  [[ "$num" =~ ^[0-9]+$ ]] || continue

  # Parse tier metadata (default 1)
  step_tier="$(parse_metadata "$step_path" "tier")"
  step_tier="${step_tier:-1}"

  # Bare number filter (overrides tier)
  if [[ -n "$TARGET_STEP" ]]; then
    [[ "$num" == "$TARGET_STEP" ]] || continue
  else
    # Tier filter
    [[ "$step_tier" -le "$REQUESTED_TIER" ]] || continue
  fi

  # --from filter
  if [[ -n "$FROM" ]]; then
    [[ $((10#$num)) -ge $((10#$FROM)) ]] || continue
  fi

  log_step "$step_file"
  if bash "$step_path"; then
    ran=$((ran + 1))
  else
    rc=$?
    log_err "step '$step_file' exited $rc"
    failed=$((failed + 1))
  fi
done

if [[ $ran -eq 0 && $failed -eq 0 ]]; then
  echo "No steps matched selection." >&2
  exit 1
fi
if [[ $failed -gt 0 ]]; then
  echo "$failed step(s) failed." >&2
  exit 1
fi
log_ok "$ran step(s) completed"
