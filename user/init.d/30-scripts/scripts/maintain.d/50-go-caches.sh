#!/usr/bin/env bash
# @tier 2
# @sudo false
# @summary Clean Go build cache, tool caches, and compiled binaries
#
# Combines:
#   50-go-build-cache.sh   — go clean -cache
#   52-go-tool-caches.sh   — ~/.cache/goimports, ~/.cache/gopls, ~/.cache/golangci-lint
#   62-artifact-binaries.sh — ELF binaries in apps/*/tmp/
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

if ! require_cmd go; then
  log_skip "go not installed"
  exit 0
fi

# ── Phase 1: Go build cache ──────────────────────────────────────────────
before="$(human_size "$(go env GOCACHE 2>/dev/null)")"
log_info "GOCACHE before: $before"
user_run go clean -cache
after="$(human_size "$(go env GOCACHE 2>/dev/null)")"
log_ok "GOCACHE after: $after"

# ── Phase 2: Go tool caches ──────────────────────────────────────────────
CACHE_DIRS=(
  "$REAL_HOME/.cache/goimports"
  "$REAL_HOME/.cache/gopls"
  "$REAL_HOME/.cache/golangci-lint"
)

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

# ── Phase 3: Compiled ELF binaries in apps/*/tmp/ ────────────────────────
cleaned=0

while IFS= read -r -d '' tmp_dir; do
  [[ "$tmp_dir" =~ /apps/[^/]+/tmp$ ]] || continue

  local_freed=0
  while IFS= read -r -d '' binary; do
    if [[ -f "$binary" && ! -x "$binary" ]]; then continue; fi
    if [[ -f "$binary" ]] && file "$binary" 2>/dev/null | grep -q 'ELF'; then
      size="$(human_size "$binary")"
      log_info "  removing $(basename "$binary") ($size) from ${tmp_dir#$EE_ROOT/}"
      run_cmd rm -f "$binary"
      (( local_freed++ )) || true
    fi
  done < <(find "$tmp_dir" -maxdepth 1 -type f -print0 2>/dev/null)

  if [[ $local_freed -gt 0 ]]; then
    (( cleaned++ )) || true
  fi
done < <(find "$EE_ROOT/apps" -type d -name 'tmp' -print0 2>/dev/null)

if [[ $cleaned -eq 0 ]]; then
  log_info "no compiled binaries found in apps/*/tmp/"
else
  log_ok "removed binaries from $cleaned tmp director(ies)"
fi
