# Central Caddy — operator's guide

The host's central Caddy reverse proxy is installed by `bootstrap/user/init.d/60-caddy`
to `~/infra/caddy/` (deploy-user owned — the step runs as the deploy user in the
user tier). The step provisions, renders, and builds but **never starts the
container** — you bring it up explicitly (see Container lifecycle). App stacks
register Caddyfile snippets and get TLS/routing automatically.

## Snippet contract

A snippet is a **Caddyfile fragment with site blocks only**:

```caddyfile
myapp.host.broadminde.org {
	reverse_proxy myapp:8080
}

:5001 {
	root * /srv/edge/artifacts
	file_server
}
```

(`/srv/edge` inside the container is a read-only mount of `~/infra/edge` on
the host — drop static assets there from any app stack.)

- **Allowed**: site blocks, matchers, `handle`, `tls`, `log`, `reverse_proxy`, `file_server`.
- **Forbidden**: global blocks `({ ... })` — ACME email, storage, admin, CrowdSec, and
  logging are owned centrally. The register command rejects global blocks.
- `{env.VAR}` placeholders resolve inside the container (secrets only — e.g.
  `{env.CROWDSEC_BOUNCER_KEY}`). App-specific values (domains, upstreams) should
  be **rendered into the snippet by the app repo** (envsubst) before registration.
- Dual-mode: a snippet is also a valid `import` target for any standalone Caddy.

## Registration

```bash
caddy-route register <app> <file.caddy>   # validate → routes.d → reconcile
caddy-route deregister <app>              # rm routes.d/<app>.caddy → reconcile
caddy-route list                          # routes.d files vs live server names
caddy-route reconcile                     # manual replay (run.sh does this automatically)
```

- **Zero-downtime**: config changes are pushed via `POST /load` (Admin API over
  unix socket inside the container). No restart, no dropped connections.
- **Atomic**: `/load` rejects invalid configs — the running config is untouched.
- **Idempotent**: registering an already-registered snippet is a no-op (hash skip).
- **Rollback**: if reconcile fails after copy, the just-added file is removed and
  merge is re-run to restore the prior state.

## Backend reachability

1. **Preferred — `edge` network**: add `networks: { edge: { external: true, name: edge } }`
   to app services Caddy proxies → snippet uses container names:
   `reverse_proxy myapp:8080`.
2. **Host-published ports**: app publishes `0.0.0.0:<port>` and snippet targets
   `host.docker.internal:<port>` (mapped via `extra_hosts`).

Restrict published-port access with `DOCKER-USER` iptables rules — Docker DNAT
bypasses ufw's INPUT, so the `DOCKER-USER` chain is the only firewall that sees
container traffic.

## TLS modes

| Case | Mechanism | Snippet needs |
|---|---|---|
| Public name (`ci.broadminde.org`) | default ACME HTTP/TLS-ALPN | nothing — auto |
| Wildcard / non-public name | DNS-01 via acme-dns CNAME delegation | `tls { dns acmedns /etc/caddy/acmedns.json }` |

### DNS-01 setup

Run once per host:

```bash
~/infra/caddy/bin/acmedns-register
```

It registers with `auth.acme-dns.io`, writes `acmedns.json`, and prints the
`_acme-challenge` CNAMEs you must add to DNS for each delegated name.

```bash
# Restart Caddy after creating acmedns.json (the DNS provider reads it at init):
docker restart caddy
```

## Port conflicts

The step **never starts a stopped container**, so running it on a host whose
80/443 are already held (e.g. a legacy per-stack caddy) is safe: it
provisions and builds, prints a warning naming the listeners, and stops
short of starting. The conflict then matters only when YOU start it —
`docker compose up -d` will fail loudly until the old service is stopped or
the ports are remapped via `~/infra/caddy/compose.override.yaml` (replacing
the base ports needs the `!override` tag; plain extra publishes/mounts merge
additively without one):

```yaml
services:
  caddy:
    ports: !override
      - "127.0.0.1:8085:80"
      - "127.0.0.1:8443:443"
```

## Container lifecycle

