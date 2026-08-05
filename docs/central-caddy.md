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

Per-site `tls` policies are preserved at reconcile (the merge in `caddy-route`'s
`reconcile`): subject-scoped DNS-01 policies keep their `subjects`, the global
issuer's `email`/`ca` identity is injected into their acme issuers, and subject
policies are ordered ahead of the subject-less default. DNS-01 via acme-dns
therefore applies only to names that declare it (wildcard zones, plus any app
snippet with its own `tls { dns acmedns … }` block); every other name uses the
default HTTP-01/TLS-ALPN challenges. One DNS-01 provider (acmedns) per host —
introducing a different DNS provider requires reworking the merge logic.

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

One `acmedns-register` run yields one acme-dns account. Each zone label
requires its own `_acme-challenge` CNAME pointing at the same fulldomain:

```
_acme-challenge.<label>.<base_domain>  CNAME  <uuid>.auth.acme-dns.io
```

For the `host` label, the CNAME is `_acme-challenge.<hostname>.<base_domain>`.
Acme-dns holds max 2 TXT records per account — stagger first issuance if errors
appear (the wildcard zone render prints each `*.zone` it writes; certificates
provision internally within a few minutes).

## Wildcard zones

Wildcard zones are configured in `bootstrap.conf.yml` under the `caddy:` section:

```yaml
caddy:
  base_domain: example.com
  wildcards: "dev host"
```

- **`base_domain`** — zone apex. A label `L` serves `*.L.base_domain`; the
  special label `host` serves `*.<hostname>.base_domain`.
- **`wildcards`** — space-separated DNS labels matching
  `^[a-z0-9]([a-z0-9-]*[a-z0-9])?$`. Empty string = no zone snippets.
- **Creds gate**: rendering activates only after `acmedns.json` holds a real
  acme-dns account. The render step prints a NOTE naming `bin/acmedns-register`
  as remediation when the gate blocks.

**Skip matrix** (each branch prints a NOTE naming the condition):
1. `wildcards` empty → no zones rendered; stale `*-wildcard.caddy` files are
   removed (deliberate opt-out).
2. `wildcards` set, `base_domain` empty → skip everything; existing files
   untouched.
3. `wildcards` set, creds gate fails → skip everything; existing files
   untouched.
4. `wildcards` set + gate passes → render active zones; stale
   `*-wildcard.caddy` files removed.

**Cert-warming model**: each wildcard site block is a placeholder that warms a
cert. Apps register more-specific site blocks via `caddy-route` — the most
specific match wins. A registered app site MAY obtain its own cert via the
same acme-dns account (Caddy's internal cert-grant flow controls this; no
per-snippet TLS configuration is required).

**Stale cleanup**: dropped zones are removed from `routes.d/` and reconciled
away. The zone's certificate remains unused in `caddy_data` until it expires
and is not renewed.

**Reserved names**: app names ending in `-wildcard` are reserved at registration
(these are owned by the wildcard zone renderer).

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

## CrowdSec

The bouncer plugin gates on the `public` capability + a generated key (Step 2).
When enabled, caddy streams decisions from the host LAPI at
`http://host.docker.internal:8080`. The host side expects
`listen_uri: 0.0.0.0:8080` and a ufw `172.16.0.0/12 → 8080/tcp` rule — both
owned by root-tier `54-crowdsec`. The bouncer is **fail-open** (hard-fails off)
so a broken link is silent: caddy serves traffic but enforces zero CrowdSec
decisions.

Diagnostics:
```bash
docker exec caddy caddy crowdsec health --address unix//run/caddy-admin.sock
docker exec caddy caddy crowdsec ping  --address unix//run/caddy-admin.sock
docker exec caddy caddy crowdsec check <ip> --address unix//run/caddy-admin.sock
cscli bouncers list          # is caddy-edge registered?
```

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
- `bootstrap/user/init.d/60-caddy/stack/wildcard.caddy.tmpl` — config-driven wildcard zone template
- `bootstrap/_plans/central-caddy.md` — full specification and design rationale
- `bootstrap/_plans/caddy-conversions.md` — Phase 2: converting the existing ci,
  netbird, and artifacts Caddy instances into dual-mode snippets
- `bootstrap/init.d/53-fail2ban/run.sh` — reads `~/infra/caddy/logs/access.log`
- `bootstrap/init.d/54-crowdsec/run.sh` — LAPI + bouncer; grants the deploy
  user `crowdsec` group membership (enables `cscli` from the user tier)
