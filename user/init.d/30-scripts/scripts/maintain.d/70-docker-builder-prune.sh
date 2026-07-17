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

run_cmd docker builder prune -f --filter "until=24h"
log_ok "Docker builder pruned"
