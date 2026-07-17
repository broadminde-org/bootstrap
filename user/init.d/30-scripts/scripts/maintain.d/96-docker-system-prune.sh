#!/usr/bin/env bash
# Prune all unused Docker data: containers, images, networks, build cache, and volumes.
# @tier 3
# @sudo false
# @summary Prune all unused Docker data
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"
if ! require_cmd docker; then log_skip "docker not installed"; exit 0; fi
run_cmd docker system prune -a -f --volumes
log_ok "Docker system pruned (aggressive, including volumes)"
