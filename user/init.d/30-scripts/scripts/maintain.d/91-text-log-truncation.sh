#!/usr/bin/env bash
# Truncate rotated text log files (syslog, kern.log) to reclaim disk space.
# Compressed older logs (.2.gz+) are deleted; .1 rotated copies are truncated.
# @tier 3
# @sudo true
# @summary Truncate rotated syslog/kern.log/ufw.log
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

LOG_DIR="/var/log"
cleaned=0

# Delete older compressed rotated logs
for pattern in 'syslog.*.gz' 'kern.log.*.gz' 'ufw.log.*.gz'; do
  while IFS= read -r -d '' f; do
    size="$(human_size "$f")"
    log_info "deleting old compressed log: $(basename "$f") ($size)"
    sudo_run rm -f "$f"
    cleaned=$((cleaned + 1))
  done < <(find "$LOG_DIR" -maxdepth 1 -type f -name "$pattern" -print0 2>/dev/null)
done

# Truncate current rotated copies (keep the file, zero its content)
for logfile in syslog.1 kern.log.1 ufw.log.1; do
  path="$LOG_DIR/$logfile"
  if [[ -f "$path" ]]; then
    size="$(human_size "$path")"
    log_info "truncating rotated log: $logfile ($size)"
    sudo_run truncate -s 0 "$path"
    cleaned=$((cleaned + 1))
  fi
done

if [[ $cleaned -eq 0 ]]; then log_info "no text log files to clean"; else log_ok "cleaned $cleaned text log file(s)"; fi
