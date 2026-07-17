#!/usr/bin/env bash
# Remove build artifacts and SvelteKit caches across projects.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

log_info "Scanning for artifacts in projects..."
for p in $(project_paths); do
  if [[ -d "$p/.svelte-kit" ]] || [[ -d "$p/dist" ]] || [[ -d "$p/.turbo" ]]; then
    log_info "Cleaning $(basename "$p")..."
    if [[ -d "$p/.svelte-kit" ]]; then run_cmd rm -rf "$p/.svelte-kit"; fi
    if [[ -d "$p/dist" ]]; then run_cmd rm -rf "$p/dist"; fi
    if [[ -d "$p/.turbo" ]]; then run_cmd rm -rf "$p/.turbo"; fi
  fi
done
log_ok "Cleaned build artifacts"
