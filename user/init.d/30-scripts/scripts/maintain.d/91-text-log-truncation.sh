#!/usr/bin/env bash
# Truncate rotated text log files (syslog, kern.log) to reclaim disk space.
# Compressed older logs (.2.gz+) are deleted; .1 rotated copies are truncated.
# The work runs in the root-owned, no-argument prune-text-logs wrapper
# (whitelisted in sudoers by 30-passwordless-sudo) — `rm`/`truncate`
# with path arguments could never be safely whitelisted directly.
# @tier 3
# @sudo true
# @summary Truncate rotated syslog/kern.log/ufw.log
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

LOG_DIR="/var/log"

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  while IFS= read -r -d '' f; do
    log_info "[dry-run] would delete/truncate: $(basename "$f") ($(human_size "$f"))"
  done < <(find "$LOG_DIR" -maxdepth 1 -type f \
    \( -name 'syslog.*.gz' -o -name 'kern.log.*.gz' -o -name 'ufw.log.*.gz' \
       -o -name 'syslog.1' -o -name 'kern.log.1' -o -name 'ufw.log.1' \) -print0 2>/dev/null)
  exit 0
fi

sudo_run /usr/local/sbin/prune-text-logs
log_ok "text log cleanup complete"
