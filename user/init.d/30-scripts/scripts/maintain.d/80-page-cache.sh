#!/usr/bin/env bash
# @tier 3
# @sudo true
# @summary Drop OS pagecache
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

before_kb="$(awk '/MemAvailable/ {print $2}' /proc/meminfo)"
log_info "MemAvailable before: $((before_kb / 1024)) MB"
# drop-caches is the root-owned, no-argument wrapper whitelisted in
# sudoers by 30-passwordless-sudo (it also runs sync first).
sudo_run /usr/local/sbin/drop-caches
after_kb="$(awk '/MemAvailable/ {print $2}' /proc/meminfo)"
log_ok "MemAvailable after: $((after_kb / 1024)) MB"
