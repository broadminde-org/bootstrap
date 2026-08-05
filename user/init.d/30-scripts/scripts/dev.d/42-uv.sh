#!/usr/bin/env bash
# 42-uv.sh — Start/stop Python backend via uv + uvicorn (auto-detected)
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Auto-detect: a pyproject.toml declaring uvicorn/fastapi, with the app at
# src/main.py, app/main.py, or main.py (override: DEV_UV_APP=pkg.mod:app).
# Backend dir: root pyproject.toml wins; otherwise backend/pyproject.toml.
# Runs `uv run uvicorn <app> --reload --reload-dir <pkg>` from the backend
# dir. Auto-port: LISTEN_ADDR unset/:0 → uvicorn --port 0; the bound port is
# parsed from the "Uvicorn running on ..." log line into the port file.

# resolve_uv_app <dir> — print "<module:attr> <reload-dir>" for the first
# conventional app layout found; return 1 when none matches.
resolve_uv_app() {
  local dir="$1"
  if [[ -f "${dir}/src/main.py" ]]; then echo "src.main:app src"; return 0; fi
  if [[ -f "${dir}/app/main.py" ]]; then echo "app.main:app app"; return 0; fi
  if [[ -f "${dir}/main.py" ]];    then echo "main:app .";      return 0; fi
  return 1
}

case "${1:-up}" in
  up)
    # Backend-slot precedence: air (Go) and DEV_BACKEND_CMD are explicit
    # config — auto-detect yields to both.
    if has_air || has_custom_backend; then
      log_skip "Explicit backend configured (air/DEV_BACKEND_CMD)"
      exit 0
    fi
    if ! has_uv_project; then
      log_skip "No pyproject.toml found"
      exit 0
    fi
    if ! command -v uv &>/dev/null; then
      fail "uv not found — install it (init.d 20-python) or set DEV_BACKEND_CMD"
      exit 1
    fi

    backend_dir="${PROJECT_DIR}"
    if [[ ! -f "${PROJECT_DIR}/pyproject.toml" ]]; then
      backend_dir="${PROJECT_DIR}/backend"
    fi

    if ! grep -qE '\b(uvicorn|fastapi)\b' "${backend_dir}/pyproject.toml"; then
      log_skip "pyproject.toml declares no uvicorn/fastapi dependency"
      exit 0
    fi

    app="${DEV_UV_APP:-}"
    reload_dir=""
    if [[ -z "$app" ]]; then
      resolved="$(resolve_uv_app "$backend_dir")" || true
      if [[ -z "${resolved:-}" ]]; then
        fail "No ASGI app found (looked for src/main.py, app/main.py, main.py)"
        fail "Set DEV_UV_APP in .env (e.g. DEV_UV_APP=mypkg.server:app)"
        exit 1
      fi
      app="${resolved% *}"
      reload_dir="${resolved##* }"
    else
      # Watch the override's top-level package (src.main:app → src).
      reload_dir="${app%%.*}"
      [[ "$reload_dir" == "$app" ]] && reload_dir="."
    fi

    kill_pid "${DEV_DIR}/backend.pid" "old backend"
    rotate_log "${DEV_DIR}/backend.log"

    # Host/port: pinned from LISTEN_ADDR, or auto (--port 0, parse the log).
    host="0.0.0.0"
    port_arg="0"
    if [[ -n "${LISTEN_ADDR:-}" && "${LISTEN_ADDR}" != *:0 ]]; then
      host="${LISTEN_ADDR%:*}"
      [[ -z "$host" ]] && host="0.0.0.0"
      port_arg="${LISTEN_ADDR##*:}"
      export BACKEND_PORT="$port_arg"
      # Pinned port: write the port file ourselves (status/down read it).
      echo "$BACKEND_PORT" > "$BACKEND_PORT_FILE"
    fi

    log "Starting Python backend (uv run uvicorn ${app})..."
    (
      cd "$backend_dir"
      setsid uv run uvicorn "$app" --host "$host" --port "$port_arg" \
        --reload --reload-dir "$reload_dir" \
        >> "${DEV_DIR}/backend.log" 2>&1 </dev/null &
      echo $! > "${DEV_DIR}/backend.pid"
    )
    uv_pid=$(cat "${DEV_DIR}/backend.pid" 2>/dev/null || echo "")

    if [[ "$port_arg" == "0" ]]; then
      for _ in $(seq 1 60); do
        BACKEND_PORT=$(grep -m1 -oP 'Uvicorn running on http://\S+:\K\d+' \
          "${DEV_DIR}/backend.log" 2>/dev/null || echo "")
        [[ -n "$BACKEND_PORT" ]] && break
        if [[ -n "$uv_pid" ]] && ! kill -0 "$uv_pid" 2>/dev/null; then
          fail "Backend exited before binding a port — see ${DEV_DIR}/backend.log"
          exit 1
        fi
        sleep 0.5
      done
      if [[ -z "$BACKEND_PORT" ]]; then
        fail "Could not parse uvicorn port from ${DEV_DIR}/backend.log"
        exit 1
      fi
      export BACKEND_PORT
      echo "$BACKEND_PORT" > "$BACKEND_PORT_FILE"
      ok "Backend bound to auto-assigned :${BACKEND_PORT}"
    fi

    wait_for_healthz "$BACKEND_PORT" "$uv_pid" 60 "Python backend" "${DEV_HEALTH_PATH:-/healthz}"
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
