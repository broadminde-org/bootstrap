#!/usr/bin/env bash
# @tier 2
# @sudo false
# @summary Clean all Node.js ecosystem caches and build artifacts
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

skipped=()

# --- npm cache ---
log_step "npm cache"
if ! require_cmd npm; then
  log_skip "npm not installed"
  skipped+=(npm)
else
  CACHE_DIR="$REAL_HOME/.npm/_cacache"
  if [[ ! -d "$CACHE_DIR" ]]; then
    log_skip "npm cache directory not found at $CACHE_DIR"
    skipped+=(npm)
  else
    size_before="$(human_size "$CACHE_DIR")"
    log_info "npm cache before: $size_before"
    user_run npm cache clean --force
    size_after="$(human_size "$CACHE_DIR")"
    log_ok "npm cache after: $size_after"
  fi
fi

# --- NVM download cache ---
log_step "nvm download cache"
NVM_CACHE="${NVM_DIR:-$REAL_HOME/.nvm}/.cache"
if [[ ! -d "$NVM_CACHE" ]]; then
  log_skip "NVM cache directory not found at $NVM_CACHE"
  skipped+=(nvm)
else
  size_before="$(human_size "$NVM_CACHE")"
  log_info "removing NVM download cache (${size_before}) from $NVM_CACHE"
  run_cmd rm -rf "$NVM_CACHE"
  if [[ ! -d "$NVM_CACHE" ]]; then
    log_ok "removed NVM download cache (freed ${size_before})"
  else
    log_err "failed to remove NVM download cache"
  fi
fi

# --- build artifacts ---
log_step "build artifacts"
cleaned=0
for p in $(project_paths); do
  if [[ -d "$p/.svelte-kit" ]] || [[ -d "$p/dist" ]] || [[ -d "$p/.turbo" ]]; then
    log_info "Cleaning $(basename "$p")..."
    if [[ -d "$p/.svelte-kit" ]]; then run_cmd rm -rf "$p/.svelte-kit"; fi
    if [[ -d "$p/dist" ]]; then run_cmd rm -rf "$p/dist"; fi
    if [[ -d "$p/.turbo" ]]; then run_cmd rm -rf "$p/.turbo"; fi
    ((cleaned++))
  fi
done
log_ok "Cleaned build artifacts ($cleaned projects)"

# --- final skip summary ---
if [[ ${#skipped[@]} -gt 0 ]]; then
  log_info "skipped: ${skipped[*]}"
fi
