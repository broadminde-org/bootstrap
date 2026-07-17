#!/usr/bin/env bash
# Clear Go tool caches (goimports, gopls, golangci-lint). They regenerate on next use.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

if ! require_cmd go; then
  log_skip "go not installed"
  exit 0
fi

CACHE_DIRS=(
  "$HOME/.cache/goimports"
  "$HOME/.cache/gopls"
  "$HOME/.cache/golangci-lint"
)

total_freed=0
cleaned=0

for dir in "${CACHE_DIRS[@]}"; do
  name="$(basename "$dir")"
  if [[ ! -d "$dir" ]]; then
    log_skip "$name cache not found at $dir"
    continue
  fi

  size_before="$(human_size "$dir")"
  log_info "removing $name cache (${size_before}) from $dir"
  run_cmd rm -rf "$dir"

  if [[ ! -d "$dir" ]]; then
    log_ok "removed $name cache (freed ${size_before})"
    (( cleaned++ )) || true
  else
    log_warn "failed to remove $name cache"
  fi
done

if [[ $cleaned -eq 0 ]]; then
  log_info "no Go tool caches to clean"
else
  log_ok "cleaned $cleaned Go tool cache(s)"
fi
