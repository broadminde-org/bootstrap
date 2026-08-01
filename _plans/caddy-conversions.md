# Caddy instance conversions — existing stacks → dual-mode snippets

Status: **ready for Phase 2 execution** (after `_plans/central-caddy.md` Phase 1
lands and is verified on a host). Surveyed 2026-08-01 from the live repo files.

This document converts the three existing Caddy instances into **dual-mode
snippets**: one file per app that works unchanged

- **standalone** — `import`ed from the app stack's own Caddyfile (today's
  deployment form), and
- **central** — `caddy-route register <app> <file>` into the host's central
  Caddy (`bootstrap/user/init.d/60-caddy`).

Conversion inventory (from `_plans/central-caddy.md` §1):

| Instance | Repo | Today | Migration |
|---|---|---|---|
| ci webhook | `~/ci` | clean snippet, imported into a main Caddyfile | **first** — proves the primitive |
| artifacts | `~/ee/infra` | stock `caddy:2-alpine`, 8-line Caddyfile, `:5001` | optional — after netbird |
| netbird edge | `~/netbird-docker` | monolithic rendered Caddyfile, DNS-01 + CrowdSec | **the big one** — needs CrowdSec gating live centrally |

---

## 1. Dual-mode compatibility rules

These are the five mechanisms that make one snippet file valid in both modes.
Every conversion below follows them.

### 1.1 Upstreams: container names + the `edge` network

Snippets address app containers **by container name**
(`reverse_proxy netbird-server:80`). For that name to resolve:

- *Standalone*: the stack's own Caddy container shares the app's docker
  network (already true in every stack today).
- *Central*: the app's proxied services join the external `edge` network:
  ```yaml
  networks:
    edge:
      external: true
      name: edge
  ```

No upstream addresses change between modes.

### 1.2 Host-published upstreams: `host.docker.internal`

When the app is not a container Caddy can reach directly, the snippet targets
`host.docker.internal:<port>`.

- *Central*: works out of the box — central compose sets
  `extra_hosts: host.docker.internal:host-gateway`.
- *Standalone (containerized caddy)*: add the same `extra_hosts` line to the
  stack's caddy service.
- *Standalone (systemd caddy on the host)*: add a line to `/etc/hosts`:
  `127.0.0.1 host.docker.internal`.

