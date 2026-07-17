#!/usr/bin/env bash
set -euo pipefail

# maintain.d/run.sh — System maintenance and diagnostics for ee monorepo
#
# Usage:
#   maintain                   # Run maintenance steps (action steps) — default
#   maintain run [options]     # Run maintain.d steps (action steps)
#   maintain check [options]   # Run diagnose.d steps (read-only)
#
# Options:
#   --list             List all steps and exit (applicable to check or run)
#   --only N           Run only step number N (e.g. --only 20)
#   --from N           Run steps with number >= N
#   --all              Run *.sh.disabled steps too (maintain run only)
#   --dry-run          Print actions without executing (maintain run only)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/env.sh"
source "${SCRIPT_ROOT}/lib/maintain-common.sh"

# Subcommand (default: run)
SUBCOMMAND="run"

# Shared flags
ONLY=""
FROM=""
LIST_ONLY=0

# Run-specific flags
INCLUDE_ALL=0
DRY_RUN=0

# Parse args
remaining_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    check|run)
      SUBCOMMAND="$1"
      shift
      ;;
    --list) LIST_ONLY=1; shift ;;
    --only) ONLY="$2"; shift 2 ;;
    --from) FROM="$2"; shift 2 ;;
    --all) INCLUDE_ALL=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: maintain [command] [options]

Commands:
  run (default)     Run maintenance action steps (from maintain.d/)
  check             Run diagnostic steps (read-only from diagnose.d/)

Options (check & run):
  --list            List available steps
  --only N          Run only step number N
  --from N          Run steps with number >= N

Options (run only):
  --all             Include disabled (.sh.disabled) steps
  --dry-run         Print actions without executing

With no command, runs all maintenance steps.
EOF
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

export DRY_RUN

# Determine step directory based on subcommand
if [[ "$SUBCOMMAND" == "run" ]]; then
  STEPS_DIR="${SCRIPT_ROOT}/maintain.d"
  ENABLED_PATTERN='[0-9]*-*.sh'
  DISABLED_PATTERN='[0-9]*-*.sh.disabled'
  LIST_HEADER="Action steps"
else
  STEPS_DIR="${SCRIPT_ROOT}/diagnose.d"
  ENABLED_PATTERN='[0-9]*-*.sh'
  DISABLED_PATTERN=''
  LIST_HEADER="Diagnostic steps"
fi

# Colors (may already be set by maintain-common.sh, but ensure they exist)
if [[ -t 1 ]]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
  BLUE=$'\033[0;34m'; BOLD=$'\033[1m'; NC=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; BOLD=""; NC=""
fi

# Collect step files
collect_steps() {
  find "$STEPS_DIR" -maxdepth 1 -type f -name "$ENABLED_PATTERN" -printf '%f\n' 2>/dev/null | sort
  if [[ "$SUBCOMMAND" == "run" && $INCLUDE_ALL -eq 1 && -n "$DISABLED_PATTERN" ]]; then
    find "$STEPS_DIR" -maxdepth 1 -type f -name "$DISABLED_PATTERN" -printf '%f\n' 2>/dev/null | sort
  fi
}

step_num() {
  printf '%s' "${1%%-*}"
}

# List mode
if [[ $LIST_ONLY -eq 1 ]]; then
  printf '%s%s%s (%s):\n' "$BOLD" "$LIST_HEADER" "$NC" "$STEPS_DIR"
  find "$STEPS_DIR" -maxdepth 1 -type f -name "$ENABLED_PATTERN" -printf '  %f\n' 2>/dev/null | sort
  if [[ "$SUBCOMMAND" == "run" ]]; then
    printf '\n%sDisabled steps%s (run with --all):\n' "$BOLD" "$NC"
    find "$STEPS_DIR" -maxdepth 1 -type f -name "$DISABLED_PATTERN" -printf '  %f\n' 2>/dev/null | sort
  fi
  exit 0
fi

# Run steps
failed=0
ran=0
total_skipped=0
mapfile -t steps < <(collect_steps)

for step in "${steps[@]}"; do
  num="$(step_num "$step")"
  [[ "$num" =~ ^[0-9]+$ ]] || continue
  if [[ -n "$ONLY" && "$num" != "$ONLY" ]]; then continue; fi
  if [[ -n "$FROM" && $((10#$num)) -lt $((10#$FROM)) ]]; then continue; fi

  log_step "$step"
  if bash "$STEPS_DIR/$step"; then
    ran=$((ran + 1))
  else
    rc=$?
    log_err "step '$step' exited $rc"
    failed=$((failed + 1))
  fi
done

if [[ $ran -eq 0 && $failed -eq 0 && $total_skipped -eq 0 ]]; then
  echo "No steps matched selection." >&2
  exit 1
fi
if [[ $failed -gt 0 ]]; then
  echo "$failed step(s) failed." >&2
  exit 1
fi
log_ok "$ran step(s) completed"