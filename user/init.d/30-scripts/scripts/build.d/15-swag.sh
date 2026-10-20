#!/usr/bin/env bash
# Generate and optionally validate the project's Swagger specification.
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

STEP_NAME="15-swag"
STEP_LABEL="Swag (OpenAPI spec generation)"
strict="${BUILD_HOOK_GENERATE_STRICT:-false}"
project_dir="$BUILD_HOOK_PROJECT_DIR"
swag_dir="${BUILD_HOOK_SWAG_DIR:-backend}"
main_file="${BUILD_HOOK_SWAG_MAIN:-main.go}"
output_dir="${BUILD_HOOK_SWAG_OUTPUT:-docs/swagger}"
if [[ "$swag_dir" != /* ]]; then swag_dir="${project_dir}/${swag_dir}"; fi
if [[ "$output_dir" != /* ]]; then output_dir="${project_dir}/${output_dir}"; fi
swagger_json="${output_dir}/swagger.json"

step_event "step_start" "$STEP_NAME" "$STEP_LABEL"
start_ms=$(date +%s%3N)
append_log "### ${STEP_LABEL}"
append_log ""
append_log '```'

swag_fail() {
  local message="$1" elapsed
  append_log '```'
  append_log "**${STEP_LABEL}: FAILED** — ${message}"
  append_log ""
  elapsed=$(( $(date +%s%3N) - start_ms ))
  if [[ "$strict" == "true" ]]; then
    fail "[${BUILD_HOOK_APP}] ${message}"
    step_event "step_fail" "$STEP_NAME" "$STEP_LABEL" "$elapsed" "$message"
    exit 1
  fi
  warn "[${BUILD_HOOK_APP}] ${message}"
  step_event "step_ok" "$STEP_NAME" "$STEP_LABEL" "$elapsed" "$message"
  exit 0
}

if [[ ! -f "${swag_dir}/${main_file}" ]]; then
  if [[ "$strict" == "true" && ( -n "${BUILD_HOOK_SWAG_VERSION:-}" || -n "${BUILD_HOOK_SWAG_REQUIRED_PATHS:-}" ) ]]; then
    swag_fail "Swagger entrypoint not found: ${swag_dir}/${main_file}"
  fi
  append_log '```'
  append_log "**${STEP_LABEL}: SKIPPED** — no ${swag_dir}/${main_file} found"
  append_log ""
  step_event "step_skip" "$STEP_NAME" "$STEP_LABEL" "" "no Swagger entrypoint"
  exit 0
fi

if [[ -z "${BUILD_HOOK_SWAG_VERSION:-}" ]] && ! command -v swag &>/dev/null; then
  if [[ "$strict" == "true" ]]; then swag_fail "swag is not installed"; fi
  append_log '```'
  append_log "**${STEP_LABEL}: SKIPPED** — swag not installed (run: go install github.com/swaggo/swag/cmd/swag@latest)"
  append_log ""
  step_event "step_skip" "$STEP_NAME" "$STEP_LABEL" "" "swag not installed"
  exit 0
fi

mkdir -p "$output_dir"
declare -a swag_args=(init -g "$main_file" -o "$output_dir")
[[ "${BUILD_HOOK_SWAG_PARSE_DEPENDENCY:-true}" == "true" ]] && swag_args+=(--parseDependency)
[[ "${BUILD_HOOK_SWAG_PARSE_INTERNAL:-true}" == "true" ]] && swag_args+=(--parseInternal)
log "[${BUILD_HOOK_APP}] Generating Swagger..."
_swag_rc=0
if [[ -n "${BUILD_HOOK_SWAG_VERSION:-}" ]]; then
  if [[ "${BUILD_HOOK_VERBOSE:-false}" == "true" ]]; then
    (cd "$swag_dir" && go run "github.com/swaggo/swag/cmd/swag@${BUILD_HOOK_SWAG_VERSION}" "${swag_args[@]}") 2>&1 | tee -a "$BUILD_HOOK_LOG_FILE" || _swag_rc=$?
  else
    (cd "$swag_dir" && go run "github.com/swaggo/swag/cmd/swag@${BUILD_HOOK_SWAG_VERSION}" "${swag_args[@]}") >> "$BUILD_HOOK_LOG_FILE" 2>&1 || _swag_rc=$?
  fi
else
  if [[ "${BUILD_HOOK_VERBOSE:-false}" == "true" ]]; then
    (cd "$swag_dir" && swag "${swag_args[@]}") 2>&1 | tee -a "$BUILD_HOOK_LOG_FILE" || _swag_rc=$?
  else
    (cd "$swag_dir" && swag "${swag_args[@]}") >> "$BUILD_HOOK_LOG_FILE" 2>&1 || _swag_rc=$?
  fi
fi
if [[ $_swag_rc -ne 0 ]]; then swag_fail "Swagger generator failed"; fi

if [[ "$strict" == "true" ]]; then
  command -v jq >/dev/null 2>&1 || swag_fail "jq is required for strict Swagger validation"
  [[ -f "$swagger_json" ]] || swag_fail "Swagger JSON missing: ${swagger_json}"
  jq -e 'type == "object" and (.paths | type == "object")' "$swagger_json" >/dev/null 2>&1 || swag_fail "Malformed Swagger JSON: ${swagger_json}"
  if [[ -n "${BUILD_HOOK_SWAG_REQUIRED_PATHS:-}" ]]; then
    IFS=',' read -r -a required_paths <<< "$BUILD_HOOK_SWAG_REQUIRED_PATHS"
    for required_path in "${required_paths[@]}"; do
      required_path="${required_path#"${required_path%%[![:space:]]*}"}"
      required_path="${required_path%"${required_path##*[![:space:]]}"}"
      [[ -n "$required_path" ]] || swag_fail "Empty path in BUILD_SWAG_REQUIRED_PATHS"
      jq -e --arg path "$required_path" '(.paths | has($path))' "$swagger_json" >/dev/null || swag_fail "Required Swagger path missing: ${required_path}"
    done
  fi
fi

append_log '```'
ok "[${BUILD_HOOK_APP}] OpenAPI spec generated → ${swagger_json}"
append_log ""
append_log "**${STEP_LABEL}: SUCCESS**"
elapsed=$(( $(date +%s%3N) - start_ms ))
step_event "step_ok" "$STEP_NAME" "$STEP_LABEL" "$elapsed"
