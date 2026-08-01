#!/usr/bin/env bash
# 10-frontend.sh — Build frontend via npm
#
# Generalized from the ee monorepo's infra/mcp/build.d/10-frontend/run.sh:
# inline frontend/package.json detection (no MCP_ROOT detector), npm
# workspace build only when the project root package.json has "workspaces",
# otherwise a plain build inside frontend/. Installed by
# user/init.d/30-scripts into $HOME/scripts/build.d/10-frontend.sh.
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

STEP_NAME="10-frontend"
STEP_LABEL="Frontend build"

step_event "step_start" "$STEP_NAME" "$STEP_LABEL"
start_ms=$(date +%s%3N)

app_dir="${BUILD_HOOK_PROJECT_DIR}"
frontend_dir="${app_dir}/frontend"

if [[ ! -f "${frontend_dir}/package.json" ]]; then
  append_log "### Frontend Build"
  append_log ""
  append_log "**Frontend: SKIPPED** — No frontend/package.json"
  append_log ""
  step_event "step_skip" "$STEP_NAME" "$STEP_LABEL" "" "no frontend/package.json"
  exit 0
fi

append_log "### Frontend Build"
append_log ""
append_log '\`\`\`'

log "[${BUILD_HOOK_APP}] Building frontend..."

# Source nvm so npm is on PATH
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  # shellcheck disable=SC1091
  source "$NVM_DIR/nvm.sh"
fi

# npm workspace monorepo (root package.json declares "workspaces") → build
# the frontend workspace from the project root. Standalone frontend → build
# inside frontend/.
npm_dir="${frontend_dir}"
npm_build_cmd=(npm run build)
if [[ -f "${app_dir}/package.json" ]] && grep -q '"workspaces"' "${app_dir}/package.json"; then
  npm_dir="${app_dir}"
  npm_build_cmd=(npm run build --workspace=frontend)
fi

# Auto-install node_modules in the same dir the build runs from, if missing
if [[ ! -d "${npm_dir}/node_modules" ]]; then
  append_log ""
  append_log "node_modules missing — running npm ci in ${npm_dir}..."
  _npm_ci_rc=0
  if [[ "${BUILD_HOOK_VERBOSE:-false}" == "true" ]]; then
    (cd "$npm_dir" && npm ci) 2>&1 | tee -a "${BUILD_HOOK_LOG_FILE}" || _npm_ci_rc=$?
  else
    (cd "$npm_dir" && npm ci) >> "${BUILD_HOOK_LOG_FILE}" 2>&1 || _npm_ci_rc=$?
  fi
fi

_npm_rc=0
if [[ "${BUILD_HOOK_VERBOSE:-false}" == "true" ]]; then
  (cd "$npm_dir" && "${npm_build_cmd[@]}") 2>&1 | tee -a "${BUILD_HOOK_LOG_FILE}" || _npm_rc=$?
else
  (cd "$npm_dir" && "${npm_build_cmd[@]}") >> "${BUILD_HOOK_LOG_FILE}" 2>&1 || _npm_rc=$?
fi

if [[ $_npm_rc -eq 0 ]]; then
  append_log '\`\`\`'

  # Copy to static/built/ (for go:embed `all:built`) and to dist/frontend/ (for runtime-only Dockerfiles).
  # Generated output lives under a single `built/` subdir so a single .gitignore rule covers it
  # and any hand-authored assets under static/ (e.g. robots.txt) survive a rebuild.
  static_dir="${app_dir}/static"
  if [[ -d "${app_dir}/backend" && -f "${app_dir}/backend/main.go" ]]; then
    static_dir="${app_dir}/backend/static"
  fi

  mkdir -p "${static_dir}/built"
  # Only wipe the generated `built/` subdir — preserves any hand-authored files in static/.
  # The `*` glob skips dotfiles, so a tracked `.gitkeep` inside built/ survives every build.
  rm -rf "${static_dir:?}/built"/*
  frontend_build_dir=""
  if [[ -d "${frontend_dir}/build" ]]; then
    frontend_build_dir="${frontend_dir}/build"
  elif [[ -d "${frontend_dir}/dist" ]]; then
    frontend_build_dir="${frontend_dir}/dist"
  fi
  if [[ -n "${frontend_build_dir}" ]]; then
    cp -r "${frontend_build_dir}/." "${static_dir}/built/"
    mkdir -p "${BUILD_HOOK_DIST_DIR}/frontend"
    rm -rf "${BUILD_HOOK_DIST_DIR}/frontend"/*
    cp -r "${frontend_build_dir}/." "${BUILD_HOOK_DIST_DIR}/frontend/"
  fi

  ok "[${BUILD_HOOK_APP}] Frontend built"
  append_log ""
  append_log "**Frontend: SUCCESS**"

  elapsed=$(( $(date +%s%3N) - start_ms ))
  step_event "step_ok" "$STEP_NAME" "$STEP_LABEL" "$elapsed"
  exit 0
else
  append_log '\`\`\`'
  append_log ""
  append_log "**Frontend: FAILED** — npm build failed"
  fail "[${BUILD_HOOK_APP}] Frontend build failed"

  elapsed=$(( $(date +%s%3N) - start_ms ))
  step_event "step_fail" "$STEP_NAME" "$STEP_LABEL" "$elapsed" "npm build failed"
  exit 1
fi
