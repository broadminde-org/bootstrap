#!/usr/bin/env bash
# 10-infra.sh — Start infra services (Docker Compose)
set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

case "${1:-up}" in
  up)
    if ! has_compose; then
      log_skip "No docker-compose.yml found"
      exit 0
    fi

    # Infra is opt-in: only services named in DEV_INFRA_SERVICES (from .env)
    # are started. Unset/empty means dev touches no containers — compose
    # files written for deployment (no profiles) are left alone.
    infra_svcs=()
    read -ra infra_svcs <<< "${DEV_INFRA_SERVICES:-}"
    if [[ ${#infra_svcs[@]} -eq 0 ]]; then
      log_skip "DEV_INFRA_SERVICES not set — no infra services to start"
      exit 0
    fi

    log "Starting infra services: ${infra_svcs[*]}..."
    # No --remove-orphans: with an explicit service list it would reap
    # containers outside the list (e.g. app containers started by stack).
    compose_cmd up -d "${infra_svcs[@]}"

    # Wait for healthchecks. ps JSON always has a "Health" key — only a
    # non-empty value ("Health":"<state>") means a healthcheck exists.
    for i in $(seq 1 30); do
      all_healthy=true
      for svc in "${infra_svcs[@]}"; do
        svc_json=$(compose_cmd ps "$svc" --format json 2>/dev/null || true)
        if echo "$svc_json" | grep -q '"Health":"[a-z]' \
            && ! echo "$svc_json" | grep -q '"Health":"healthy"'; then
          all_healthy=false
        fi
      done
      if $all_healthy; then
        ok "Infra services are healthy"
        break
      fi
      if [[ $i -eq 30 ]]; then
        warn "Some infra services not healthy after 60s, continuing anyway..."
      fi
      sleep 2
    done
    ;;

  down)
    # dev does not tear down infra — `dev down` prints a note if compose
    # services are still running.
    ;;
esac
