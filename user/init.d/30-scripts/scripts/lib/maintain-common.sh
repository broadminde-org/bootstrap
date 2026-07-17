#!/usr/bin/env bash
# Common helpers for maintain.d steps.
# Sourced — do not exec. No `set -e` here (callers control that).

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

# Colors (no-op if not a tty)
if [[ -t 1 ]]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
  BLUE=$'\033[0;34m'; BOLD=$'\033[1m'; NC=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; BOLD=""; NC=""
fi

log_step() { printf '%s==> %s%s\n' "$BLUE" "$1" "$NC"; }
log_info() { printf '   %s\n' "$1"; }
log_ok()   { printf '   %s✓%s %s\n' "$GREEN" "$NC" "$1"; }
log_warn() { printf '   %s⚠%s %s\n' "$YELLOW" "$NC" "$1"; }
log_skip() { printf '   %s⏭%s %s\n' "$YELLOW" "$NC" "skip: $1"; }
log_err()  { printf '   %s✗%s %s\n' "$RED" "$NC" "$1" >&2; }

# DRY_RUN: when "1", commands print instead of executing.
run_cmd() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '   [dry-run] %s\n' "$*"
    return 0
  fi
  "$@"
}

# Returns 0 if running as root or passwordless sudo is available.
have_root_or_sudo() {
  if [[ $EUID -eq 0 ]]; then return 0; fi
  if sudo -n true 2>/dev/null; then return 0; fi
  return 1
}

# Wraps a sudo-requiring command; skips gracefully if no privilege.
sudo_run() {
  if [[ $EUID -eq 0 ]]; then
    run_cmd "$@"
    return $?
  fi
  if sudo -n true 2>/dev/null; then
    run_cmd sudo "$@"
    return $?
  fi
  log_skip "needs sudo (non-interactive); run with sudo if needed"
  return 0
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1
}

human_size() {
  if [[ -e "$1" ]]; then
    du -sh "$1" 2>/dev/null | awk '{print $1}'
  else
    printf '0\n'
  fi
}
