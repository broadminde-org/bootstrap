#!/usr/bin/env bash
# 50-vite.sh — Start/stop Vite dev server via PM2
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# pm2 is only needed when there IS a frontend — Go-only projects must
# not be aborted by a missing pm2 (check after the has_frontend skip).
PM2_NAME="${DETECTED_APP}-vite"

case "${1:-up}" in
  up)
    if ! has_frontend; then
      log_skip "No frontend found (${FRONTEND_DIR}/package.json)"
      exit 0
    fi

    if ! command -v pm2 &>/dev/null; then
      log_skip "pm2 not found — skipping Vite dev server (install: npm install -g pm2)"
      exit 0
    fi

    pm2 delete --silent "$PM2_NAME" 2>/dev/null || true

    if [[ ! -d "${FRONTEND_DIR}/node_modules" ]]; then
      log "Installing frontend dependencies..."
      npm --prefix "${FRONTEND_DIR}" install
    fi

    rotate_log "${DEV_DIR}/vite.log"

    vite_args="--prefix ${FRONTEND_DIR} run dev -- --host ${FRONTEND_DEV_HOST:-::}"
    if [[ -n "${FRONTEND_PORT:-}" ]]; then
      vite_args+=" --port ${FRONTEND_PORT} --strictPort"
    fi

    cat > "${DEV_DIR}/ecosystem.config.js" <<EOF
module.exports = {
  apps: [{
    name:        '${PM2_NAME}',
    script:      'npm',
        args:        '${vite_args}',
    cwd:         '${PROJECT_DIR}',
    env:         {
      VITE_BACKEND_PORT: '${BACKEND_PORT}',
      FRONTEND_HMR_HOST: '${FRONTEND_HMR_HOST:-}',
      FRONTEND_HMR_PROTOCOL: '${FRONTEND_HMR_PROTOCOL:-}',
      FRONTEND_HMR_CLIENT_PORT: '${FRONTEND_HMR_CLIENT_PORT:-}',
    },
    out_file:    '${DEV_DIR}/vite.log',
    error_file:  '${DEV_DIR}/vite.log',
    merge_logs:  true,
    autorestart: false,
    watch:       false,
  }]
};
EOF

    pm2 start "${DEV_DIR}/ecosystem.config.js"

    # Require Vite's own announcement so an unrelated listener cannot satisfy
    # readiness when a strict configured port is already occupied.
    vite_port=$(timeout 30 tail -F "${DEV_DIR}/vite.log" \
      | grep -m1 -oP '(?<=localhost:)\d+') || true
    if [[ -z "${vite_port:-}" || ! "$vite_port" =~ ^[0-9]+$ ]]; then
      fail "Vite did not announce a port within 30s — see ${DEV_DIR}/vite.log"
      exit 1
    fi
    if [[ -n "${FRONTEND_PORT:-}" && "$vite_port" != "$FRONTEND_PORT" ]]; then
      fail "Vite did not bind configured port ${FRONTEND_PORT} — see ${DEV_DIR}/vite.log"
      exit 1
    fi
    echo "$vite_port" > "${FRONTEND_PORT_FILE}"
    FRONTEND_PORT="$vite_port"
    export FRONTEND_PORT

    # TCP readiness only — /healthz is an ee-specific shared-package route.
    wait_for_port "$FRONTEND_PORT" localhost 30 "Vite dev server"
    ;;

  down)
    log "Stopping Vite dev server..."
    pm2 delete --silent "$PM2_NAME" 2>/dev/null || true
    rm -f "${FRONTEND_PORT_FILE:-}"
    ok "Vite stopped"
    ;;
esac
