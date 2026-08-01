# shellcheck shell=bash
# common.sh — Shared helpers for build and build.d/* steps
#
# Generalized from the ee monorepo's infra/mcp/build.d/common.sh (EE_ROOT →
# PROJECT_DIR renames, sep() added, hook dir keyed off BUILD_HOOK_PROJECT_DIR).
# Installed by user/init.d/30-scripts into $HOME/scripts/build.d/common.sh.
#
# Source at the top of any build.d/ step:
#   source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
#
# The orchestrator (scripts/build) also sources this for log/ok/warn/fail/sep.
# Steps expect BUILD_HOOK_* env vars from the build runner.

# Colors (disabled when stdout is not a TTY)
if [[ -t 1 ]]; then
  BOLD='\033[1m'; RED='\033[0;31m'; GREEN='\033[0;32m'
  YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
else
  BOLD=''; RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi

log()  { echo -e "${BLUE}==>${NC} $*"; }
ok()   { echo -e "${GREEN}  ✓${NC} $*"; }
warn() { echo -e "${YELLOW}  ⚠${NC} $*"; }
fail() { echo -e "${RED}  ✗${NC} $*" >&2; }
sep()  { echo ""; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }

# Emit a structured event to STEP_EVENTS_LOG (JSONL), if set.
step_event() {
  local event="$1" step="$2" label="$3" ms="${4:-}" err="${5:-}"
  [[ -z "${STEP_EVENTS_LOG:-}" ]] && return 0
  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  local json="{\"ts\":\"${ts}\",\"event\":\"${event}\",\"step\":\"${step}\",\"label\":\"${label}\""
  [[ -n "$ms" ]] && json="${json},\"ms\":${ms}"
  [[ -n "$err" ]] && json="${json},\"err\":\"${err}\""
  json="${json}}"
  echo "$json" >> "$STEP_EVENTS_LOG"
}

# Append to the build log file (BUILD_HOOK_LOG_FILE)
# When BUILD_HOOK_VERBOSE=true, also echo to stdout so the user sees live output.
append_log() {
  local line="$1"
  echo "$line" >> "${BUILD_HOOK_LOG_FILE:?}"
  if [[ "${BUILD_HOOK_VERBOSE:-false}" == "true" ]]; then
    echo "$line"
  fi
}

# Dump a markdown environment snapshot to build.md (Tier 2 diagnostic).
# Always file-only — never echoed to stdout, even in verbose mode.
dump_env_snapshot() {
  {
    echo ""
    echo "## Environment Snapshot"
    echo ""
    echo '```'
    go env GOPROXY GOSUMDB GONOSUMDB GONOPROXY GOTOOLCHAIN GOFLAGS GOWORK CGO_ENABLED GOARCH
    echo '```'
    echo ""
  } >> "${BUILD_HOOK_LOG_FILE:?}"
}

# Run a per-project build hook script from scripts/build-hooks/<name>
run_build_hook() {
  local hook_name="$1"
  shift
  local hook_script="${BUILD_HOOK_PROJECT_DIR}/scripts/build-hooks/${hook_name}"
  if [[ -x "$hook_script" ]]; then
    log "[${BUILD_HOOK_APP}] Running build hook: ${hook_name}"
    "$hook_script" "$@"
  fi
}
