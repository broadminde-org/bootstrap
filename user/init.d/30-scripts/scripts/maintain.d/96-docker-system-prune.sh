#!/usr/bin/env bash
# Prune all unused Docker data: containers, images, networks, build cache.
# CAUTION: --volumes also deletes anonymous volumes (attached to removed
# containers) — persistent named volumes survive, anonymous data does not.
# @tier 3
# @sudo false
# @summary Prune all unused Docker data (incl. anonymous volumes — CAUTION)
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"
if ! require_cmd docker; then log_skip "docker not installed"; exit 0; fi
# require_cmd only proves the binary exists — the prune needs the DAEMON.
if ! user_run docker info >/dev/null 2>&1; then
  log_skip "docker daemon not reachable — skipping system prune"
  exit 0
fi
if run_cmd docker system prune -a -f --volumes; then
  log_ok "Docker system pruned (aggressive, including anonymous volumes)"
else
  log_err "docker system prune failed"
  exit 1
fi
