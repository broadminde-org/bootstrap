#!/usr/bin/env bash
# 20-go-generate.sh — Run go generate (e.g. to populate a route source map)
#
# Generalized from the ee monorepo's infra/mcp/build.d/20-go-generate/run.sh:
# renames only, plus the hardcoded GOPROXY/GOSUMDB/GOTOOLCHAIN env was
# dropped — CGO_ENABLED defaults to 0 and the host environment provides
# proxy settings. Tolerate-failure semantics kept: a broken generator never
# breaks the build. Installed by user/init.d/30-scripts into
# $HOME/scripts/build.d/20-go-generate.sh.
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

STEP_NAME="20-go-generate"
STEP_LABEL="Go generate (sourcemap)"

step_event "step_start" "$STEP_NAME" "$STEP_LABEL"
start_ms=$(date +%s%3N)

# Default-only CGO; proxy/toolchain settings come from the host environment.
: "${CGO_ENABLED:=0}"
export CGO_ENABLED

append_log "### Go Generate (sourcemap)"
append_log ""
append_log '\`\`\`'
log "[${BUILD_HOOK_APP}] Running go generate..."

gen_dir="${BUILD_HOOK_PROJECT_DIR}"
if [[ -f "${BUILD_HOOK_PROJECT_DIR}/backend/go.mod" ]]; then
  gen_dir="${BUILD_HOOK_PROJECT_DIR}/backend"
elif [[ -f "${BUILD_HOOK_PROJECT_DIR}/go.mod" ]]; then
  gen_dir="${BUILD_HOOK_PROJECT_DIR}"
fi

_gen_rc=0
if [[ "${BUILD_HOOK_VERBOSE:-false}" == "true" ]]; then
  (cd "$gen_dir" && go generate ./...) 2>&1 | tee -a "${BUILD_HOOK_LOG_FILE}" || _gen_rc=$?
else
  (cd "$gen_dir" && go generate ./...) >> "${BUILD_HOOK_LOG_FILE}" 2>&1 || _gen_rc=$?
fi

if [[ $_gen_rc -eq 0 ]]; then
  append_log '\`\`\`'
  ok "[${BUILD_HOOK_APP}] go generate done"
  append_log ""
  append_log "**Go Generate: SUCCESS**"
  elapsed=$(( $(date +%s%3N) - start_ms ))
  step_event "step_ok" "$STEP_NAME" "$STEP_LABEL" "$elapsed"
else
  append_log '\`\`\`'
  warn "[${BUILD_HOOK_APP}] go generate failed (generated code may be stale)"
  append_log ""
  append_log "**Go Generate: FAILED** (continuing)"
  elapsed=$(( $(date +%s%3N) - start_ms ))
  step_event "step_ok" "$STEP_NAME" "$STEP_LABEL" "$elapsed" "go generate failed"
fi
