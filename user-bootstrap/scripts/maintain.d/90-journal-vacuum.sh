#!/usr/bin/env bash
# Vacuum systemd journal logs (>14 days).
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

if ! require_cmd journalctl; then
  log_skip "journalctl not installed"
  exit 0
fi

sudo_run journalctl --vacuum-time=14d
log_ok "Journal vacuumed"
