#!/usr/bin/env bash
# Report VSCodium server process RSS, extension sizes, caches, and dumps.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

CODIUM_SRV_DIR="$REAL_HOME/.vscodium-server"
CODIUM_DUMP_DIR="$REAL_HOME/.local/state/VSCodium"

codium_rss="$(ps -eo rss,command 2>/dev/null | awk '/codium-server|bootstrap-fork/ && !/awk/ {s+=$1} END {printf "%.0f", s/1024}')"
if [[ -n "$codium_rss" && "$codium_rss" -gt 0 ]]; then
  log_info "VSCodium procs:  ${codium_rss} MB RSS"
else
  log_info "VSCodium procs:  not running"
fi

if [[ -d "$CODIUM_SRV_DIR" ]]; then
  log_info "VSCodium server: $(human_size "$CODIUM_SRV_DIR")"
  for sub in bin extensions data; do
    sub_path="$CODIUM_SRV_DIR/$sub"
    if [[ -d "$sub_path" ]]; then
      log_info "  $sub: $(human_size "$sub_path")"
    fi
  done

  extensions_dir="$CODIUM_SRV_DIR/extensions"
  if [[ -d "$extensions_dir" ]]; then
    ext_count="$(find "$extensions_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
    log_info "  extensions: $ext_count installed"
    while IFS= read -r line; do
      log_info "    $line"
    done < <(du -sh "$extensions_dir"/*/ 2>/dev/null | sort -rh | head -5)
  fi

  cache_dir="$CODIUM_SRV_DIR/data/CachedExtensionVSIXs"
  if [[ -d "$cache_dir" ]]; then
    vsix_count="$(find "$cache_dir" -type f 2>/dev/null | wc -l)"
    log_info "  VSIX cache: $(human_size "$cache_dir") ($vsix_count files)"
  fi
else
  log_info "VSCodium server: not found"
fi

if [[ -d "$CODIUM_DUMP_DIR" ]]; then
  dump_count="$(find "$CODIUM_DUMP_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
  log_info "Crash dumps: $(human_size "$CODIUM_DUMP_DIR") ($dump_count directories)"
else
  log_info "Crash dumps: not found"
fi
