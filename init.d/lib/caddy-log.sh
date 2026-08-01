#!/usr/bin/env bash
# lib/caddy-log.sh — resolve the Caddy JSON access-log path, shared by
# 53-fail2ban and 54-crowdsec so the two IPS layers can never resolve to
# different logs.
#
#   resolve_caddy_log <output-var-name>
#
# Resolution order:
#   1. $CADDY_LOG_PATH (environment override — honored verbatim)
#   2. central (~/infra/caddy/logs/access.log under the deploy user's home)
#      or legacy (netbird-docker) — whichever exists; when BOTH exist
#      (migration window or rollback), prefer the one with the fresher
#      mtime: the live edge is the file being written. Existence alone
#      cannot distinguish "central ran once" from "central is the edge".
#   3. central path as the default for new hosts (neither exists yet)
#   4. legacy path when there is no deploy-user context at all
#
# LEGACY_CADDY_LOG may be overridden in the environment (used by tests).

LEGACY_CADDY_LOG="${LEGACY_CADDY_LOG:-/home/stack/netbird-docker/logs/caddy/access.log}"

resolve_caddy_log() {
  local __out="$1"
  local central=""
  if [[ -n "${SUDO_USER:-}" ]]; then
    central="$(getent passwd "$SUDO_USER" | cut -d: -f6)/infra/caddy/logs/access.log"
  fi

  local resolved
  if [[ -n "${CADDY_LOG_PATH:-}" ]]; then
    resolved="$CADDY_LOG_PATH"
  elif [[ -n "$central" && -f "$central" && -f "$LEGACY_CADDY_LOG" ]]; then
    # Both exist — follow whichever is actively written.
    if [[ "$central" -nt "$LEGACY_CADDY_LOG" ]]; then
      resolved="$central"
    else
      resolved="$LEGACY_CADDY_LOG"
    fi
  elif [[ -n "$central" && -f "$central" ]]; then
    resolved="$central"
  elif [[ -f "$LEGACY_CADDY_LOG" ]]; then
    resolved="$LEGACY_CADDY_LOG"
  elif [[ -n "$central" ]]; then
    resolved="$central"
  else
    resolved="$LEGACY_CADDY_LOG"
  fi

  printf -v "$__out" '%s' "$resolved"
}
