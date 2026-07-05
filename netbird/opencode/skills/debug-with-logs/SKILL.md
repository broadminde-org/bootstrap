---
name: debug-with-logs
description: Locate & parse logs across docker-compose services, init.d runs, and netbird-server / dashboard output
---
<rules>
- LOCATE: identify the relevant log source (compose service, init.d step, host process)
- ACCESS: use `docker compose logs`, `init.d/<step>/run.sh` reruns, or `journalctl` for the service
- FILTER: grep for ERROR / WARN / stack-trace markers
- REPORT: present relevant log lines BEFORE asking the user for more detail
</rules>
<locations>
- DOCKER_COMPOSE: docker compose -f docker-compose.yml logs -f [--tail N] [service]
- DOCKER_SERVICE_LOGS: docker compose logs <service> 1>&2 | tee /tmp/<service>.log
- INITD_FAILURE: re-run the failing init.d step with `bash -x` to see expanded commands:
       bash -x init.d/<NN>-<step>/run.sh
- DASHBOARD_CONSOLE: docker compose logs dashboard
- STUN_TRAFFIC: netstat or ss for UDP/3478 (WireGuard) and the gRPC port — confirm traffic is reaching the server
</locations>
<scope>
WHEN: before asking the user about a failure, post-deploy (after 50-stack), post-bootstrap-PAT (after 60-health)
</scope>
<methodology>
1. IDENTIFY_SOURCE: which surface is failing — Caddy, netbird-server, dashboard, an init.d step?
2. RUN_ACCESS: tail or grep via `docker compose logs` or `bash -x init.d/.../run.sh`
3. APPLY_FILTER: grep for the failing marker — ERROR, panic, "failed to", "exit code"
4. SUMMARIZE: surface the key lines with their timestamp and the originating service
</methodology>
<typical_questions>
- "The stack won't come up." -> `docker compose logs caddy` (TLS errors are the most common cause) and `docker compose logs netbird-server` (config errors / port collisions)
- "Bootstrap PAT didn't appear in 60-health." -> re-run `bash -x init.d/60-health/run.sh` and watch for the `/api/setup` response
- "Caddy can't get a cert." -> CLOUDFLARE_API_TOKEN missing or invalid; check `docker compose logs caddy` for DNS-01 errors
- "OIDC login fails." -> `docker compose logs dashboard` + browser DevTools Network tab
</typical_questions>
<anti_patterns>
- NO_LOG_CHECK: do not ask the user about a failure before log analysis
- NO_SUCCESS_REPORT: do not confirm success without log evidence (e.g. `docker compose ps` shows healthy)
</anti_patterns>
