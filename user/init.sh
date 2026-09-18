#!/usr/bin/env bash
set -euo pipefail

# init.sh — user-side bootstrap runner
#
# Second-tier bootstrap: runs AFTER the root `bootstrap/init.sh` has
# finished and a non-root deploy user exists. Log in as that user and
# run this script from the same cloned repo.
#
# The runner refuses to run as root — every step here installs per-user
# tooling into $HOME, not into /usr/local or /etc. If a step needs
# root, it does not belong in user; move it to
# bootstrap/init.d/.
#
# Steps may declare required capabilities via a `.requires` file in
# their step directory (one capability name per line). Capabilities
# are enabled/disabled in `bootstrap/bootstrap.conf.yml`. Steps
# without a `.requires` file always run.
#
# Supported step formats:
#   - Flat files:   NN-description.sh       (e.g., 10-create-tooling.sh)
#   - Directories:  NN-description/run.sh   (e.g., 20-python/run.sh)
#
# Disabled scripts use a `.disabled` suffix and are skipped.
#
# Usage:
#   ./init.sh                          # run all user-side steps
#   ./init.sh --from 20                # run from step 20 onward
#   ./init.sh 20                       # run only step 20

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INIT_DIR="$SCRIPT_DIR/init.d"

if [[ ! -d "$INIT_DIR" ]]; then
  echo "No init.d/ directory found — nothing to do."
  exit 0
fi

# ---------------------------------------------------------------------------
# Prerequisite check (non-root + base tooling)
# ---------------------------------------------------------------------------

if [[ $EUID -eq 0 ]]; then
  echo "Error: this script must NOT be run as root." >&2
  echo "Log in as the deploy user (e.g., luke) and rerun." >&2
  exit 1
fi

missing=0
for cmd in find xargs; do
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
        echo "Error: --from requires a numeric operand (e.g. --from 20)." >&2
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
. "$SCRIPT_DIR/../init.d/lib/conf.sh"

# resolve_conf_file applies the same hostname-override rule as the root-tier
# runner (<hostname>.conf.yml takes precedence), so both tiers always
# evaluate the same capability set.
CAPS_CONFIG="$(resolve_conf_file || true)"

# Export the runner-selected file so step subshells (lib/common.sh →
# load_conf with no arguments) resolve the same config (see conf.sh).
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
selector_matched=0

mapfile -t sorted_nums < <(printf "%s\n" "${!steps_by_num[@]}" | sort -n)

echo ""
echo "==========================================="
echo "  bootstrap user-side provisioning"
echo "  (running as $(id -un)@$(hostname))"
echo "==========================================="
echo ""

for num in "${sorted_nums[@]}"; do
  # Numeric comparison normalizes leading zeros, so `./init.sh 5`
  # selects 05-…. An unmatched selector is a hard error (checked after
  # the loop) — a typo must never silently run nothing.
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
    fi
  else
    chmod +x "$path"
    if "$path"; then
      echo "    done."
    else
      echo "    FAILED (exit $?)." >&2
      (( failed++ )) || true
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
  echo "$failed script(s) failed." >&2
  exit 1
fi

echo "All user init scripts completed successfully."
