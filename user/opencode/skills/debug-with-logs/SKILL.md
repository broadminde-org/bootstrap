---
name: debug-with-logs
description: Locate and parse logs across services to debug failures. Use when a service won't start, health checks fail, or unknown errors appear.
---

# Debug With Logs

## Rules
- LOCATE: Find the actual log output before guessing. Check compose logs, init.d reruns, journalctl.
- ACCESS: Use docker compose logs, redirect to temp file, read with Read tool. For bare processes, check stdout/stderr capture.
- FILTER: Search for ERROR, WARN, stack-trace, panic, fatal lines first. Then widen to the failure timestamp window.
- REPORT: Present log lines to the user before asking questions or proposing fixes.

## Log Locations
- docker compose logs: `docker compose logs --tail=100 <service>`
- Service logs teed to file: Check `/tmp/` or `/var/log/` for service-specific output
- Init/pipeline failures: Re-run with verbose flag (`bash -x`, `set -x`) to capture step-by-step output
- Frontend console: Browser DevTools Console for client-side errors
- Network: `ss -tlnp`, `netstat` for port binding conflicts

## Methodology
1. IDENTIFY_SOURCE: Which service failed? What's the failure symptom?
2. RUN_ACCESS: Fetch the logs using the correct access method for that service.
3. APPLY_FILTER: Filter to ERROR/WARN/stack-trace around the failure time.
4. SUMMARIZE: Present key log lines, error codes, and timestamps. Include full log tail if relevant.

## Typical Patterns
- Service won't start → check docker compose logs for that service + check port conflicts
- Health check fails → check application logs at startup, verify downstream dependencies are reachable
- TLS/cert failure → check certificate renewal logs, DNS resolution, ACME challenge completion
- Auth failure → check OIDC/OAuth callback URL configuration, client secret validity

## Anti-Patterns
- NO_LOG_CHECK: Proposing fixes or asking the user questions without first reading the logs
- NO_SUCCESS_REPORT: Finding and fixing an error but not confirming the service is now healthy
