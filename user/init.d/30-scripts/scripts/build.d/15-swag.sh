#!/usr/bin/env bash
# 15-swag.sh — Run swag init to generate swagger.json for projects with a Go backend
#
# Generalized from the ee monorepo's infra/mcp/build.d/15-swag/run.sh
# (renames only; tolerate-failure semantics kept). Installed by
# user/init.d/30-scripts into $HOME/scripts/build.d/15-swag.sh.
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

STEP_NAME="15-swag"
STEP_LABEL="Swag (OpenAPI spec generation)"

step_event "step_start" "$STEP_NAME" "$STEP_LABEL"
start_ms=$(date +%s%3N)

backend_dir="${BUILD_HOOK_PROJECT_DIR}/backend"
if [[ ! -f "${backend_dir}/main.go" ]]; then
  append_log "### ${STEP_LABEL}"
  append_log ""
  append_log "**${STEP_LABEL}: SKIPPED** — no backend/main.go found"
  append_log ""
  step_event "step_skip" "$STEP_NAME" "$STEP_LABEL" "" "no backend/main.go"
  exit 0
fi

if ! command -v swag &>/dev/null; then
  append_log "### ${STEP_LABEL}"
  append_log ""
  append_log "**${STEP_LABEL}: SKIPPED** — swag not installed (run: go install github.com/swaggo/swag/cmd/swag@latest)"
  append_log ""
  step_event "step_skip" "$STEP_NAME" "$STEP_LABEL" "" "swag not installed"
  exit 0
fi

append_log "### ${STEP_LABEL}"
append_log ""
append_log '\`\`\`'
log "[${BUILD_HOOK_APP}] Running swag init..."

output_dir="${BUILD_HOOK_PROJECT_DIR}/docs/swagger"
mkdir -p "$output_dir"

_swag_rc=0
if [[ "${BUILD_HOOK_VERBOSE:-false}" == "true" ]]; then
  (cd "$backend_dir" && swag init -g main.go -o "../docs/swagger" --parseDependency --parseInternal) 2>&1 | tee -a "${BUILD_HOOK_LOG_FILE}" || _swag_rc=$?
else
  (cd "$backend_dir" && swag init -g main.go -o "../docs/swagger" --parseDependency --parseInternal) >> "${BUILD_HOOK_LOG_FILE}" 2>&1 || _swag_rc=$?
fi

if [[ $_swag_rc -eq 0 ]]; then
  append_log '\`\`\`'
  ok "[${BUILD_HOOK_APP}] OpenAPI spec generated → docs/swagger/swagger.json"
  append_log ""
  append_log "**${STEP_LABEL}: SUCCESS**"
  elapsed=$(( $(date +%s%3N) - start_ms ))
  step_event "step_ok" "$STEP_NAME" "$STEP_LABEL" "$elapsed"
else
  append_log '\`\`\`'
  warn "[${BUILD_HOOK_APP}] swag init failed (spec may be stale)"
  append_log ""
  append_log "**${STEP_LABEL}: FAILED** (non-fatal, continuing)"
  elapsed=$(( $(date +%s%3N) - start_ms ))
  step_event "step_ok" "$STEP_NAME" "$STEP_LABEL" "$elapsed" "swag init failed"
fi
