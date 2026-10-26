---
name: central-caddy
description: >-
  Create and register Caddy reverse-proxy snippets for apps on this host's
  central Caddy instance. USE FOR: onboarding an app to central Caddy,
  writing a .caddy snippet, registering or deregistering routes with
  caddy-route, viewing runtime or access logs, checking route health, and
  troubleshooting Caddy 404/502 responses, TLS, DNS, or backend connectivity.
  DO NOT USE FOR: provisioning or upgrading the host-level Caddy stack,
  destructive stack maintenance, non-Caddy reverse proxies, or Caddy on hosts
  without the central stack. See references/operator-guide.md for operations.
---

# Central Caddy — App Onboarding

Create a Caddyfile snippet and register it with the host's central Caddy
reverse proxy. The central instance handles TLS, routing, and (optionally)
CrowdSec — app snippets are site blocks only.

## Discovery

Check whether central Caddy is provisioned on this host when you need live
host settings:

```bash
cat ~/infra/caddy/central.json
```

If the file exists, it contains the registration CLI path, snippet contract,
backend reachability patterns, and container status. If absent, central Caddy
is not provisioned — fall back to standalone `import` of the snippet.

## Snippet Contract

Snippets are **Caddyfile fragments with site blocks only**.

**Allowed:** site blocks, `reverse_proxy`, `file_server`, `handle`, `route`,
`tls`, `log`, `header`, `respond`, `redir`, matchers (`path`, `remote_ip`,
`header`, etc.)

**Forbidden:** global blocks (`{ ... }`), global options (`email`, `admin`,
`storage`, `crowdsec`). The register command validates and rejects these.

**App name constraints:**
- Characters: `[a-zA-Z0-9._-]+` (no spaces, no slashes)
- Must NOT end in `-wildcard` (reserved for zone management)
- Must be unique — the name becomes `routes.d/<name>.caddy`

## TLS

Use Caddy's default automatic HTTPS for public names. Do not add a `tls` block
unless the name needs DNS-01, such as a wildcard or a non-public name:

```caddyfile
tls {
    dns acmedns /etc/caddy/acmedns.json
}
```

The reconcile merge preserves per-site TLS policies and injects the global ACME
identity (email and CA) into per-site issuers. Names without an explicit DNS-01
policy use the global default, which is HTTP-01/TLS-ALPN. One DNS-01 provider
(`acmedns`) is supported per host.

## Backend Reachability

Two patterns, in preference order:

1. **Edge network** (preferred) — app joins the `edge` Docker network;
   snippet targets container name: `reverse_proxy myapp:3000`
2. **Host-published port** (fallback) — app binds to `0.0.0.0:<port>` on the
   host; snippet targets `host.docker.internal:<port>`

For host-published ports, arrange a persistent, host-specific firewall rule
that blocks direct public access while allowing the Caddy container through.
Docker DNAT bypasses ufw's INPUT chain; check the host's `DOCKER-USER` policy
and interface before adding rules. Prefer the edge network to avoid publishing
the port at all.

## Patterns

### A: Docker Compose app on the edge network

App's `compose.yaml`:

```yaml
services:
  myapp:
    networks:
      - edge

networks:
  edge:
    external: true
    name: edge
```

No port publishing needed — Caddy reaches the container by name. A name under
an already provisioned wildcard zone needs no per-snippet TLS configuration:

Snippet (`myapp.caddy`):

```caddyfile
myapp.dev.broadminde.org {
    reverse_proxy myapp:3000
}
```

### B: Host-level dev server (Vite, etc.)

Dev server must bind to `0.0.0.0` (not `localhost`):

```bash
npx vite --host 0.0.0.0 --port 5173
```

Or in `vite.config.ts`: `server: { host: true }`

Snippet:

```caddyfile
myapp.dev.broadminde.org {
    reverse_proxy host.docker.internal:5173
}
```

### C: Custom subdomain (not under a wildcard zone)

Requires an A record at the provider. Public names use automatic HTTPS; if
the name needs DNS-01, also delegate its ACME challenge and add the `tls`
block shown above:

```
myapp.broadminde.org                          A      <host-ip>
# Only for DNS-01:
_acme-challenge.myapp.broadminde.org          CNAME  <acme-dns-fulldomain>
```

Snippet is the same shape, with the custom hostname.

