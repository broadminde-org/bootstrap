#!/usr/bin/env bash
# 40-docker.sh — Build Docker image (and optionally push)
#
# Generalized from the ee monorepo's infra/mcp/build.d/40-docker/run.sh:
# inline Dockerfile detection (no MCP_ROOT detector), build context is the
# project root. Tags <app>:{tag,version_tag,semver_tag} plus a
# registry-prefixed set when IMAGE_REGISTRY is non-empty; pushes all three
# registry tags when push is enabled. When IMAGE_TAG_EXPLICIT=true (the
# orchestrator sets this when --tag was given), the version/semver tags are
# neither built nor pushed — CI callers pass --tag sha-<8> and the
# v0.0.0-family tags would be junk. Installed by user/init.d/30-scripts
# into $HOME/scripts/build.d/40-docker.sh.
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

STEP_NAME="40-docker"
STEP_LABEL="Docker image build"

step_event "step_start" "$STEP_NAME" "$STEP_LABEL"
start_ms=$(date +%s%3N)

app="${BUILD_HOOK_APP}"
app_dir="${BUILD_HOOK_PROJECT_DIR}"
log_file="${BUILD_HOOK_LOG_FILE}"

dockerfile="${app_dir}/Dockerfile"

if [[ ! -f "$dockerfile" ]]; then
  append_log "### Docker Image Build"
  append_log ""
  append_log "**Docker Image: SKIPPED** — No Dockerfile"
  append_log ""
  step_event "step_skip" "$STEP_NAME" "$STEP_LABEL" "" "no Dockerfile"
  exit 0
fi

append_log "### Docker Image Build"
append_log ""
append_log '```'

log "[${app}] Building Docker image..."

registry="${BUILD_HOOK_REGISTRY}"
image_tag="${BUILD_HOOK_IMAGE_TAG}"
semver="${BUILD_HOOK_SEMVER}"
git_sha="${BUILD_HOOK_GIT_SHA}"
build_num="${BUILD_HOOK_BUILD_NUM}"
version_tag="${BUILD_HOOK_VERSION_TAG}"
semver_tag="v${semver}"

# Explicit --tag (CI passes sha-<8>) replaces the version tag family entirely:
# with no VERSION file they would be junk v0.0.0* tags on the registry.
_version_tags=true
if [[ "${BUILD_HOOK_IMAGE_TAG_EXPLICIT:-false}" == "true" ]]; then
  _version_tags=false
fi

declare -a build_tags=( -t "${app}:${image_tag}" )
if [[ -n "$registry" ]]; then
  build_tags+=( -t "${registry}/${app}:${image_tag}" )
fi
if $_version_tags; then
  build_tags+=( -t "${app}:${version_tag}" -t "${app}:${semver_tag}" )
  if [[ -n "$registry" ]]; then
    build_tags+=( -t "${registry}/${app}:${version_tag}" -t "${registry}/${app}:${semver_tag}" )
  fi
fi

_docker_rc=0
if [[ "${BUILD_HOOK_VERBOSE:-false}" == "true" ]]; then
  docker build "${build_tags[@]}" \
      --label org.opencontainers.image.version="${semver}" \
      --label org.opencontainers.image.revision="${git_sha}" \
      --label ee.build.number="${build_num}" \
      --label ee.build.time="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      -f "${dockerfile}" "${BUILD_HOOK_PROJECT_DIR}" 2>&1 | tee -a "${log_file}" || _docker_rc=$?
else
  docker build "${build_tags[@]}" \
      --label org.opencontainers.image.version="${semver}" \
      --label org.opencontainers.image.revision="${git_sha}" \
      --label ee.build.number="${build_num}" \
      --label ee.build.time="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      -f "${dockerfile}" "${BUILD_HOOK_PROJECT_DIR}" >> "${log_file}" 2>&1 || _docker_rc=$?
fi

if [[ $_docker_rc -eq 0 ]]; then

  append_log '```'
  ok "[${app}] Image built: ${app}:${image_tag}"
  append_log ""
  append_log "**Docker Image: SUCCESS** — ${app}:${image_tag}"

  # Push to registry if configured
  if [[ -n "$registry" && "${BUILD_HOOK_PUSH_IMAGE}" == "true" ]]; then
    append_log ""
    append_log "### Docker Image Push"
    append_log ""
    append_log '```'
    log "[${app}] Pushing ${registry}/${app}:${image_tag} ..."
    push_ok=true
    declare -a push_tags=( "${registry}/${app}:${image_tag}" )
    if $_version_tags; then
      push_tags+=( "${registry}/${app}:${version_tag}" "${registry}/${app}:${semver_tag}" )
    fi
    for push_tag in "${push_tags[@]}"; do
      if ! $push_ok; then break; fi
      if [[ "${BUILD_HOOK_VERBOSE:-false}" == "true" ]]; then
        if ! docker push "$push_tag" 2>&1 | tee -a "${log_file}"; then push_ok=false; fi
      else
        if ! docker push "$push_tag" >> "${log_file}" 2>&1; then push_ok=false; fi
      fi
    done
    append_log '```'
    if $push_ok; then
      ok "[${app}] Pushed ${registry}/${app}:${image_tag}"
      append_log ""
      append_log "**Docker Push: SUCCESS**"
    else
      fail "[${app}] Push failed (registry ${registry} unreachable?)"
      append_log ""
      append_log "**Docker Push: FAILED**"
      elapsed=$(( $(date +%s%3N) - start_ms ))
      step_event "step_fail" "$STEP_NAME" "$STEP_LABEL" "$elapsed" "docker push failed"
      exit 1
    fi
  elif [[ -z "$registry" ]]; then
    append_log ""
    append_log "**Docker Push: SKIPPED** — no IMAGE_REGISTRY configured"
  else
    append_log ""
    append_log "**Docker Push: SKIPPED** — --no-push flag"
  fi

  # Run post-docker hook
  run_build_hook "post-docker"

  elapsed=$(( $(date +%s%3N) - start_ms ))
  step_event "step_ok" "$STEP_NAME" "$STEP_LABEL" "$elapsed"
  exit 0
else
  append_log '```'
  append_log ""
  append_log "**Docker Image: FAILED** — Docker build failed"
  fail "[${app}] Docker build failed"

  elapsed=$(( $(date +%s%3N) - start_ms ))
  step_event "step_fail" "$STEP_NAME" "$STEP_LABEL" "$elapsed" "docker build failed"
  exit 1
fi
