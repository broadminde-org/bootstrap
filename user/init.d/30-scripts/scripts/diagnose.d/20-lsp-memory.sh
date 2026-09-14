#!/usr/bin/env bash
# Report RSS memory usage per language server.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

LSP_NAMES=("gopls" "tsserver" "typescript-language-server" "svelte-language-server" "pyright" "jsonServerMain" "cssServerMain" "htmlServerMain" "markdownServerMain")

for name in "${LSP_NAMES[@]}"; do
  mem_mb="$(ps -eo rss,command 2>/dev/null | awk -v pat="$name" '$0 ~ pat && !/awk/ {s+=$1} END {printf "%.0f", s/1024}')"
  if [[ "$mem_mb" -gt 1024 ]]; then
    log_warn "$name: ${mem_mb} MB (high)"
  else
    log_info "$name: ${mem_mb} MB"
  fi
done
