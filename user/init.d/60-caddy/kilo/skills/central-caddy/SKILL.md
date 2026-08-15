---
name: central-caddy
description: >-
  Create and register Caddy reverse-proxy snippets for apps on this host's
  central Caddy instance. USE FOR: onboarding an app to central Caddy,
  writing a .caddy snippet, registering a route with caddy-route, reverse
  proxying through Caddy, adding a subdomain for an app, serving an app
  behind Caddy, Caddyfile snippet creation. DO NOT USE FOR: operating the
  Caddy server itself (see ~/bootstrap/docs/central-caddy.md), non-Caddy
  reverse proxies, or Caddy on hosts without the central stack.
---

# Central Caddy — App Onboarding

Create a Caddyfile snippet and register it with the host's central Caddy
reverse proxy. The central instance handles TLS, routing, and (optionally)
CrowdSec — app snippets are site blocks only.

## Discovery

Check whether central Caddy is provisioned on this host:

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

Every snippet MUST declare DNS-01 TLS:

```caddyfile
tls {
    dns acmedns /etc/caddy/acmedns.json
}
```

This is required for all names — wildcard zones require DNS-01 by Let's
Encrypt policy, and the reconcile merge injects the global ACME identity
(email, CA) into per-site issuers automatically. HTTP-01 is never used.

## Backend Reachability

Two patterns, in preference order:

1. **Edge network** (preferred) — app joins the `edge` Docker network;
   snippet targets container name: `reverse_proxy myapp:3000`
2. **Host-published port** (fallback) — app binds to `0.0.0.0:<port>` on the
   host; snippet targets `host.docker.internal:<port>`

For host-published ports, restrict public access with DOCKER-USER iptables:

```bash
iptables -I DOCKER-USER -p tcp -i eth0 --dport <port> -j DROP
```

Docker DNAT bypasses ufw's INPUT chain. The Caddy container still reaches
the port via the Docker bridge.

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

No port publishing needed — Caddy reaches the container by name.

Snippet (`myapp.caddy`):

```caddyfile
myapp.dev.broadminde.org {
    tls {
        dns acmedns /etc/caddy/acmedns.json
    }
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
    tls {
        dns acmedns /etc/caddy/acmedns.json
    }
    reverse_proxy host.docker.internal:5173
}
```

### C: Custom subdomain (not under a wildcard zone)

Requires DNS records at the provider:

```
myapp.broadminde.org                          A      <host-ip>
_acme-challenge.myapp.broadminde.org          CNAME  <acme-dns-fulldomain>
```

Snippet is the same shape, with the custom hostname.

### D: Static file server

Drop files at `~/infra/edge/<app-name>/` on the host (mounted read-only
at `/srv/edge` in the container).

Snippet:

```caddyfile
static.dev.broadminde.org {
    tls {
        dns acmedns /etc/caddy/acmedns.json
    }
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
docker exec caddy caddy adapt --config - --adapter caddyfile < myapp.caddy
```

## Automating in init.sh

Gate on discovery, render from a template, register:

```bash
if [ -f "$HOME/infra/caddy/central.json" ] && command -v caddy-route >/dev/null 2>&1; then
  APP_HOST="${APP_HOST:-myapp.dev.broadminde.org}"

  tmpfile=$(mktemp)
  sed "s|\${APP_HOST}|$APP_HOST|g" caddy/myapp.caddy.tmpl > "$tmpfile"
  caddy-route register myapp "$tmpfile"
  rm -f "$tmpfile"
else
  echo "NOTE: central caddy not detected — register manually"
fi
```

Template (`caddy/myapp.caddy.tmpl`):

```caddyfile
${APP_HOST} {
    tls {
        dns acmedns /etc/caddy/acmedns.json
    }
    reverse_proxy host.docker.internal:${APP_PORT}
}
```

Deregister on teardown: `caddy-route deregister myapp`

## Verification

```bash
caddy-route list                    # registered routes vs live config
docker logs caddy --tail 50         # container logs
dig +short myapp.dev.broadminde.org # DNS resolution
```

## References

- **Operator guide**: `~/bootstrap/docs/central-caddy.md` — full day-2 ops,
  TLS modes, wildcard zones, CrowdSec, teardown
- **Discovery file**: `~/infra/caddy/central.json` — machine-readable
  contract for this host
- **Master spec**: `~/bootstrap/_plans/central-caddy.md` — design rationale
