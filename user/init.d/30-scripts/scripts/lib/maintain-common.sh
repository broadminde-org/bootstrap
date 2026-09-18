#!/usr/bin/env bash
# Common helpers for maintain.d and diagnose.d steps.
# Sourced — do not exec. No `set -e` here (callers control that).

# Derive SCRIPT_ROOT and EE_ROOT from sibling env.sh
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

# Colors (no-op if not a tty)
# shellcheck disable=SC2034  # BOLD/NC are consumed by maintain.d/run.sh --list
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

# Wraps a sudo-requiring command; skips gracefully if no privilege.
# The probe is per-command (`sudo -n -l <cmd...>`): a blanket
# `sudo -n true` probe only succeeds when `true` itself is whitelisted,
# which the narrow deploy-user whitelist deliberately does not do.
sudo_run() {
  if [[ $EUID -eq 0 ]]; then
    run_cmd "$@"
    return $?
  fi
  if sudo -n -l "$@" >/dev/null 2>&1; then
    run_cmd sudo -n "$@"
    return $?
  fi
  # Print the absolute runner path: `sudo maintain` cannot work because
  # ~/.local/bin is not in sudo's secure_path.
  log_skip "needs sudo (non-interactive); run: sudo $HOME/.local/bin/maintain"
  return 0
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# EE_ROOT detection: env override, else the $HOME fallback from
# lib/env.sh. (No git probe: the deployed ~/scripts/lib is never inside
# a git worktree, so a probe from BASH_SOURCE can never succeed.)
detect_ee_root() {
  if [[ -n "${EE_ROOT:-}" && -d "$EE_ROOT" ]]; then
    printf '%s\n' "$EE_ROOT"
    return
  fi
  printf '%s\n' "$HOME"
}

# ee_layout_root — print EE_ROOT only when it is a real ee-layout
# project root; return 1 otherwise. The env.sh EE_ROOT=$HOME fallback
# means "no project root": ee-layout steps must never run against $HOME
# (a tier-1 `maintain` on a non-ee host would otherwise delete from
# ~/archive or sweep the whole home directory). A root is accepted when
# it carries a positive marker (.git or apps/) or the operator opted in
# explicitly via EE_LAYOUT_FORCE=1.
ee_layout_root() {
  local root
  root="$(detect_ee_root)"
  if [[ "${EE_LAYOUT_FORCE:-0}" == "1" ]]; then
    printf '%s\n' "$root"
    return 0
  fi
  if [[ -d "$root/.git" || -d "$root/apps" ]]; then
    printf '%s\n' "$root"
    return 0
  fi
  return 1
}

# require_ee_layout — gate for ee-layout steps; skips the step when no
# real project root is detected.
require_ee_layout() {
  if ! EE_ROOT="$(ee_layout_root)"; then
    log_skip "no ee-layout project root (EE_ROOT has no .git/ or apps/) — set EE_LAYOUT_FORCE=1 to override"
    exit 0
  fi
  export EE_ROOT
}

# kilo_running — 0 when a Kilo agent process is alive for the real
# user. `pgrep -x kilo` matches the binary's comm (robust against
# cmdline changes); the -f fallback catches wrappers that re-exec.
# Verified against a live host: the agent runs as `kilo serve --port 0`.
kilo_running() {
  local user="${SUDO_USER:-$USER}"
  if pgrep -x kilo -u "$user" >/dev/null 2>&1; then return 0; fi
  if pgrep -f 'kilo serve' -u "$user" >/dev/null 2>&1; then return 0; fi
  return 1
}

# Emits one path per line: EE_ROOT plus each apps/* subdir.
project_paths() {
  local root
  root="$(detect_ee_root)"
  printf '%s\n' "$root"
  if [[ -d "$root/apps" ]]; then
    find "$root/apps" -mindepth 1 -maxdepth 1 -type d | sort
  fi
}

human_size() {
  if [[ -e "$1" ]]; then
    du -sh "$1" 2>/dev/null | awk '{print $1}'
  else
    printf '0\n'
  fi
}

# When run via sudo, resolve the real user's home directory.
if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
  REAL_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
else
  REAL_HOME="$HOME"
fi
export REAL_HOME

# Run a command as the real user (drops sudo if we're root via sudo).
user_run() {
  if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
    run_cmd sudo -u "$SUDO_USER" "$@"
  else
    run_cmd "$@"
  fi
}
export -f user_run
