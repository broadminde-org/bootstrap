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

    log "Starting infra services..."
    infra_svcs=$(compose_cmd config --services 2>/dev/null || true)
    if [[ -n "$infra_svcs" ]]; then
      compose_cmd up -d --remove-orphans
    else
      log_skip "No services defined in compose file"
    fi

    # Wait for healthchecks. ps JSON always has a "Health" key — only a
    # non-empty value ("Health":"<state>") means a healthcheck exists.
    if [[ -n "$infra_svcs" ]]; then
      for i in $(seq 1 30); do
        all_healthy=true
        while IFS= read -r svc; do
          [[ -z "$svc" ]] && continue
          svc_json=$(compose_cmd ps "$svc" --format json 2>/dev/null || true)
          if echo "$svc_json" | grep -q '"Health":"[a-z]' \
              && ! echo "$svc_json" | grep -q '"Health":"healthy"'; then
            all_healthy=false
          fi
        done <<< "$infra_svcs"
        if $all_healthy; then
          ok "Infra services are healthy"
          break
        fi
        if [[ $i -eq 30 ]]; then
          warn "Some infra services not healthy after 60s, continuing anyway..."
        fi
        sleep 2
      done
    fi
    ;;

  down)
    # dev does not tear down infra — `dev down` prints a note if compose
    # services are still running.
    ;;
esac
