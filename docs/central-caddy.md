# Central Caddy — operator's guide

The host's central Caddy reverse proxy is provisioned by the repository's
`user/init.d/60-caddy` step to `~/infra/caddy/` (deploy-user owned — the step runs
as the deploy user in the user tier). On a provisioned host this source step is
normally `~/bootstrap/user/init.d/60-caddy`. The step provisions, renders,
builds, and **starts the container itself** — refusing only when ports 80/443
are held by another service — then **verifies wildcard readiness**: for every
configured zone it confirms the `_acme-challenge` CNAME delegation resolves and
the certificate has been issued, failing loudly when either is missing. App
stacks register Caddyfile snippets and get TLS/routing automatically.

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

- **Supported**: site blocks and site-level directives such as matchers, `handle`,
  `route`, `tls`, `log`, `header`, `respond`, `redir`, `reverse_proxy`, and
  `file_server`.
- **Forbidden**: global blocks `({ ... })` — ACME email, storage, admin, CrowdSec, and
  logging are owned centrally. The register command rejects global blocks.
- `{env.VAR}` placeholders resolve inside the container (secrets only — e.g.
  `{env.CROWDSEC_BOUNCER_KEY}`). App-specific values (domains, upstreams) should
  be **rendered into the snippet by the app repo** (envsubst) before registration.
- Dual-mode: a snippet is also a valid `import` target for any standalone Caddy.

Registration does **not** enforce a directive allowlist, hostname ownership, or
safe file roots. Treat anyone who can register a snippet as fully trusted to
control the edge, including access to files and environment inside Caddy. See
`docs/caddy-route-security-review.md` in the bootstrap checkout before granting
app pipelines access.

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

### Remove an app route

Inspect the registry before and after removal:

```bash
caddy-route list
caddy-route deregister myapp
caddy-route list
```

Deregistration removes `~/infra/caddy/routes.d/myapp.caddy`, immediately
reconciles the live configuration, and reports `Not registered` when the file is
already absent. If reconciliation fails, the command restores the route file and
attempts to restore the previous live configuration. During application
teardown, deregister before removing the backend where practical, then verify
that the hostname no longer reaches the application.

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
acmedns-register
```

On first registration it writes `acmedns.json` and prints a generic
`_acme-challenge.<your-name>` CNAME pattern and an example, not a list of
configured names. If credentials already exist, it skips registration without
printing DNS records. The `user/init.d/60-caddy` step runs registration when
needed and prints the exact configured CNAMEs when wildcard readiness fails.

After creating or replacing `acmedns.json`, recreate the container so the
individual bind mount and the DNS provider load the new credentials. A reload
or `docker restart` may retain the old mount after atomic file replacement:

```bash
cd ~/infra/caddy
docker compose up -d --no-build --force-recreate caddy
```

One `acmedns-register` run yields one acme-dns account. Each zone label
requires its own `_acme-challenge` CNAME pointing at the same fulldomain:

```
_acme-challenge.<label>.<base_domain>  CNAME  <uuid>.auth.acme-dns.io
```

For the `host` label, the CNAME is `_acme-challenge.<hostname>.<base_domain>`.
For the `*` label, the CNAME is `_acme-challenge.<base_domain>` for the
wildcard. The apex needs its own registered app site and certificate.
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
  special label `host` serves `*.<hostname>.base_domain`; the special label
  `*` serves only `*.base_domain` as a wildcard placeholder. Register the
  apex separately through an app route.
- **`wildcards`** — space-separated DNS labels matching
  `^[a-z0-9]([a-z0-9-]*[a-z0-9])?$`, plus the special labels `*` and `host`.
  Empty string = no zone snippets.
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

The step starts the container itself, so running it on a host whose 80/443
are already held (e.g. a legacy per-stack caddy) **fails loudly**: it
provisions and builds, names the listeners holding the ports, and exits
without starting. Stop the old service before re-running the step. For an
operator-managed parallel stack, ports can instead be remapped in
`~/infra/caddy/compose.override.yaml` (replacing the base ports needs the
`!override` tag), but the step's listener check still fails while 80/443 are
held. Start the remapped stack manually from `~/infra/caddy/`; rerun the step
only after the legacy listener has been removed:

```yaml
services:
  caddy:
    ports: !override
      - "127.0.0.1:8085:80"
      - "127.0.0.1:8443:443"
