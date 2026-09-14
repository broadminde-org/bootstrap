#!/usr/bin/env bash
# Report Docker container and disk usage.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

if ! require_cmd docker; then
  log_skip "docker not installed"
  exit 0
fi

log_info "Running containers: $(docker ps -q 2>/dev/null | wc -l)"
if docker_df="$(docker system df 2>/dev/null)"; then
  while IFS= read -r line; do
    log_info "  $line"
  done <<< "$docker_df"
else
  log_warn "Docker daemon is unavailable"
fi
