#!/usr/bin/env bash
# Clear the NVM download cache ($NVM_DIR/.cache). Does NOT touch installed versions.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

NVM_CACHE_DIR="${NVM_DIR:-$HOME/.nvm}/.cache"

if [[ ! -d "$NVM_CACHE_DIR" ]]; then
  log_skip "NVM cache directory not found at $NVM_CACHE_DIR"
  exit 0
fi

size_before="$(human_size "$NVM_CACHE_DIR")"
log_info "removing NVM download cache (${size_before}) from $NVM_CACHE_DIR"
run_cmd rm -rf "$NVM_CACHE_DIR"

if [[ ! -d "$NVM_CACHE_DIR" ]]; then
  log_ok "removed NVM download cache (freed ${size_before})"
else
  log_err "failed to remove NVM download cache"
fi
