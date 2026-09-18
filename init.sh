#!/usr/bin/env bash
set -euo pipefail

# init.sh — bootstrap project initialization runner
#
# Runs all scripts in init.d/ in numeric order.
# Supports two formats:
#   - Flat files:   NN-description.sh       (e.g., 10-create-deploy-user.sh)
#   - Directories:  NN-description/run.sh   (e.g., 50-docker/run.sh)
#
# Disabled scripts use .disabled suffix and are skipped.
#
# Every script must be run as root (sudo) — bootstrap owns host
# provisioning only. To continue into a non-root deployment, log in
# as the deploy user and run that app's init.sh (e.g.
# apps/<app>/init.sh inside its own repository).
#
# Steps may declare required capabilities via a `.requires` file in
# their step directory (one capability name per line). Capabilities
# are enabled/disabled in `bootstrap.conf.yml`. Steps without a
# `.requires` file always run.
#
# Usage:
#   ./init.sh                          # run all steps
#   ./init.sh --from 25                # run from step 25 onward
#   ./init.sh 25                       # run only step 25

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INIT_DIR="$SCRIPT_DIR/init.d"

if [[ ! -d "$INIT_DIR" ]]; then
  echo "No init.d/ directory found — nothing to do."
  exit 0
fi

# ---------------------------------------------------------------------------
# Prerequisite check (root + base tooling)
# ---------------------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
  echo "Error: this script must be run as root (e.g., via sudo)." >&2
  exit 1
fi

missing=0
for cmd in apt-get curl find xargs; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "  [FAIL] $cmd not found in PATH" >&2
    missing=1
  fi
done
if (( missing )); then
  echo "Prerequisites missing. Install them and re-run." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

from_number=""
only_number=""

usage() { sed -n '/^# Usage:/,/^$/p' "$0"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --from)
      if [[ $# -lt 2 || ! "$2" =~ ^[0-9]+$ ]]; then
        echo "Error: --from requires a numeric operand (e.g. --from 25)." >&2
        usage >&2
        exit 1
      fi
      from_number="$2"
      shift 2
      ;;
    -*)
      echo "Error: unknown option '$1'." >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ "$1" =~ ^[0-9]+[^0-9].*$ ]]; then
        only_number="${1%%[^0-9]*}"
      elif [[ "$1" =~ ^[0-9]+$ ]]; then
        only_number="$1"
      else
        echo "Error: unrecognized argument '$1'." >&2
        usage >&2
        exit 1
      fi
      shift
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Load capability config
# ---------------------------------------------------------------------------

# shellcheck source=init.d/lib/conf.sh
. "$SCRIPT_DIR/init.d/lib/conf.sh"

# resolve_conf_file applies the hostname-override rule: <hostname>.conf.yml
# takes precedence over bootstrap.conf.yml when both exist.
CAPS_CONFIG="$(resolve_conf_file || true)"

# Export the runner-selected file so step subshells that re-source conf.sh
# and call load_conf with no arguments resolve the same config (see conf.sh).
if [[ -n "$CAPS_CONFIG" ]]; then
  export BOOTSTRAP_CONFIG_FILE="$CAPS_CONFIG"
fi

load_conf "$CAPS_CONFIG"

# ---------------------------------------------------------------------------
# Collect steps: flat files + directory scripts, sorted by numeric prefix
# ---------------------------------------------------------------------------

declare -A steps_by_num  # num -> path (file or dir)
declare -A steps_kind    # num -> "file" or "dir"

# Flat files: NN-name.sh (skip .disabled).
while IFS= read -r entry; do
  [[ -z "$entry" ]] && continue
  base="$(basename "$entry")"
  num="${base%%-*}"
  [[ "$num" =~ ^[0-9]+$ ]] || continue
  steps_by_num["$num"]="$entry"
  steps_kind["$num"]="file"
done < <(find "$INIT_DIR" -maxdepth 1 -type f -name '[0-9]*.sh' ! -name '*.disabled' | sort)

# Directory scripts: NN-name/run.sh (skip .disabled).
while IFS= read -r entry; do
  [[ -z "$entry" ]] && continue
  base="$(basename "$entry")"
  num="${base%%-*}"
  [[ "$num" =~ ^[0-9]+$ ]] || continue
  [[ -f "$entry/run.sh" ]] || continue
  steps_by_num["$num"]="$entry"
  steps_kind["$num"]="dir"
done < <(find "$INIT_DIR" -maxdepth 1 -type d -name '[0-9]*' ! -name '*.disabled' | sort)

if [[ ${#steps_by_num[@]} -eq 0 ]]; then
  echo "No scripts found in init.d/ — nothing to do."
  exit 0
fi

# ---------------------------------------------------------------------------
# Run steps in numeric order
# ---------------------------------------------------------------------------

failed=0
declare -a failed_names=()
selector_matched=0

mapfile -t sorted_nums < <(printf "%s\n" "${!steps_by_num[@]}" | sort -n)

echo ""
echo "==========================================="
echo "  bootstrap host provisioning"
echo "==========================================="
echo ""

for num in "${sorted_nums[@]}"; do
  # Step selection. Numeric comparison normalizes leading zeros, so
  # `./init.sh 5` selects 05-…. An unmatched selector is a hard error
  # (checked after the loop) — a typo must never silently run nothing.
  if [[ -n "$only_number" ]] && (( 10#$num != 10#$only_number )); then
    continue
  fi
  if [[ -n "$from_number" ]] && (( 10#$num < 10#$from_number )); then
    continue
  fi

  selector_matched=1
  path="${steps_by_num[$num]}"
  kind="${steps_kind[$num]}"
  name="$(basename "$path")"

  if ! step_requires_caps "$path"; then
    echo "--> $name  (skipped — capability not enabled)"
    echo ""
    continue
  fi

  echo "==> Running $name"
  if [[ "$kind" == "dir" ]]; then
    chmod +x "$path/run.sh"
    if (cd "$path" && ./run.sh); then
      echo "    done."
    else
      echo "    FAILED (exit $?)." >&2
      (( failed++ )) || true
      failed_names+=("$name")
    fi
  else
    chmod +x "$path"
    if "$path"; then
      echo "    done."
    else
      echo "    FAILED (exit $?)." >&2
      (( failed++ )) || true
      failed_names+=("$name")
    fi
  fi
  echo ""
done

if [[ -n "$only_number" && "$selector_matched" -eq 0 ]]; then
  echo "Error: no step matches selector '$only_number'." >&2
  echo "Available steps:" >&2
  for num in "${sorted_nums[@]}"; do
    echo "  $(basename "${steps_by_num[$num]}")" >&2
  done
  exit 1
fi

if [[ "$failed" -gt 0 ]]; then
  echo "" >&2
  echo "$failed script(s) failed:" >&2
  for name in "${failed_names[@]}"; do
    echo "  - $name" >&2
  done
  exit 1
fi

echo "All bootstrap init scripts completed successfully."
