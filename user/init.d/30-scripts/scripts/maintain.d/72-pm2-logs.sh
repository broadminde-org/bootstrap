#!/usr/bin/env bash
# Flush PM2 logs (prefers 'pm2 flush'; falls back to truncating log files).
# @tier 1
# @sudo false
# @summary Flush PM2 log files
#
# dev isolates pm2 per project (PM2_HOME=<project>/.dev/pm2), so the
# real logs live in <project>/.dev/pm2/logs — a single shared
# $EE_ROOT/.pm2/logs is never where `dev up` writes.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

found=0
while IFS= read -r project; do
  PM2_LOG_DIR="$project/.dev/pm2/logs"
  [[ -d "$PM2_LOG_DIR" ]] || continue
  found=1

  size_before="$(human_size "$PM2_LOG_DIR")"
  log_info "PM2 logs in $project: $size_before"

  if require_cmd pm2; then
    # Flush THIS project's daemon logs via its isolated PM2_HOME.
    user_run env PM2_HOME="$project/.dev/pm2" pm2 flush
  else
    log_info "pm2 not found; truncating log files manually"
    while IFS= read -r -d '' logfile; do
      run_cmd truncate -s 0 "$logfile"
    done < <(find "$PM2_LOG_DIR" -maxdepth 1 -type f -name '*.log' -print0 2>/dev/null)
  fi

  size_after="$(human_size "$PM2_LOG_DIR")"
  log_ok "PM2 logs in $project: $size_after"
done < <(project_paths)

if [[ $found -eq 0 ]]; then
  log_skip "no per-project PM2 log directories (.dev/pm2/logs) found"
fi
