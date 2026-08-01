#!/usr/bin/env bash
# 30-binary.sh — Build Go binary into dist/<app>
#
# Generalized from the ee monorepo's infra/mcp/build.d/30-binary/run.sh:
# only the portable go.mod-detection branches are kept (all ./apps/<app>
# path branches deleted), hardcoded GOPROXY/GOSUMDB/GOTOOLCHAIN dropped in
# favor of a CGO_ENABLED default, and the --debug diagnostic is slimmed to
# the go.work section only. Installed by user/init.d/30-scripts into
# $HOME/scripts/build.d/30-binary.sh.
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

STEP_NAME="30-binary"
STEP_LABEL="Go binary build"

step_event "step_start" "$STEP_NAME" "$STEP_LABEL"
start_ms=$(date +%s%3N)

app="${BUILD_HOOK_APP}"
app_dir="${BUILD_HOOK_PROJECT_DIR}"
dist_dir="${BUILD_HOOK_DIST_DIR}"
log_file="${BUILD_HOOK_LOG_FILE}"

# Default-only CGO; proxy/toolchain settings come from the host environment.
: "${CGO_ENABLED:=0}"
export CGO_ENABLED

# Tier 2: dump environment snapshot at step start when verbose
if [[ "${BUILD_HOOK_VERBOSE:-false}" == "true" ]]; then
  dump_env_snapshot
fi

# Determine build directory and package from go.mod layout
go_build_dir="${app_dir}"
go_build_pkg="."

if [[ -f "${app_dir}/backend/go.mod" ]]; then
  go_build_dir="${app_dir}/backend"
  go_build_pkg="."
elif [[ -f "${app_dir}/go.mod" ]]; then
  go_build_dir="${app_dir}"
  if [[ -d "${app_dir}/backend" && -f "${app_dir}/backend/main.go" ]]; then
    go_build_pkg="./backend"
  else
    go_build_pkg="."
  fi
fi

append_log "### Go Binary Build"
append_log ""
append_log '\`\`\`'

log "[${app}] Building binary..."
mkdir -p "${dist_dir}"

# Common go build flags (extracted to avoid duplication between branches)
_go_ldflags="-s -w \
  -X main.Version=${BUILD_HOOK_SEMVER} \
  -X main.BuildNumber=${BUILD_HOOK_BUILD_NUM} \
  -X main.GitSHA=${BUILD_HOOK_GIT_SHA} \
  -X main.BuildTime=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Tier 1: when verbose, stream go build output to stdout AND build.md.
# When not verbose, capture silently to build.md only.
# Using separate branches avoids subshell/pid issues with background redirects.
_build_rc=0
if [[ "${BUILD_HOOK_VERBOSE:-false}" == "true" ]]; then
  go build \
    -C "${go_build_dir}" \
    -ldflags="${_go_ldflags}" \
    -o "${dist_dir}/${app}" \
    "${go_build_pkg}" 2>&1 | tee -a "${log_file}" || _build_rc=$?
else
  go build \
    -C "${go_build_dir}" \
    -ldflags="${_go_ldflags}" \
    -o "${dist_dir}/${app}" \
    "${go_build_pkg}" >> "${log_file}" 2>&1 || _build_rc=$?
fi

if [[ $_build_rc -eq 0 ]]; then

  append_log '\`\`\`'
  ok "[${app}] Binary built: dist/${app}"
  append_log ""
  append_log "**Binary: SUCCESS** — dist/${app}"

  # Run post-binary hook
  run_build_hook "post-binary"

  elapsed=$(( $(date +%s%3N) - start_ms ))
  step_event "step_ok" "$STEP_NAME" "$STEP_LABEL" "$elapsed"
  exit 0
else
  append_log '\`\`\`'
  append_log ""
  append_log "**Binary: FAILED** — Go build failed"
  fail "[${app}] Binary build failed"

  # Tier 3: when BUILD_HOOK_DEBUG=true and the error suggests a module resolution
  # problem, append diagnostics to build.md so the root cause is self-evident.
  # Always file-only — never echoed to stdout even in verbose mode.
  if [[ "${BUILD_HOOK_DEBUG:-false}" == "true" ]]; then
    # Search the full log for the tell-tale error string
    if grep -q "no required module provides package" "${log_file}" 2>/dev/null; then
      {
        echo ""
        echo "## Module Resolution Diagnostics"
        echo ""
        echo "_GOWORK value and workspace status:_"
        echo '```'
        echo "GOWORK=${GOWORK:-<unset>}"
        echo ""
        if [[ -f "${BUILD_HOOK_PROJECT_DIR}/go.work" ]]; then
          echo "# go.work contents:"
          cat "${BUILD_HOOK_PROJECT_DIR}/go.work"
          echo ""
        else
          echo "# go.work: not found in PROJECT_DIR"
          echo ""
        fi
        echo '```'
        echo ""
      } >> "${log_file}"
    fi
  fi

  elapsed=$(( $(date +%s%3N) - start_ms ))
  step_event "step_fail" "$STEP_NAME" "$STEP_LABEL" "$elapsed" "go build failed"
  exit 1
fi
