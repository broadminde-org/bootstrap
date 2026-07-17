#!/usr/bin/env bash
# @tier 3
# @sudo false
# @summary Remove ISO build artifacts
#
# DISABLED by default: ISO builds are expensive to reproduce.
# Enable with --all if disk pressure is critical.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

total_freed=0
cleaned=0

while IFS= read -r -d '' iso_dir; do
  [[ "$iso_dir" =~ /apps/[^/]+/iso-output$ ]] || continue

  size="$(human_size "$iso_dir")"
  log_warn "removing ISO output ($size) from ${iso_dir#$EE_ROOT/}"
  log_warn "ISO rebuilds are expensive — only do this when disk pressure is critical"
  run_cmd rm -rf "$iso_dir"

  if [[ ! -d "$iso_dir" ]]; then
    log_ok "removed ${iso_dir#$EE_ROOT/} (freed $size)"
    (( cleaned++ )) || true
  fi
done < <(find "$EE_ROOT/apps" -type d -name 'iso-output' -print0 2>/dev/null)

if [[ $cleaned -eq 0 ]]; then
  log_info "no iso-output directories found"
else
  log_ok "cleaned $cleaned iso-output director(ies)"
fi
