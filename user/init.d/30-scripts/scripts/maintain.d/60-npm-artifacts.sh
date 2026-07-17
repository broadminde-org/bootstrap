#!/usr/bin/env bash
# Remove build artifacts and SvelteKit caches from projects under $HOME.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

log_info "Scanning for artifacts in $HOME..."
cleaned=0
while IFS= read -r -d '' dir; do
  name="$(basename "$dir")"
  log_info "removing ${name}"
  run_cmd rm -rf "$dir"
  (( cleaned++ )) || true
done < <(find "$HOME" -maxdepth 5 -type d \( -name '.svelte-kit' -o -name 'dist' -o -name '.turbo' \) -print0 2>/dev/null)

if [[ $cleaned -eq 0 ]]; then
  log_ok "no build artifacts found"
else
  log_ok "cleaned $cleaned build artifact director(ies)"
fi
