#!/usr/bin/env bash
# Prune Docker build cache (>24h old).
# @tier 2
# @sudo false
# @summary Prune Docker build cache >24h
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

if ! require_cmd docker; then
  log_skip "docker not installed"
  exit 0
fi

# require_cmd only proves the binary exists — the prune needs the DAEMON.
if ! user_run docker info >/dev/null 2>&1; then
  log_skip "docker daemon not reachable — skipping builder prune"
  exit 0
fi

if run_cmd docker builder prune -f --filter "until=24h"; then
  log_ok "Docker builder pruned"
else
  log_err "docker builder prune failed"
  exit 1
fi
