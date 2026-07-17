#!/usr/bin/env bash
# @tier 3
# @sudo true
# @summary Drop OS pagecache
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

before_kb="$(awk '/MemAvailable/ {print $2}' /proc/meminfo)"
log_info "MemAvailable before: $((before_kb / 1024)) MB"
sync
sudo_run sh -c 'echo 1 > /proc/sys/vm/drop_caches'
after_kb="$(awk '/MemAvailable/ {print $2}' /proc/meminfo)"
log_ok "MemAvailable after: $((after_kb / 1024)) MB"