```

## Container lifecycle

- **Start**: the provisioning step starts the container itself
  (`docker compose up -d`), unless ports 80/443 are held by another service —
  then it fails without starting. When the container is already running,
  re-running the step applies updates in place (rebuild + recreate on change)
  and replays routes.d.
- **Stop**: `cd ~/infra/caddy && docker compose stop` — the next step re-run
  will bring it back up (stop it again if it should stay down).
- **Restart**: safe — Caddy resumes its autosaved configuration; `routes.d/` remains
  the source of truth and `caddy-route reconcile` can replay it if needed.
- **Rebuild/update**: re-run `./user/init.sh 60-caddy`. An image-input change
  rebuilds and clears autosave before recreating the container; a Compose-only
  change recreates without rebuilding; a Caddyfile-only change hot-reloads.
  A converged run does not recreate the container. All paths reconcile routes.d.
- **Runtime logs**: `docker compose logs -f caddy` (startup, TLS, certificate,
  and configuration diagnostics are written to Docker stdout).
- **Access logs**: site blocks must opt into Caddy's site-level `log` directive;
  when configured, write them to `~/infra/caddy/logs/access.log` (JSON,
  rotated 100MB×5). The global `log` block is not an access-log enablement
  switch.

Useful log commands:

```bash
docker logs caddy --tail 100
docker logs caddy --since 30m
docker logs -f caddy
tail -f ~/infra/caddy/logs/access.log

# Filter JSON access logs by hostname or error status.
jq 'select(.request.host == "myapp.example.com")' ~/infra/caddy/logs/access.log
jq 'select(.status >= 500)' ~/infra/caddy/logs/access.log
```

Runtime logs are always available through Docker. The access-log file exists
only when at least one site snippet enables `log`. Treat both log streams as
potentially sensitive: URLs, query strings, and headers may contain secrets, so
do not copy unreviewed logs into reports or issue trackers.

A conventional site-level access-log block is:

```caddyfile
myapp.example.com {
	log {
		output file /data/logs/access.log {
			roll_size 100mb
			roll_keep 5
		}
		format json
	}
	reverse_proxy myapp:3000
}
```

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

Set `versions.caddy` in the active bootstrap config to an exact version (or
`"latest"` to resolve the newest stable release on each run), then re-run the
user-tier step. If omitted, the version defaults to `"latest"`. The step
updates the builder, compiled binary, and runtime together; review plugin
compatibility before upgrading.

```bash
./user/init.sh 60-caddy
```

### Debug a snippet

```bash
# Validate a snippet without registering it:
docker exec -i caddy caddy adapt --config - --adapter caddyfile < myapp.caddy

# See the running config:
docker exec caddy curl --unix-socket /run/caddy-admin.sock http://localhost/config/ | jq .

# Check cert status:
docker exec caddy curl --unix-socket /run/caddy-admin.sock http://localhost/config/apps/tls/certificates | jq .
```

### Verify a route end to end

```bash
# Public DNS, TLS, and routing:
curl -v https://myapp.example.com/

# Test this host directly while preserving hostname, SNI, and TLS validation:
curl --resolve myapp.example.com:443:127.0.0.1 https://myapp.example.com/

# Preferred edge-network upstream, from Caddy's network namespace:
docker exec caddy curl -fsS http://myapp:3000/healthz

# Confirm the application is attached to the edge network:
docker inspect myapp --format '{{json .NetworkSettings.Networks}}' | jq .
```

For a host-published upstream, replace the backend check with
`docker exec caddy curl -fsS http://host.docker.internal:<port>/healthz`.
Use an application endpoint that exists when `/healthz` is not provided.

### Troubleshooting routes

| Symptom | Checks and likely cause |
|---|---|
| Route absent from disk | Run `caddy-route list`; confirm the expected file exists in `~/infra/caddy/routes.d/`; register it again if appropriate |
| Route on disk but not live | Run `caddy-route reconcile`, then `caddy-route list`; inspect runtime logs if reconcile fails |
| HTTP 404 | Confirm the request hostname exactly matches the site address; inspect the live config and test with `curl --resolve` |
| HTTP 502 | Test the upstream from inside Caddy; verify the container name, port, health, and `edge` network membership |
| Host upstream unreachable | Ensure the service binds to `0.0.0.0`, not only `127.0.0.1`; test `host.docker.internal:<port>` from Caddy |
| TLS or certificate failure | Verify A/AAAA/CNAME records, inspect `docker logs caddy --tail 100`, then inspect certificate configuration |
| Caddy unavailable | Run `docker inspect caddy --format '{{json .State}}' \| jq .`, then inspect runtime logs and port conflicts |