**Hard requirement**: the app must publish the port on `0.0.0.0`, not
`127.0.0.1`. Docker's loopback publishes are unreachable from the host-gateway
address that containers use. Restrict exposure with `DOCKER-USER` rules
(host firewall is the only chain that sees DNAT'd container traffic) — never
by binding mesh/bridge IPs (§2.6 of the central-caddy plan).

### 1.3 Static roots: one absolute path, mounted per mode

`file_server` snippets use a single absolute container path. Each mode mounts
the host content at that same path:

| Snippet path | Central mount | Standalone mount |
|---|---|---|
| `/srv/edge/<app>` | `~/infra/edge/<app>` (via `../edge:/srv/edge:ro`) or a shadow mount in `compose.override.yaml` | app's compose mounts its asset dir at `/srv/edge/<app>:ro` |

Symlinks inside a bind-mounted dir do **not** work (they resolve in the
container's mount namespace) — use a real directory or a shadow mount.

### 1.4 CrowdSec: site directive travels, global app stays home

The site-level `crowdsec` directive is kept **in the snippet** — it is valid
in both modes because each mode's *global block* owns the app configuration:

- *Central*: `crowdsec { api_url … api_key {env.CROWDSEC_BOUNCER_KEY} }` +
  `order crowdsec first`, gated on `CROWDSEC_BOUNCER_KEY` in `~/infra/caddy/.env`.
- *Standalone*: the stack's own global block keeps its existing crowdsec app.

A host running central caddy with an empty bouncer key runs that app
**unprotected** — check the gate before migrating a protected site.

### 1.5 Values: envsubst renders app-specifics; `{env.*}` only for shared secrets

Snippets registered with central caddy must be **concrete** — app repos render
their templates (the `init.d/20-render` pattern) before registration. The only
`{env.*}` placeholders allowed in snippets are centrally-owned secrets
(none of the three conversions need any — the `crowdsec` site directive takes
no arguments).

### 1.6 TLS: stable `acmedns.json` path

`tls { dns acmedns /etc/caddy/acmedns.json }` resolves in both modes: central
bind-mounts `~/infra/caddy/acmedns.json` at that path; standalone stacks
already mount their own copy there. **The DNS provider reads the file only at
container start** — restart the caddy container after replacing it, in either
mode.

---

## 2. `ci` — Woodpecker webhook endpoint (migrate first)

### 2.1 Current state

`~/ci/caddy/ci.broadminde.org.caddy` is already a valid snippet
(site block + per-site log filter). Docs (`README.md`, `GETTING_STARTED.md`)
say to `import` it from "the main Caddyfile" and `systemctl reload caddy` —
i.e. today it is served by a host-level Caddy on broadminde1.

Two central-mode blockers:

1. `reverse_proxy @hooks 127.0.0.1:8000` — loopback inside a container is the
   container itself.
2. `~/ci/compose.yaml` publishes `127.0.0.1:8000:8000` — unreachable from
   `host.docker.internal` even after fixing (1). **The same port serves the
   dashboard**, so opening it to `0.0.0.0` without firewall rules would expose
   the dashboard publicly — a security regression. The publish change and the
   `DOCKER-USER` rules land together.

### 2.2 Converted snippet (ships in the ci repo)

Only the upstream address changes:

```caddyfile
# Public webhook endpoint for Woodpecker CI.
#
# The dashboard is Netbird-mesh-only; this site exposes ONLY the forge
# webhook path. Hook requests are authenticated per repo (JWT access_token
# verified against the repo hash).
#
# Dual-mode:
#   central caddy — caddy-route register ci caddy/ci.broadminde.org.caddy
#   standalone    — import this file from any Caddyfile; requires
#                   host.docker.internal to resolve to the host
#                   (extra_hosts host-gateway in a container, or an
#                   /etc/hosts entry for systemd caddy).
ci.broadminde.org {
	@hooks path /api/hook*
	reverse_proxy @hooks host.docker.internal:8000
	respond 404

	# The hook auth token rides in ?access_token= — never write it to logs.
	log {
		format filter {
			wrap json
			fields {
				request>uri replace "access_token=[^&]*" "access_token=REDACTED"
			}
		}
	}
}
```

The per-site `log format filter` is snippet-legal (§2.2 of the plan): it wraps
the mode's global output — central JSON file log in central mode, whatever the
standalone caddy's global log is in standalone mode.

### 2.3 ci repo changes

1. `caddy/ci.broadminde.org.caddy` — upstream → `host.docker.internal:8000`
   (as above).
2. `compose.yaml` — woodpecker-server port block:
   ```yaml
   ports:
     - "8000:8000"   # hooks via caddy + dashboard; exposure governed by DOCKER-USER
   ```
   replaces both the `127.0.0.1:8000:8000` and `${MESH_IP}:8000:8000` binds
   (mesh-IP binds are against doctrine §2.6; the firewall rules below keep the
   dashboard mesh/LAN-only).
3. `DOCKER-USER` rules on the host (document in GETTING_STARTED; apply once):
   ```bash
   # dashboard + hooks reachable from docker bridges (central caddy) and the mesh;
   # everything else dropped.
   iptables -I DOCKER-USER -p tcp --dport 8000 -s 172.16.0.0/12 -j ACCEPT
   iptables -I DOCKER-USER -p tcp --dport 8000 -s 100.64.0.0/10 -j ACCEPT
   iptables -A DOCKER-USER -p tcp --dport 8000 -j DROP
   ```
4. `init.sh` — register when the helper exists, keep import as fallback:
   ```bash
   if command -v caddy-route >/dev/null 2>&1; then
     caddy-route register ci caddy/ci.broadminde.org.caddy
   fi
   ```
5. `README.md` / `GETTING_STARTED.md` — swap "import from the main Caddyfile"
   for register instructions; keep standalone import as the documented
   fallback (with the §1.2 `host.docker.internal` resolution note).

### 2.4 Cutover on broadminde1

1. Identify what currently serves `ci.broadminde.org` (expected: systemd
   caddy — **verify**; see §5 open questions).
2. Apply compose + firewall changes; `docker compose up -d` woodpecker.
3. Remove the site from the legacy Caddy; reload it.
4. `caddy-route register ci caddy/ci.broadminde.org.caddy`.
5. Verify: `curl -s https://ci.broadminde.org/api/hook` → 404-family response
   (not 502); a real forge webhook delivery; `caddy-route list` shows the
   server; access log lines have `access_token=REDACTED`.

Rollback: `caddy-route deregister ci`, re-import from the legacy Caddyfile.

---

## 3. `ee/infra` artifacts — static file server (optional migration)

### 3.1 Current state

`~/ee/infra/Caddyfile` (8 lines) + an `artifacts` service in
`docker-compose.yml`: stock `caddy:2-alpine`, publishes `5001:5001`, mounts
`${ARTIFACTS_DIR:-/home/luke/artifacts}` at `/data/artifacts:ro`. Read-only;
uploads happen over SSH.

### 3.2 Converted snippet (ships in ee/infra as `artifacts.caddy`)

```caddyfile
# Binary artifact file server — browseable, read-only.
# Dual-mode:
#   central caddy — caddy-route register artifacts artifacts.caddy
#                   (plus a compose.override.yaml mount, see below)
#   standalone    — import from the artifacts service's Caddyfile; the
#                   service mounts ARTIFACTS_DIR at /srv/edge/artifacts.
:5001 {
	root * /srv/edge/artifacts
	file_server browse
}
```

### 3.3 ee/infra changes

1. Standalone service volume becomes
   `- ${ARTIFACTS_DIR:-/home/luke/artifacts}:/srv/edge/artifacts:ro`
   (mount-path unification; the service otherwise unchanged).
2. Its Caddyfile becomes a global-free one-liner import of the snippet —
   or keeps the snippet inline; either satisfies dual-mode.

### 3.4 Central registration (when migrating)

`~/infra/caddy/compose.override.yaml` on the host (per §6.3 — never rendered
by the step):

```yaml
services:
  caddy:
    ports:
      - "5001:5001"
    volumes:
      - /home/luke/artifacts:/srv/edge/artifacts:ro   # shadow mount over ../edge
```

Then `docker compose up -d` and
`caddy-route register artifacts artifacts.caddy`. Retire the standalone
`artifacts` service from `ee/infra/docker-compose.yml`.

Verify: `curl -s http://<host>:5001/` returns the directory listing; uploads
over SSH still land in the same host directory.

---

## 4. `netbird-docker` — the public edge (the big one)

Prerequisites before touching it (per plan §4.2): central caddy verified on
broadminde1 **and** CrowdSec gating live — `birb.broadminde.org` is
bouncer-protected today. That means bootstrap `public: true` on broadminde1,
root-tier 54-crowdsec run (host LAPI + the deploy user's `crowdsec` group),
and `CROWDSEC_BOUNCER_KEY` populated in `~/infra/caddy/.env`.

### 4.1 Current state (`Caddyfile.tmpl`, 211 lines)

- **Global block**: JSON log to `/data/logs/access.log`; `crowdsec` app
  (`api_url http://crowdsec:8080`, `{env.CROWDSEC_BOUNCER_KEY}`);
  `order crowdsec first`. → **all owned centrally in central mode**; kept
  verbatim for standalone mode.
- **`http://:${NETBIRD_API_PORT}`** (8082): plain-HTTP loopback listener for
  the NetBird REST API (local MCP tools; PAT-authenticated). Published today
  as `127.0.0.1:8082:8082`.
- **`${SITE_NAMES}`** (birb + optional direct domain):
  `tls { dns acmedns /etc/caddy/acmedns.json }`; site-level `crowdsec`;
  `@cf_blocked` CDN allowlist; gRPC (`h2c`), websocket, and backend routes to
  `netbird-server:80`; `@deploy` static assets (`root * /srv/deploy` +
  strip_prefix); sidecar SPA/API to `netbird-installer:8080`; dashboard
  fallback with edge CSP to `dashboard:80`.

### 4.2 The split

`Caddyfile.tmpl` becomes two files:

**`Caddyfile.tmpl` (standalone global block — unchanged content, new role):**
the existing global block (log + crowdsec app + order) plus one line at the
end: `import ./caddy/netbird.caddy`. This keeps today's standalone deployment
working with the *same* site configuration that central mode registers.

**`caddy/netbird.caddy.tmpl` (the dual-mode snippet template)** — rendered by
the existing `init.d/20-render` to `caddy/netbird.caddy`:

```caddyfile
# NetBird site blocks — dual-mode snippet.
# Rendered by init.d/20-render → caddy/netbird.caddy.
#
#   central caddy — caddy-route register netbird caddy/netbird.caddy
#   standalone    — imported by this stack's Caddyfile, which provides the
#                   global block (log, crowdsec app, order crowdsec first).
#
# Routes (in evaluation order): unchanged from the legacy monolith —
#   crowdsec, @cf_blocked, @grpc/@grpcPaths (h2c), @websocket, @backend,
#   @deploy (static assets), @sidecarRoot/@sidecarTree, dashboard fallback.

http://:${NETBIRD_API_PORT} {
    reverse_proxy netbird-server:80
}

${SITE_NAMES} {
    tls {
        dns acmedns /etc/caddy/acmedns.json
    }

    crowdsec

    @cf_blocked {
        host ${CF_PROXIED_HOSTS}
        not remote_ip \
            103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 \
            104.16.0.0/13  104.24.0.0/14   108.162.192.0/18 \
            131.0.72.0/22  141.101.64.0/18 162.158.0.0/15 \
            172.64.0.0/13  173.245.48.0/20 188.114.96.0/20 \
            190.93.240.0/20 197.234.240.0/22 198.41.128.0/17 \
            2400:cb00::/32 2606:4700::/32  2803:f800::/32 \
            2405:b500::/32 2405:8100::/32  2a06:98c0::/29 \
            2c0f:f248::/32
    }
    respond @cf_blocked 403

    @grpc header Content-Type application/grpc*
    reverse_proxy @grpc h2c://netbird-server:80

    @grpcPaths path /signalexchange.SignalExchange/* /management.ManagementService/*
    reverse_proxy @grpcPaths h2c://netbird-server:80

    @websocket path /ws-proxy/signal /ws-proxy/management
    reverse_proxy @websocket netbird-server:80

    @backend path /relay* /ws-proxy/* /api/* /oauth2/*
    reverse_proxy @backend netbird-server:80

    @deploy path /deploy/*
    handle @deploy {
        root * /srv/edge/netbird
        uri strip_prefix /deploy
        file_server
    }

    @sidecarRoot path /sidecar
    handle @sidecarRoot {
        redir /sidecar /sidecar/ 308
    }

    @sidecarTree path /sidecar/ /sidecar/* /sidecar/api/* /sidecar/auth/*
    handle @sidecarTree {
        reverse_proxy netbird-installer:8080
    }

    reverse_proxy /* dashboard:80 {
        header_down Content-Security-Policy "default-src 'none'; script-src 'self' 'wasm-unsafe-eval' 'sha256-7knV6EIjKUvCpYWE2rCYx8dYV2WCNb2bpTuitFXzBcA='; style-src 'self' 'unsafe-inline'; connect-src 'self' https://${NETBIRD_DOMAIN} wss://${NETBIRD_DOMAIN} https://api.github.com/repos/netbirdio/netbird/releases/latest https://raw.githubusercontent.com/netbirdio/dashboard/; frame-src 'self' https://${NETBIRD_DOMAIN} https://${NETBIRD_DOMAIN}/oauth2; font-src 'self'; img-src * data:; manifest-src 'self'; frame-ancestors 'self'; base-uri 'self'; form-action 'self'; upgrade-insecure-requests;"
    }
}
```

Every directive is copied verbatim from the current template except
`root * /srv/deploy` → `root * /srv/edge/netbird` (§1.3). The full header
comment block from the current template (route documentation, dev-server
notes, plan references) carries over — trim shown here for brevity only.

### 4.3 netbird-docker repo changes

1. **Split** as above; `init.d/20-render` renders both templates (it already
   computes `SITE_NAMES`, `CF_PROXIED_HOSTS`, `NETBIRD_DOMAIN` — no new
   variables).
2. **compose** (`docker-compose.yml`):
   - Join `netbird-server`, `dashboard`, `netbird-installer` to the external
     `edge` network (§1.1). They keep the `netbird` network too.
   - Deploy assets: move `scripts/install-pfsense.sh` into a dedicated
     `deploy/` dir and mount `./deploy:/srv/edge/netbird:ro` on the
     (standalone) caddy service — replacing the single-file `/srv/deploy`
     mount. Central mode serves the same path from `~/infra/edge/netbird/`.
3. **Standalone validation step**: after the split, run the stack with its own
   caddy (global block + import) and confirm zero behavior change. **Do this
   before any central cutover** — it proves the snippet in isolation.
4. **Registration step**: new `init.d/55-central-route` (runs after 50-stack):
   ```bash
   if command -v caddy-route >/dev/null 2>&1; then
     caddy-route register netbird caddy/netbird.caddy
   fi
   ```
   Absent the helper, the stack's own caddy keeps serving (standalone mode) —
   the init script picks the mode by probing, exactly like the ci repo.
5. **Cutover commit** (separate from the split): remove the `caddy` service
   and its `45-build` target; retire the in-stack `crowdsec` container and its
   acquis mount (host LAPI + host acquis from 54-crowdsec take over — it
   already tails `~/infra/caddy/logs/access.log`); drop the
   `CROWDSEC_BOUNCER_KEY` plumbing from netbird's `.env`.

### 4.4 Host-side cutover sequence (broadminde1)

Port clash: the old caddy holds 80/443, so the central container cannot be up
first. Sequence for minimal downtime:

1. **Prep (no downtime)**:
   - `./user/init.sh 60-caddy` — but *stop the container* afterwards
     (`docker compose -f ~/infra/caddy/compose.yaml stop`) since ports clash.
   - Move acme-dns creds: `cp caddy_data/acmedns.json ~/infra/caddy/acmedns.json`,
     `chmod 600`.
   - Copy deploy assets to `~/infra/edge/netbird/`.
   - **Copy the cert store** so no re-issuance storm hits Let's Encrypt
     rate limits:
     ```bash
     docker run --rm -v netbird-docker_caddy_data:/from -v caddy_caddy_data:/to \
       alpine cp -a /from/. /to/
     ```
     (volume names per each compose project; verify with `docker volume ls`.)
   - Central `compose.override.yaml`: publish the API listener with its
     current loopback semantics:
     ```yaml
     services:
       caddy:
         ports:
           - "127.0.0.1:8082:8082"
     ```
2. **Cutover (seconds)**:
   - `docker compose stop caddy` (old stack).
   - `docker compose -f ~/infra/caddy/compose.yaml up -d` (central starts,
     certs already present, `--resume` irrelevant on first boot — routes.d
     replays after registration).
   - `caddy-route register netbird caddy/netbird.caddy`.
3. **Verify**:
   - `init.d/80-verify` probes **unchanged** — cert path root is the same
     `/data/caddy/...` inside the central container.
   - Client-facing: TLS handshake on birb, signal exchange gRPC, dashboard
     load, `/deploy/install-pfsense.sh` download, sidecar SPA, a
     deliberately-blocklisted IP → 403 (CrowdSec path), a non-CF IP with
     CF-fronted Host header → 403 (`@cf_blocked`).
   - MCP tools: `curl -H "Authorization: Token <pat>" http://127.0.0.1:8082/api/...`.
   - fail2ban jails reading `~/infra/caddy/logs/access.log` (53-fail2ban
     derivation) — `fail2ban-client status caddy-auth`.
4. **Rollback**: `caddy-route deregister netbird`; `docker compose up -d` the
   old stack's caddy service (keep the compose change revertible until the
   migration has soaked).

### 4.5 What changes semantically

- **CrowdSec LAPI moves** from in-stack container to host LAPI
  (`CROWDSEC_API_URL=http://host.docker.internal:8080` in central `.env`).
  Fail-open semantics preserved (bouncer plugin's `enable_hard_fails` stays
  off; central gate is empty-key = no crowdsec).
- **Log consumers move with the log**: fail2ban (53-fail2ban, derived path —
  already updated) and CrowdSec acquis (54-crowdsec, derived path — already
  updated) both point at `~/infra/caddy/logs/access.log`. The legacy
  `/home/stack/netbird-docker/...` fallbacks in those steps are removed once
  netbird migrates.
- **`@cf_blocked` semantics unchanged**: neither the old nor the central
  global block sets `trusted_proxies`; `remote_ip` stays the real client IP.
- **Cert renewal continuity**: same ACME account (copied volume), same
  acme-dns creds, same names — renewals continue on schedule inside the
  central container.

---

## 5. Open questions to resolve on broadminde1 before executing

1. **What serves `ci.broadminde.org` today?** The ci docs say
   `systemctl reload caddy` — if a systemd caddy exists on broadminde1, it
   clashes with central caddy on 80/443 and must be retired as part of the ci
   migration (it may also be serving other sites — inventory its Caddyfile
   first).
2. **Is broadminde1 bootstrap-provisioned with `public: true`?** Netbird's
   migration requires the host LAPI (54-crowdsec). If the host predates
   bootstrap, run the bootstrap root tier (or at least 54-crowdsec) first.
3. **Exact volume name of netbird's `caddy_data`** for the cert-store copy
   (`docker volume ls` — compose project prefix varies).
4. **Does anything else publish 80/443 on broadminde1?** `docker ps` +
   `ss -tlnp` before cutover.
5. **artifacts migration** is optional — decide after netbird soaks.

## 6. Execution order

1. **ci** (proves the primitive with a real cert; small blast radius).
2. **netbird split + standalone validation** (no central involvement yet).
3. **netbird central cutover** (after CrowdSec gating confirmed).
4. **artifacts** (optional; any time after 1).
5. **Cleanup**: remove legacy log-path fallbacks from 53-fail2ban /
   54-crowdsec; delete this file's open questions once answered.
