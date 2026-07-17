---
description: Bring up, tear down, or inspect the netbird stack — unified frontend for the init.d/ + docker compose lifecycle
agent: code
---
<purpose>Spin up, tear down, and inspect the netbird stack. The stack runs as three Docker containers (caddy, dashboard, netbird-server) under the init.d/ orchestrator. This command is the unified shortcut for the most common operational actions; for non-trivial changes (new init.d step, new template, image swap) edit the underlying scripts directly and run them.</purpose>

<usage>
- /netbird-stack up          -> run the app tier of init.sh (10-cloudflare → 80-verify)
- /netbird-stack down        -> docker compose down (volumes preserved)
- /netbird-stack teardown    -> docker compose down -v (DESTRUCTIVE; deletes caddy_data, caddy_config, netbird_data)
- /netbird-stack status      -> docker compose ps + per-service log tail for non-healthy
- /netbird-stack health      -> curl /api/health on the management API; tail logs on failure
- /netbird-stack logs <svc>  -> docker compose logs -f --tail 100 [svc]
- /netbird-stack bootstrap   -> print NETBIRD_BOOTSTRAP_PAT from .env (PAT is captured by 60-health)
- /netbird-stack render-only -> run 20-render (renders config.yaml, dashboard.env, Caddyfile from *.tmpl)
- /netbird-stack help        -> print this usage block
</usage>

<scope>
ALLOWED: docker compose (config, ps, logs, down, up -d), curl on the management API port, ./init.sh app-tier, read .env
DENIED: host-tier steps (require sudo, MUST be run with `sudo ./init.sh`); destructive teardown without explicit confirmation; editing *.tmpl or .env directly (delegate to ee-shell)
</scope>

<command_mapping>
| Action | Equivalent (run from the stack root) |
|---|---|
| `up` | `./init.sh --from 10` (assumes the host tier has already completed) |
| `down` | `docker compose down` |
| `teardown` | `docker compose down -v` (DANGEROUS — see clarification_triggers) |
| `status` | `docker compose ps -a` |
| `health` | `curl -fsS http://<NETBIRD_DOMAIN>/api/health` |
| `logs <svc>` | `docker compose logs -f --tail 100 <svc>` |
| `bootstrap` | `grep '^NETBIRD_BOOTSTRAP_PAT=' .env \| cut -d= -f2-` |
| `render-only` | `./init.sh 20-render` |
</command_mapping>

<methodology>
1. PARSE: extract the action (up / down / teardown / status / health / logs / bootstrap / render-only / help) and any service name argument.
2. CWD CHECK: confirm `$PWD` is the netbird stack root (must contain `docker-compose.yml` AND `init.sh`). If not, abort with the CWD error.
3. LOAD ENV: `set -a; source .env; set +a` so `${NETBIRD_DOMAIN}` is available for the health probe. Never assume .env is rendered; if missing, suggest `./init.sh 20-render` first.
4. DISPATCH by action:
   - **up**: prefer `./init.sh --from 10` (idempotent — 10/12 re-validate, 50-stack no-ops if running). On a first-time host, detect missing `docker` group membership (`id -nG | grep -qw docker`) and warn that the host tier needs `sudo ./init.sh 30-docker` first.
   - **down**: `docker compose down`. NEVER pass `-v` automatically.
   - **teardown**: require the user to type `teardown confirm` (or pass `--yes`). Then `docker compose down -v`. Print the data dir paths removed: `caddy_data` (TLS certs), `caddy_config`, `netbird_data` (sqlite + store encryption).
   - **status**: `docker compose ps -a`. For any service with `Exit` or unhealthy state, append `docker compose logs --tail 5 <svc>` and surface.
   - **health**: `curl -fsS --max-time 10 https://${NETBIRD_DOMAIN}/api/health || docker compose logs netbird-server --tail 50`. Treat non-2xx as failure and surface the body.
   - **logs <svc>**: `docker compose logs -f --tail 100 <svc>`. If no service given, default to `netbird-server`.
   - **bootstrap**: read `.env` for `NETBIRD_BOOTSTRAP_PAT`. If empty, the user hasn't completed `60-health` — point them at `/netbird-stack up`.
   - **render-only**: `./init.sh 20-render`. Useful for diffing tmpl changes without restarting the stack.
   - **help**: print the `<usage>` block.
5. REPORT: action result, durations where available, the relevant URL/credential.

</methodology>

<routing>
- `20-render` fails (envsubst error, missing var) → delegate to ee-shell
- `50-stack` fails (compose fail, port conflict) → delegate to ee-docker
- `60-health` fails (no bootstrap PAT after 60s) → use the debug-with-logs skill
- health probe hangs (TLS not yet provisioned) → tail `docker compose logs caddy` and watch for DNS-01 errors
- destructive flag detected without explicit confirmation → HALT and clarify
</routing>

<examples>
<example>
<input>/netbird-stack up</input>
<output>Running `./init.sh --from 10` from /home/luke/ee/apps/netbird. 10-cloudflare OK (CLOUDFLARE_API_TOKEN valid). 12-secrets OK (no empties). 20-render OK (config.yaml, dashboard.env, Caddyfile written). 45-build-caddy OK (caddy-custom:latest built). 50-stack OK (3 services up, healthy). 60-health OK (PAT captured). 80-verify summary printed. Stack is up. Try `/netbird-stack health` to confirm.</output>
</example>

<example>
<input>/netbird-stack down</input>
<output>Ran `docker compose down`. caddy, dashboard, netbird-server stopped. Volumes (caddy_data, caddy_config, netbird_data) PRESERVED. To remove volumes as well, run `/netbird-stack teardown`.</output>
</example>

<example>
<input>/netbird-stack teardown confirm</input>
<output>Teardown confirmed. Ran `docker compose down -v`. Removed: caddy_data (TLS certs), caddy_config, netbird_data (sqlite + store). Fresh `up` will trigger a full Caddy DNS-01 issuance and a fresh NETBIRD_BOOTSTRAP_PAT.</output>
</example>

<example>
<input>/netbird-stack health</input>
<output>curl --max-time 10 https://netbird.example.com/api/health → 200 OK {"status":"healthy"}. All services healthy. Dashboard at https://netbird.example.com.</output>
</example>

<example>
<input>/netbird-stack logs caddy</input>
<output>Tailing caddy logs (-f --tail 100). Press Ctrl-C to stop. To follow netbird-server instead: /netbird-stack logs netbird-server.</output>
</example>

<example>
<input>/netbird-stack bootstrap</input>
<output>NETBIRD_BOOTSTRAP_PAT=pxXxyQbSnGsjTH7DF6EFGQ== (from .env). Use this to enroll your first peer via `netbird login --management-url https://netbird.example.com --pat <PAT>`.</output>
</example>
</examples>

<clarification_triggers>
- `up` invoked on a host without a working `docker` group → "Run `sudo ./init.sh 30-docker` (and `05-passwordless-sudo` if you haven't) before `/netbird-stack up`. The host tier installs Docker and grants your user the group membership; without it `docker compose` will fail with permission errors."
- `down -v` or `teardown` without `confirm` → require the explicit confirmation string before running
- `bootstrap` with no PAT in `.env` → "Run `/netbird-stack up` first; 60-health generates NETBIRD_BOOTSTRAP_PAT."
- Unknown action → list the valid actions and exit
- `up` on a host where 60-health previously ran but the API is now returning 5xx → suggest `/netbird-stack status` then `/netbird-stack logs netbird-server`
- Service name for `logs` that doesn't exist in `docker-compose.yml` → list the actual service names and exit
</clarification_triggers>

