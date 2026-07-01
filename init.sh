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
# apps/netbird/init.sh).
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      sed -n '/^# Usage:/,/^$/p' "$0"
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
echo "  bootstrap host provisioning"
echo "==========================================="
echo ""

for num in "${sorted_nums[@]}"; do
  # Step selection.
  if [[ -n "$only_number" && "$num" != "$only_number" ]]; then
    continue
  fi
  if [[ -n "$from_number" ]] && (( 10#$num < 10#$from_number )); then
    continue
  fi

  path="${steps_by_num[$num]}"
  kind="${steps_kind[$num]}"
  name="$(basename "$path")"

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

echo "All bootstrap init scripts completed successfully."