- **Start**: `cd ~/infra/caddy && docker compose up -d` — always an explicit
  operator action; the provisioning step never starts a stopped container.
  When the container is already running, re-running the step applies updates
  in place (rebuild + recreate on change) and replays routes.d.
- **Stop**: `cd ~/infra/caddy && docker compose stop` — stays down across
  step re-runs and reboots until started again.
- **Restart**: safe — `--resume` restores registered apps from `autosave.json`
- **Rebuild**: re-run `./user/init.sh 60-caddy` (wipes autosave, replays routes.d
  when running; otherwise start it yourself and run `caddy-route reconcile`)
- **Logs**: `docker logs caddy --tail 50` or read `~/infra/caddy/logs/access.log`
  (JSON, rotated 100MB×5)

Always invoke compose **from the live dir** (or with
`docker compose --project-directory ~/infra/caddy`) — an explicit
`-f ~/infra/caddy/compose.yaml` suppresses `compose.override.yaml` discovery
and silently drops the host's per-host overrides.

## Teardown / opting out

Setting `caddy: false` in `bootstrap.conf.yml` only stops the provisioning
step from running — it does **not** undeploy anything. An installed central
Caddy keeps running (and holding ports 80/443) until torn down by hand:

```bash
cd ~/infra/caddy && docker compose down
```

The named volumes persist afterwards. Remove them only if you are retiring
the stack for good — `caddy_caddy_data` holds issued ACME certificates and
accounts, and `caddy_caddy_config` holds the autosave registry:

```bash
docker volume rm caddy_caddy_config caddy_caddy_data   # destructive: certs lost
```

## Day-2 operations

### Add a new app

```bash
# 1. Write a snippet in your app repo (e.g. myapp/myapp.caddy).
# 2. In your app's init.sh:
caddy-route register myapp ./myapp.caddy
```

### Upgrade Caddy version

Edit `~/infra/caddy/Dockerfile` and bump `CADDY_VERSION` (and plugin pins),
then re-run the user-tier step:

```bash
./user/init.sh 60-caddy
```

### Debug a snippet

```bash
# Validate a snippet without registering it:
docker exec caddy caddy adapt --config - --adapter caddyfile < myapp.caddy

# See the running config:
docker exec caddy curl --unix-socket /run/caddy-admin.sock http://localhost/config/ | jq .

# Check cert status:
docker exec caddy curl --unix-socket /run/caddy-admin.sock http://localhost/config/apps/tls/certificates | jq .
```

### Fallback: standalone import

Snippets are valid standalone Caddyfile imports. On hosts without the central
stack, import the snippet directly:

```caddyfile
import path/to/myapp.caddy
```

Then `caddy reload` or restart the container.

## Architecture

- **One Caddy container per host**, named `caddy`, on the `edge` docker network.
- **Admin API: unix socket only** (`/run/caddy-admin.sock` inside the container),
  reached via `docker exec caddy curl --unix-socket …`. No TCP admin surface.
  Authorization = docker group membership (deploy user).
- **Ports**: 80 and 443 on `0.0.0.0` and `[::]`. No mesh or bridge IP binds —
  everything publishes on `0.0.0.0` and the firewall decides access.
- **Registry**: `~/infra/caddy/routes.d/<app>.caddy` is the source of truth on
  disk. Reconcile replays it into the running config.
- **Static assets**: `~/infra/edge/` on the host mounts to `/srv/edge` (ro) in
  the container — the conventional root for `file_server` snippets.

## Related files

- `bootstrap/user/init.d/60-caddy/run.sh` — the provisioning step (user tier)
- `bootstrap/user/init.d/60-caddy/stack/` — Dockerfile, compose, template, helpers
- `bootstrap/_plans/central-caddy.md` — full specification and design rationale
- `bootstrap/_plans/caddy-conversions.md` — Phase 2: converting the existing ci,
  netbird, and artifacts Caddy instances into dual-mode snippets
- `bootstrap/init.d/53-fail2ban/run.sh` — reads `~/infra/caddy/logs/access.log`
- `bootstrap/init.d/54-crowdsec/run.sh` — LAPI + bouncer; grants the deploy
  user `crowdsec` group membership (enables `cscli` from the user tier)
