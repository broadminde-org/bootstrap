#!/usr/bin/env bash
# 45-backend.sh — Start/stop custom backend via DEV_BACKEND_CMD
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

case "${1:-up}" in
  up)
    if ! has_custom_backend; then
      log_skip "DEV_BACKEND_CMD not set"
      exit 0
    fi

    kill_pid "${DEV_DIR}/backend.pid" "old backend"
    rotate_log "${DEV_DIR}/backend.log"

    # Custom backend command from .env (e.g. Python/uv). No auto-port:
    # the port lives inside the command, so LISTEN_ADDR must be pinned
    # for the health check to know where to probe.
    if [[ -z "${LISTEN_ADDR:-}" || "${LISTEN_ADDR}" == *:0 ]]; then
      fail "DEV_BACKEND_CMD requires a pinned LISTEN_ADDR (e.g. :9000) in .env"
      exit 1
    fi
    export BACKEND_PORT="${LISTEN_ADDR##*:}"
    # Pinned port: write the port file ourselves — a custom backend doesn't
    # know the auto-port contract, and status/down read it from the file.
    echo "$BACKEND_PORT" > "$BACKEND_PORT_FILE"

    log "Starting backend (DEV_BACKEND_CMD)..."
    (
      cd "$PROJECT_DIR"
      setsid bash -c "$DEV_BACKEND_CMD" >> "${DEV_DIR}/backend.log" 2>&1 </dev/null &
      echo $! > "${DEV_DIR}/backend.pid"
    )
    backend_pid=$(cat "${DEV_DIR}/backend.pid" 2>/dev/null || echo "")

    wait_for_healthz "$BACKEND_PORT" "$backend_pid" 60 "Backend" "${DEV_HEALTH_PATH:-/healthz}"
    ;;

  down)
    log "Stopping backend..."
    kill_pid "${DEV_DIR}/backend.pid" "backend"
    # Prefer the port file (auto-port) over $BACKEND_PORT (may be stale).
    down_port="${BACKEND_PORT:-}"
    if [[ -f "${BACKEND_PORT_FILE:-}" ]]; then
      down_port="$(cat "${BACKEND_PORT_FILE}")"
    fi
    if [[ -n "$down_port" && "$down_port" =~ ^[0-9]+$ ]]; then
      pids=$(own_port_pids "$down_port")
      if [[ -n "$pids" ]]; then
        echo "$pids" | xargs kill 2>/dev/null || true
      fi
    fi
    rm -f "${BACKEND_PORT_FILE:-}"
    ok "Backend stopped"
    ;;
esac
