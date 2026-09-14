#!/usr/bin/env bash
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/maintain-common.sh"

load_avg="$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' | sed 's/^ *//' || true)"
memory="$(free -m 2>/dev/null | awk '/^Mem:/ {printf "%dMB / %dMB (%.0f%%)", $3, $2, $3*100/$2}' || true)"
inotify="$(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || true)"
editor_procs="$(pgrep -fc 'windsurf|codium-server|server-main\.js' 2>/dev/null || true)"

log_info "Load avg:        ${load_avg:-unavailable}"
log_info "Memory:          ${memory:-unavailable}"
log_info "Inotify watches: ${inotify:-unavailable}"
log_info "Editor procs:    ${editor_procs:-0}"
