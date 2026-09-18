#!/usr/bin/env bash
# Report host-wide Kilo process and state directory sizes.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

KILO_STATE_DIR="$REAL_HOME/.local/share/kilo"

kilo_rss="$(ps -eo rss,command -u "$(id -u)" 2>/dev/null | awk '/kilo serve/ && !/awk/ {s+=$1} END {printf "%.0f", s/1024}')"
if [[ -n "$kilo_rss" && "$kilo_rss" -gt 0 ]]; then
  if [[ "$kilo_rss" -gt 1024 ]]; then
    log_warn "Kilo process: ${kilo_rss} MB RSS"
  else
    log_info "Kilo process: ${kilo_rss} MB RSS"
  fi
else
  log_info "Kilo process: not running"
fi

if [[ -d "$KILO_STATE_DIR" ]]; then
  log_info "Kilo state dir: $(human_size "$KILO_STATE_DIR")"
  for sub in log storage snapshot tool-output; do
    sub_path="$KILO_STATE_DIR/$sub"
    if [[ -d "$sub_path" ]]; then
      log_info "  $sub: $(human_size "$sub_path") ($(find "$sub_path" -maxdepth 1 -type f 2>/dev/null | wc -l) files)"
    fi
  done

  kilo_db="$KILO_STATE_DIR/kilo.db"
  if [[ -f "$kilo_db" ]]; then
    log_info "  kilo.db: $(human_size "$kilo_db")"
  fi
else
  log_info "Kilo state dir: not found"
fi