`caddy-route list` compares the disk registry with live server names, but an
empty live section can also mean that the Admin API was unreachable. Confirm
container health and query the live config directly before concluding that no
servers are loaded.

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

`user/init.d/60-caddy` checks the bouncer link on every provisioning run when
a key is configured, and fails the run if the link does not recover. This is
not continuous monitoring: an outage between runs will not be detected by
bootstrap. Use a separate scheduled health check or alert for that gap.
If key generation fails, provisioning stops without deleting an existing
`caddy-edge` registration; inspect the `cscli` error before manual recovery.

Diagnostics:
```bash
docker exec caddy caddy crowdsec health --address unix//run/caddy-admin.sock
docker exec caddy caddy crowdsec ping  --address unix//run/caddy-admin.sock
docker exec caddy caddy crowdsec check <ip> --address unix//run/caddy-admin.sock
cscli bouncers list          # is caddy-edge registered?
```

## Architecture

- **One Caddy container per host**, named `caddy`, on the `edge` docker network.
- **`edge` subnet is pinned** (`172.24.0.0/16`, gateway `172.24.0.1` — set at
  creation in 60-caddy step 4): snippets may reference the gateway IP.
  Requests originating on the host itself hairpin through docker-proxy and
  arrive with the gateway as source IP, so host-trusting gates (e.g.
  ci-dashboard's mesh gate) whitelist `172.24.0.1/32`.
- **Admin API: unix socket only** (`/run/caddy-admin.sock` inside the container),
  reached via `docker exec caddy curl --unix-socket …`. No TCP admin surface.
  Authorization = docker group membership (deploy user).
- **Ports**: 80 and 443 on `0.0.0.0` and `[::]`. No mesh or bridge IP binds —
  everything publishes on `0.0.0.0` and the firewall decides access.
- **Registry**: `~/infra/caddy/routes.d/<app>.caddy` is the source of truth on
  disk. Reconcile replays it into the running config.
- **Static assets**: `~/infra/edge/` on the host mounts to `/srv/edge` (ro) in
  the container — the conventional root for `file_server` snippets.

## Discovery — well-known file for project agents

The provisioning step (60-caddy) writes a machine-readable discovery file at
`~/infra/caddy/central.json`. Any project init agent can read this single file
to learn everything needed to register routes with the central Caddy:

```bash
# Discovery protocol for any project agent:
if [[ -f ~/infra/caddy/central.json ]]; then
  jq . ~/infra/caddy/central.json
fi
```

The file includes:

| Field | Content |
|---|---|
| `container.name` | `caddy` — Docker container name |
| `container.network` | `edge` — Docker network apps must join |
| `registration.cli` | Full path to `caddy-route` |
| `registration.commands` | Register/deregister/list/reconcile syntax |
| `snippet_contract` | What's allowed and forbidden in snippets |
| `backend_reachability` | Preferred (edge network) and fallback patterns |
| `static_assets.host_path` | `~/infra/edge/` — mount point for file_server snippets |
| `documentation.path` | Path to this guide |
| `status.running` | Whether the container is currently healthy |
| `base_domain` | Host zone apex from `caddy.base_domain` in bootstrap config |
| `wildcards` | Configured wildcard labels |
| `portal_mode` | Portal deployment mode (`dev` or `image`) from bootstrap config |
| `version` | Schema version (currently 2) |

The file is regenerated on every provisioning run — `status.running` flips to
`true` after the container reaches a healthy state. Its absence means central
Caddy is not provisioned on this host (or was torn down).

## Related files

- `user/init.d/60-caddy/run.sh` — the provisioning step (user tier)
- `user/init.d/60-caddy/stack/` — Dockerfile, compose, template, helpers
- `user/init.d/60-caddy/stack/wildcard.caddy.tmpl` — config-driven wildcard zone template
- `_plans/done/central-caddy.md` — historical specification and design rationale
- `init.d/53-fail2ban/run.sh` — reads `~/infra/caddy/logs/access.log`
- `init.d/54-crowdsec/run.sh` — LAPI + bouncer; grants the deploy
  user `crowdsec` group membership (enables `cscli` from the user tier)
