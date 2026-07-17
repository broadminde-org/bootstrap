#!/usr/bin/env bash
# Flush PM2 logs (prefers 'pm2 flush'; falls back to truncating log files).
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

PM2_LOG_DIR="$EE_ROOT/.pm2/logs"

if [[ ! -d "$PM2_LOG_DIR" ]]; then
  log_skip "PM2 log directory not found at $PM2_LOG_DIR"
  exit 0
fi

size_before="$(human_size "$PM2_LOG_DIR")"
log_info "PM2 logs before: $size_before"

if require_cmd pm2; then
  run_cmd pm2 flush
else
  log_info "pm2 not found; truncating log files manually"
  while IFS= read -r -d '' logfile; do
    run_cmd truncate -s 0 "$logfile"
  done < <(find "$PM2_LOG_DIR" -maxdepth 1 -type f -name '*.log' -print0 2>/dev/null)
fi

size_after="$(human_size "$PM2_LOG_DIR")"
log_ok "PM2 logs after: $size_after"
