#!/usr/bin/env bash
# 40-backend.sh — Start/stop Go backend with air
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

case "${1:-up}" in
  up)
    if ! has_backend; then
      log_skip "No backend found (no .air.toml, no DEV_BACKEND_CMD)"
      exit 0
    fi

    kill_pid "${DEV_DIR}/backend.pid" "old backend"
    rotate_log "${DEV_DIR}/backend.log"

    if [[ -n "${DEV_BACKEND_CMD:-}" ]]; then
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
      exit 0
    fi

    # Root .air.toml wins; otherwise use backend/ (backend/.air.toml).
    backend_dir="${PROJECT_DIR}"
    if [[ ! -f "${PROJECT_DIR}/.air.toml" ]]; then
      backend_dir="${PROJECT_DIR}/backend"
    fi

    log "Starting Go backend (air)..."
    (
      cd "$backend_dir"
      setsid air >> "${DEV_DIR}/backend.log" 2>&1 </dev/null &
      echo $! > "${DEV_DIR}/backend.pid"
    )
    go_pid=$(cat "${DEV_DIR}/backend.pid" 2>/dev/null || echo "")

    # Auto-port (LISTEN_ADDR unset or *:0): wait for the Go binary to write
    # the port file. Pinned port: derive it from LISTEN_ADDR.
    if [[ -z "${LISTEN_ADDR:-}" || "${LISTEN_ADDR}" == *:0 ]]; then
      for _ in $(seq 1 30); do
        if [[ -f "${BACKEND_PORT_FILE}" ]]; then
          BACKEND_PORT="$(cat "${BACKEND_PORT_FILE}")"
          export BACKEND_PORT
          break
        fi
        if [[ -n "$go_pid" ]] && ! kill -0 "$go_pid" 2>/dev/null; then
          fail "Backend exited before writing port file — see ${DEV_DIR}/backend.log"
          exit 1
        fi
        sleep 0.5
      done
      if [[ ! -f "${BACKEND_PORT_FILE}" || -z "${BACKEND_PORT:-}" ]]; then
        fail "Backend did not write port file at ${BACKEND_PORT_FILE}"
        exit 1
      fi
      ok "Backend bound to auto-assigned :${BACKEND_PORT}"
    else
      export BACKEND_PORT="${LISTEN_ADDR##*:}"
    fi

    wait_for_healthz "$BACKEND_PORT" "$go_pid" 60 "Go backend" "${DEV_HEALTH_PATH:-/healthz}"
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