### D: Static file server

Drop files at `~/infra/edge/<app-name>/` on the host (mounted read-only
at `/srv/edge` in the container).

Snippet:

```caddyfile
static.dev.broadminde.org {
    root * /srv/edge/myapp
    file_server
}
```

## Registration

```bash
caddy-route register <app-name> <path/to/snippet.caddy>
caddy-route deregister <app-name>
caddy-route list
```

Registration is zero-downtime: validate → copy to `routes.d/` → reconcile
(merge + `POST /load` to Admin API). Rollback on failure is automatic.

Validate without registering:

```bash
docker exec -i caddy caddy adapt --config - --adapter caddyfile < myapp.caddy
```

## Automating in init.sh

Gate on discovery, render from a template, register. Keep rendered snippets
in the app workspace rather than creating host-global temporary files:

```bash
if [ -f "$HOME/infra/caddy/central.json" ] && command -v caddy-route >/dev/null 2>&1; then
  APP_HOST="${APP_HOST:-myapp.dev.broadminde.org}"

  mkdir -p .tmp
  sed -e "s|\${APP_HOST}|$APP_HOST|g" \
      -e "s|\${APP_PORT}|$APP_PORT|g" caddy/myapp.caddy.tmpl > .tmp/myapp.caddy
  caddy-route register myapp .tmp/myapp.caddy
  rm -f .tmp/myapp.caddy
else
  echo "NOTE: central caddy not detected — register manually"
fi
```

Template (`caddy/myapp.caddy.tmpl`):

```caddyfile
${APP_HOST} {
    reverse_proxy host.docker.internal:${APP_PORT}
}
```

Deregister on teardown: `caddy-route deregister myapp`

## Verification

```bash
caddy-route list                    # registered routes vs live config
docker logs caddy --tail 50         # container logs
dig +short myapp.dev.broadminde.org # DNS resolution
curl -v https://myapp.dev.broadminde.org/

# Bypass public DNS/CDN while preserving SNI and certificate validation:
curl --resolve myapp.dev.broadminde.org:443:127.0.0.1 \
  https://myapp.dev.broadminde.org/

# Preferred edge-network backend check from Caddy's network namespace:
docker exec caddy curl -fsS http://myapp:3000/healthz
```

## Logs

```bash
docker logs caddy --tail 100         # recent runtime/TLS/configuration logs
docker logs caddy --since 30m        # runtime logs for a time window
docker logs -f caddy                 # follow runtime logs
tail -f ~/infra/caddy/logs/access.log
jq 'select(.request.host == "myapp.dev.broadminde.org")' \
  ~/infra/caddy/logs/access.log
```

Access logs exist only when the site block includes the `log` directive. Runtime
logs always go to container stdout. Do not print logs into reports without first
checking them for credentials, query parameters, or other sensitive values.

## Deregistration

```bash
caddy-route list
caddy-route deregister myapp
caddy-route list
```

Deregistration removes `routes.d/myapp.caddy` and immediately reconciles the
live config. If reconcile fails, `caddy-route` restores the file and retries the
previous configuration. Deregister during app teardown before removing its
backend, then verify that the hostname no longer reaches the app.

## Troubleshooting

| Symptom | First checks |
|---|---|
| Route missing | Run `caddy-route list`; inspect `~/infra/caddy/routes.d/` |
| 404 | Confirm the requested hostname, route listing, and live config |
| 502 | Run the upstream check from inside `caddy`; verify port and `edge` membership |
| TLS failure | Check DNS, then `docker logs caddy --tail 100` |
| Caddy unavailable | Run `docker inspect caddy`, then inspect runtime logs |
| Disk/live mismatch | Run `caddy-route reconcile`, then `caddy-route list` |

Use `references/operator-guide.md` for exact live-config commands, access-log
setup, container lifecycle, wildcard DNS, CrowdSec, and deeper diagnostics.

## References

- **Operator guide**: `references/operator-guide.md` (relative to this skill) — full day-2 ops,
  TLS modes, wildcard zones, CrowdSec, teardown
- **Discovery file**: `~/infra/caddy/central.json` — machine-readable
  live contract for this host; do not rely on a bundled snapshot
- The historical master design plan remains in the bootstrap checkout and is
  intentionally not deployed; it is not needed for day-to-day operation.
