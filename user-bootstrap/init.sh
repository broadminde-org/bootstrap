#!/usr/bin/env bash
set -euo pipefail

# init.sh — user-side bootstrap runner
#
# Second-tier bootstrap: runs AFTER the root `bootstrap/init.sh` has
# finished and a non-root deploy user exists. Log in as that user and
# run this script from the same cloned repo:
#
#   cd bootstrap/user-bootstrap
#   ./init.sh                          # run all user-side steps
#   ./init.sh --from 20                # run from step 20 onward
#   ./init.sh 20                       # run only step 20
#
# The runner refuses to run as root — every step here installs per-user
# tooling into $HOME, not into /usr/local or /etc. If a step needs
# root, it does not belong in user-bootstrap; move it to
# bootstrap/init.d/.
#
# Steps may declare required capabilities via a `.requires` file in
# their step directory (one capability name per line). Capabilities
# are enabled/disabled in `bootstrap/bootstrap.conf.yml`. Steps
# without a `.requires` file always run.
#
# Supported step formats:
#   - Flat files:   NN-description.sh       (e.g., 10-create-tooling.sh)
#   - Directories:  NN-description/run.sh   (e.g., 20-tooling/run.sh)
#
# Disabled scripts use a `.disabled` suffix and are skipped.

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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      sed -n '/^# init.sh/,/^# Supported step formats:/p' "$0"
      exit 0
      ;;
    --from)
      from_number="$2"
      shift 2
      ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        only_number="$1"
      fi
      shift
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Load capability config
# ---------------------------------------------------------------------------

CAPS_CONFIG="$SCRIPT_DIR/../bootstrap.conf.yml"
# shellcheck source=../init.d/lib/caps.sh
. "$SCRIPT_DIR/../init.d/lib/caps.sh"
load_caps "$CAPS_CONFIG"

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

mapfile -t sorted_nums < <(printf "%s\n" "${!steps_by_num[@]}" | sort -n)

echo ""
echo "==========================================="
echo "  bootstrap user-side provisioning"
echo "  (running as $(id -un)@$(hostname))"
echo "==========================================="
echo ""

for num in "${sorted_nums[@]}"; do
  if [[ -n "$only_number" && "$num" != "$only_number" ]]; then
    continue
  fi
  if [[ -n "$from_number" ]] && (( 10#$num < 10#$from_number )); then
    continue
  fi

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

if [[ "$failed" -gt 0 ]]; then
  echo "$failed script(s) failed." >&2
  exit 1
fi

echo "All user-bootstrap init scripts completed successfully."
