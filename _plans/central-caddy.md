# Plan: Central Caddy — one edge reverse proxy per host, provisioned by bootstrap

Status: **ready for implementation** (Phase 1). Supersedes `~/ci/caddy-shared.md`
(see §8 for its review findings).

Revision notes (2026-08-01, post-review): stack installs to **`~/infra/caddy`**
(deploy-user owned, `ee/infra` convention) — not `/opt/caddy`; host-wide bind
doctrine is **0.0.0.0 + host firewall (`DOCKER-USER`)** — nothing binds mesh
or bridge IPs; capability semantics per `conf.sh` (absent = enabled →
opt-out via `caddy: false`); template rendering split documented in A.3
(`${VAR}` envsubst vs `{env.VAR}` Caddy runtime). Executor guardrails for
mid-tier agents: A.4 (zero-snippet reconcile, global-block rejection,
register rollback, hash location), A.6 (`.env.example` full text, run.sh
mechanics — getent home, runuser, cscli `-o raw`, envsubst single-pass,
autosave wipe, health wait).

**Revision 2 (2026-08-01, user-tier relocation):** the step moved from
`init.d/60-caddy` (root tier) to **`user/init.d/60-caddy`** — it runs as the
deploy user, not as root. The three original root requirements dissolved:
`/srv/edge` became **`~/infra/edge`** (compose mounts it `../edge:/srv/edge:ro`,
in-container path unchanged — snippets unaffected); `cscli` access comes from
root-tier **54-crowdsec adding the deploy user to the `crowdsec` group**;
the blanket **`dev` gate on the user tier was removed** (it gated non-dev
infrastructure for no reason) along with 40-profile's gate, so the step
runs on `dev: false` deployment hosts. `run.sh` no longer uses `SUDO_USER`/
`getent`/`runuser`/chown — everything is done directly as the deploy user.

**Self-containment note (for workspace moves):** this document is the complete
specification — every file an executor must create is either fully quoted in
Appendix A or precisely specified in §3. References to `~/netbird-docker`,
`~/ci`, and `~/ee` are *provenance and Phase-2 context only*; nothing needs to
be read from those paths to implement Phase 1. The executor does need the
`bootstrap` repo itself (init.d step format, `lib/common.sh`, `.requires` and
`bootstrap.conf.yml` capability mechanics — all documented in its README).

## Goal

Every dev/infra host runs **exactly one Caddy** (Docker), provisioned once by the
bootstrap root tier. App stacks and dev environments get TLS and routing by
**registering a Caddyfile snippet** with the host's central Caddy — either pushed
to its Admin API (dynamic, default) or `import`ed into any standalone Caddy
(escape hatch). Snippets are plain Caddyfile site blocks in both modes.

Non-goals (deferred, §7): multi-host shared cert storage (postgres/redis),
cross-host failover/load-balancing, Cloudflare DNS plugin.

---

## 1. Current state (surveyed 2026-08-01)

| Caddy today | Where | Form | Fate |
|---|---|---|---|
| `netbird-docker` (`~/netbird-docker`, prod at `/home/stack/netbird-docker` on broadminde1) | public edge for `birb.broadminde.org` | custom xcaddy build (`caddy/Dockerfile`), monolithic `Caddyfile.tmpl` rendered by `init.d/20-render`, DNS-01 via acme-dns CNAME delegation, CrowdSec bouncer, JSON log consumed by host fail2ban (53-fail2ban) | **Migrate** its site block into a central-caddy snippet (Phase 2) |
| `ee/infra` `artifacts` service | `:5001` file server | stock `caddy:2-alpine`, 8-line Caddyfile | Convert to snippet + `compose.override.yaml` (Phase 2, optional) |
| `ci` repo (`~/ci/caddy/ci.broadminde.org.caddy`) | webhook endpoint | already a clean drop-in snippet; docs say "import from the main Caddyfile" | First consumer of the **standalone** mode; switch to `register` in Phase 2 |

Key existing assets to reuse verbatim or near-verbatim:

- `netbird-docker/caddy/Dockerfile` — pinned xcaddy matrix (Caddy 2.11.4,
  xcaddy v0.4.5, `caddy-dns/acmedns@v0.7.0`,
  `hslatman/caddy-crowdsec-bouncer/http@v0.13.1`, `apk upgrade` CVE stage).
- `netbird-docker/init.d/46-acmedns` — acme-dns registration → `acmedns.json`
  → prints required `_acme-challenge` CNAMEs → cert-file probe with diagnostics.
- `netbird-docker` compose caddy service — port publishes (80/443 v4+v6),
  volume set, JSON log + roll settings (its `wget :2019` healthcheck becomes a
  socket-based check, §2.4).
- bootstrap conventions: init.d step format, `.requires`, `bootstrap.conf.yml`
  capabilities, root-tier `lib/common.sh`, `.env`-driven params, idempotent
  compare-before-write — and, from `ee/infra` (the convention the stacks
  themselves follow): deploy-user-owned `~/infra/<service>/` dirs with
  `.env`/`secrets/` (0600) beside the compose file, one init.d step per
  service. `ee/infra` is slated to break out into bootstrap deployment
  steps; central Caddy is the first service to follow that layout.

---

## 2. Architecture

```
                 ┌─────────────────────────── host ───────────────────────────┐
                 │                                                            │
   internet ────▶│  :80/:443   caddy container (caddy-custom, one per host)   │
                 │              ┌──────────────────────────────────────┐      │
   app init.sh ─▶│  caddy-route │  global config (Caddyfile, rendered) │      │
   (deploy user) │  register ──▶│  + apps from routes.d, combined &    │      │
   (docker grp)  │  docker exec │  pushed via POST /load (Admin API    │      │
                 │  unix socket │  over unix socket — no TCP listener) │      │
                 │     │        └──────────────────────────────────────┘      │
                 │     │                │ reverse_proxy                       │
                  │  routes.d/*.caddy    ▼                                     │
                  │  (source of truth)  app containers on external `edge` net  │
                  │                     or 0.0.0.0-published host ports via    │
                  │                     host.docker.internal (§2.6)            │
                 └────────────────────────────────────────────────────────────┘
```

### 2.1 Registration model — combined adapt + atomic `/load` (VERIFIED live, §9)

`routes.d/*.caddy` is the source of truth. Every change to it triggers a
**reconcile**: concatenate all snippets → `caddy adapt` the combined Caddyfile
(Caddy's own adapter consolidates all `:443` sites into one server and gives
each distinct listener its own server) → deep-merge the result over the
adapted global config (`jq -s '.[0] * .[1]'`) → `POST /load` the merged JSON.
`/load` is atomic: a config that fails validation leaves the running config
untouched.

- **register** `<app>` = validate snippet on its own → copy into `routes.d/` →
  reconcile. **deregister** = remove the file → reconcile. Both idempotent.
- Zero-downtime: `/load` swaps config live, no restart, no dropped connections.
- New `:443` hostnames trigger background cert issuance automatically; extra
  listeners (`http://:8082`, `:5001`) ride along as their own consolidated
  servers — no special casing.

**Rejected alternative (tested, §9):** one server per app via
`PUT /config/apps/http/servers/<app>`. Caddy **rejects** two servers claiming
the same listener (`listener address repeated: tcp/:443`) — its adapter
consolidates same-listener sites into a single server by design. Per-route
`@id` surgery inside the shared server would work but reimplements merging
logic the adapter already does; the combined-adapt model is simpler, uses
only Caddy-supported semantics, and keeps snippets as the single source of
truth.

### 2.2 Snippet contract (what app repos ship)

A snippet is a **Caddyfile fragment with site blocks only**:

- ✅ site blocks (`app.example.org { reverse_proxy … }`, `:5001 { … }`,
  `http://:8082 { … }`), matchers, `handle`, `tls { dns acmedns … }`, `log { … }`.
- ❌ no global block `({ ... })` — logging, ACME email, admin, CrowdSec app,
  storage are owned centrally.
- `{env.VAR}` placeholders survive `caddy adapt` and resolve **inside the
  central container** → shared secrets (e.g. `CROWDSEC_BOUNCER_KEY`) live in
  `~/infra/caddy/.env`. App-specific values (domains, upstreams) should be
  **rendered into the snippet by the app repo** (envsubst, the
  `netbird-docker/init.d/20-render` pattern) before registration, so snippets
  are concrete and portable.

Dual-mode by construction:

- **Dynamic**: `caddy-route register <app> path/to/<app>.caddy`
- **Standalone**: `import path/to/<app>.caddy` from any classic Caddyfile +
  reload (exactly what `ci` documents today). Hosts without the central stack
  keep working.

### 2.3 Source of truth and restart semantics

`~/infra/caddy/routes.d/<app>.caddy` is the persistent registry on disk:

- `register` copies the snippet into `routes.d/` *then* reconciles;
  `deregister` removes the file and reconciles. Reconcile is idempotent
  (hash-compare skips no-op `/load`s).
- Container runs `caddy run --config /etc/caddy/Caddyfile --resume`:
  unplanned restarts/reboots resume `autosave.json` (named volume) — apps come
  back with no orchestration.
- **The step never starts a stopped container.** Bringing the edge up is an
  explicit operator action (`cd ~/infra/caddy && docker compose up -d`), so
  an unattended user-tier run can never grab 80/443. When the container IS
  already running, the step applies updates in place: on config change it
  deletes `autosave.json` (via a transient port-less `compose run`), rebuilds,
  recreates, waits healthy, and `reconcile` replays `routes.d/` — avoiding
  the stale-autosave trap (`--resume` ignores `--config` whenever autosave
  exists). When it is NOT running, the step only provisions/builds/wipes and
  prints the start + `caddy-route reconcile` instructions.

### 2.4 Central container

- **Image**: `netbird-docker/caddy/Dockerfile` — the full text is embedded in
  Appendix A.1 (same pin matrix, verbatim). Plugins: acmedns
  (DNS-01 for wildcards/non-public names) + CrowdSec bouncer (public hosts).
- **Global Caddyfile** (rendered from `Caddyfile.tmpl` by the step): JSON
  access log at `/data/logs/access.log` (fail2ban-compatible, roll 100mb×5),
  `admin unix//run/caddy-admin.sock`, ACME `email` from `.env`, CrowdSec app +
  `order crowdsec first` **only when** `CROWDSEC_BOUNCER_KEY` is set
  (envsubst-gated template sections; fail-open per netbird's rationale).
- **compose.yaml** at `~/infra/caddy` (deploy-user owned):
  `container_name: caddy` (stable `docker exec`), ports `80/443` v4+v6 on
  `0.0.0.0` (**no admin port published — see below**), volumes: rendered
  Caddyfile ro, `acmedns.json` ro (when present), `logs/`, `caddy_data`,
  `caddy_config`, `../edge:/srv/edge:ro` (host dir `~/infra/edge` —
  static-asset convention for `file_server` snippets; created by the step),
  `extra_hosts: host.docker.internal:host-gateway`, joins external **`edge`**
  network (created by the step; app stacks opt in to be reachable by
  container name). `pull_policy: build` from netbird's service
  (`container_name: caddy` is new — netbird relies on compose project
  naming); healthcheck via the admin socket (below).
- **Admin API: unix socket only, reached via `docker exec`.**
  `admin unix//run/caddy-admin.sock`; all API access is
  `docker exec caddy curl --unix-socket /run/caddy-admin.sock …`
  (the caddy image ships a `curl` binary — verified). **No TCP admin listener
  exists at all** — nothing to publish, nothing for app containers or other
  hosts to attack. Authorization = host `docker` group membership (deploy
  user already has it via 50-docker; root-equivalent, same threat level as
  the docker socket itself).
  - Why not publish `127.0.0.1:2019`: inside a container, `admin
    127.0.0.1:2019` binds the *container's* loopback — published-port DNAT
    arrives on eth0 and is refused (verified). `admin :2019` would work but
    also exposes the API to every container on the docker networks.
  - Why not a host bind-mounted socket: Caddy **recreates** the socket on
    every config apply with `0600 root` — host-side access breaks on the
    first registration (verified).

### 2.5 TLS modes

| Case | Mechanism | Snippet needs |
|---|---|---|
| Public host, public name (`ci.broadminde.org`) | default ACME HTTP/TLS-ALPN | nothing — auto |
| Wildcard / non-public name (`*.host.broadminde.org`, `birb…`) | DNS-01 via acme-dns CNAME delegation | `tls { dns acmedns /etc/caddy/acmedns.json }` |

`acmedns.json` (0600, `~/infra/caddy/`) holds the flat single-account credential
blob. New helper `bin/acmedns-register` (flow fully specified in Appendix A.5):
one-time account registration against `auth.acme-dns.io`, prints required
CNAMEs per delegated name, probes cert issuance with the same diagnostics as
netbird's `46-acmedns`. One account covers unlimited delegated names.

### 2.6 Backend reachability (how snippets target apps)

Bind doctrine (host-wide, not just Caddy): services publish on **`0.0.0.0` —
never on a mesh or bridge IP**. A host runs several docker bridge networks
that must sometimes reach each other, and hosts plus their services reach
each other over the mesh; bind addresses are the wrong tool for either.
Reachability is controlled at the **host firewall**. For Docker-published
ports the enforcement point is the `DOCKER-USER` chain — Docker DNAT fires
before ufw's INPUT chain, so ufw rules never see published-port traffic
(52-ufw documents this for 80/443).

1. **Preferred — `edge` network**: app's compose adds
   `networks: { edge: { external: true, name: edge } }` to the services Caddy
   proxies → snippet uses container names (`reverse_proxy netbird-server:80`).
   This is also how two bridge networks inside one host exchange traffic:
   join the shared network instead of publishing ports at each other.
2. **Host-published ports**: app publishes `0.0.0.0:<port>` and the snippet
   targets `host.docker.internal:<port>` (mapped via `extra_hosts`). The
   host firewall decides who can actually reach `<port>` (LAN, mesh, no one).
   (`ci`'s snippet today proxies to `127.0.0.1:8000` inside the legacy
   Caddy — that breaks inside a container and becomes
   `host.docker.internal:8000` at registration, §4.1.)

---

## 3. Deliverable: `bootstrap/user/init.d/60-caddy/` (Phase 1)

```
user/init.d/60-caddy/
├── .requires                 # docker \n caddy
├── run.sh                    # user-tier step: install to ~/infra/caddy,
│                             #   render/build/up/reconcile (all as deploy user)
└── stack/
    ├── Dockerfile            # copy of netbird-docker/caddy/Dockerfile
    ├── compose.yaml          # central caddy service (§2.4)
    ├── Caddyfile.tmpl        # global block only (§2.4)
    ├── .env.example          # ACME_EMAIL, CROWDSEC_BOUNCER_KEY(optional),
    │                         #   ACMEDNS note, TZ
    └── bin/
        ├── caddy-route       # register|deregister|list|reconcile (§3.2)
        └── acmedns-register  # adapted 46-acmedns (§2.5)
```

Install layout on the host — **owned by the deploy user end to end**, under
`~/infra/` (the `ee/infra` convention; future infra stacks land as siblings
like `~/infra/artifacts/`). No root-owned stack state: the docker group is
already root-equivalent (§2.4), so root ownership buys no security and costs
sudo on every day-2 op. The step **runs as the deploy user** in the user
tier — no `SUDO_USER`, no `runuser`, no chown; its only privileges are
docker group membership (50-docker) and, when `public` is on, crowdsec
group membership (54-crowdsec):

```
~/infra/caddy/                     # i.e. /home/<deploy>/infra/caddy
├── compose.yaml  Dockerfile  Caddyfile   .env (0600)
├── bin/caddy-route  bin/acmedns-register
├── routes.d/<app>.caddy      # source of truth, deploy-user owned
├── logs/access.log           # fail2ban/crowdsec consume
├── acmedns.json (0600, when DNS-01 used)
└── compose.override.yaml     # per-host publishes/mounts (§6.3)
~/infra/edge/                  # static roots for file_server snippets
                               # (mounted ../edge:/srv/edge:ro — §2.4)
```

`~/.local/bin/caddy-route` → symlink to `~/infra/caddy/bin/caddy-route`
(stock Debian `.profile` puts `~/.local/bin` on PATH once the dir exists;
app init scripts call it as the deploy user — the same user owns the whole
stack, and needs only the `docker` group for `docker exec`/`docker cp`.
The Admin API is reached inside the container over its unix socket, so no
host network access is involved).

### 3.1 `run.sh` behavior (idempotent, user-tier style)

0. Runs as the deploy user (user tier refuses root). Everything lands
   deploy-user-owned by construction; docker/compose actions run directly
   (docker group from 50-docker; crowdsec group from 54-crowdsec when
   `public` is on). Preflight: `docker info` daemon access with a clear
   "log out and back in" error when the group isn't active yet.
1. Source `user/init.d/lib/common.sh`; preflight docker+compose, jq, curl, envsubst.
2. Seed `~/infra/caddy/.env` from `.env.example` if absent
   (0600) → instruct operator to fill `ACME_EMAIL`; when the `public`
   capability is on and the key is empty, generate `CROWDSEC_BOUNCER_KEY`
   via `cscli bouncers add` (group access from 54-crowdsec) directly into
   `.env` — no bootstrap-side secrets dir. Fail-open with a warning when
   cscli is missing or the group isn't active.
3. Create `~/infra/edge` if absent (mounted into the container at
   `/srv/edge`). Sync `stack/` → `~/infra/caddy` (compare-before-write;
   restart only when Dockerfile/compose/template changed).
4. Render `Caddyfile.tmpl` → `Caddyfile` (CrowdSec section gated on key).
5. `docker network create edge` if absent; `docker compose build` and clear
   `autosave.json` + push-hash when config/image changed (wipe uses a
   transient port-less `compose run` — the service is not started by it).
   Then, **only when the container was already running**: `up -d` (recreate
   on change), wait healthy, `caddy-route reconcile` **unconditionally** —
   the hash-skip makes it a no-op when converged, and it heals a previous
   run that wiped autosave but aborted before its own reconcile. When the
   container is stopped/absent the step **never starts it** (user decision
   2026-08-01, superseding the earlier auto-up and the brief refusal-guard
   designs): it prints a port-conflict warning if 80/443 are held
   (`ss -tlnH`), then the start + `caddy-route reconcile` instructions.
6. Post-condition checks (when running): `caddy adapt` validates rendered
   Caddyfile; healthcheck passes; `caddy-route list` works.

### 3.2 `caddy-route` (bash, ~120 lines)

```
caddy-route register <app> <file.caddy>   # validate → routes.d → reconcile
caddy-route deregister <app>              # rm routes.d/<app>.caddy → reconcile
caddy-route list                          # routes.d files vs live server hosts
caddy-route reconcile                     # combined adapt → merge → POST /load
```

- **validate**: adapt the new snippet alone first (`docker exec caddy caddy
  adapt`); reject global blocks and empty configs with actionable errors —
  a bad snippet never touches `routes.d`.
- **reconcile**: `cat routes.d/*.caddy` → adapt combined → `jq -s '.[0] *
  .[1]'` over the adapted global config → hash-compare against the last
  pushed config (skip no-op pushes) → `POST /load` via socket curl. Failure
  leaves the running config untouched and the error names the offending file.
- All container interaction is `docker exec`/`docker cp` (docker group) — the
  helper itself needs no other privilege; `jq` comes from 05-packages.

### 3.3 bootstrap repo touch-points

- `bootstrap.conf.yml` + `example.bootstrap.conf.yml`: add `caddy: true`
  capability (gated on `docker` via two-line `.requires`). Note the
  existing-host semantics: `conf.sh` treats a capability **absent** from the
  config as *enabled*, so the gitignored live `bootstrap.conf.yml` needs no
  edit to pick up the step — set `caddy: false` to opt out. (No config file
  at all = all capabilities disabled, as today.)
- **User-tier `dev` gate removal**: delete the blanket `.requires: dev` from
  all user-tier steps (it gated non-dev infrastructure for no reason) and
  from root-tier 40-profile (its PATH block supports user tooling and the
  `caddy-route` symlink on every host). `dev` now gates only
  06-playwright-deps. The user-tier runner's per-step `step_requires_caps`
  gating stays — 60-caddy uses it for `docker` + `caddy`.
- `init.d/54-crowdsec/run.sh`: add the deploy user to the **`crowdsec`
  group** (`local_api_credentials.yaml` is root:crowdsec 0640 → group
  membership grants `cscli` without sudo, used by user-tier 60-caddy);
  manage the Caddy acquisition source as a rewritten drop-in
  (`/etc/crowdsec/acquis.d/caddy-central.yaml`, stripping any previously
  appended acquis.yaml block) with a daemon restart when it changes —
  append-only accumulation and no-restart blindness were found in review.
- `init.d/53-fail2ban/run.sh`: make `CADDY_LOG` configurable via bootstrap
  `.env` (`CADDY_LOG_PATH`, default derived from the deploy user's home:
  `/home/<deploy>/infra/caddy/logs/access.log`); keep the legacy
  `/home/stack/netbird-docker/...` value working until netbird migrates.
  **Both steps resolve via the shared `init.d/lib/caddy-log.sh`** (env
  override → live file by mtime when both exist → central default) so
  fail2ban and crowdsec can never tail different logs, and 53 reloads
  fail2ban when jail.local changes on a running daemon.
- `README.md`: capability table row, layout tree, idempotency bullet,
  one-paragraph "central Caddy" section pointing at the new doc.
- New `docs/central-caddy.md` in bootstrap: snippet contract, register flows,
  backend networking, TLS modes, day-2 ops (upgrade pins, renewals, logs).

---

## 4. Phase 2 — consumer migrations (their own repos, after Phase 1 lands)

Conversion details (exact converted snippets, repo changes, cutover and
rollback per stack) live in `_plans/caddy-conversions.md` — surveyed from
the live configs on 2026-08-01.

1. **`ci` repo** (smallest, proves the primitive): `init.sh` calls
   `caddy-route register ci caddy/ci.broadminde.org.caddy` when
   `command -v caddy-route` exists; README/GETTING_STARTED swap "import from
   main Caddyfile" for register instructions, keeping the standalone import as
   documented fallback. Public ACME. One upstream fix at registration:
   `127.0.0.1:8000` → `host.docker.internal:8000` (§2.6 — woodpecker
   publishes on 0.0.0.0; no mesh-IP binds).
2. **`netbird-docker`** (the big one — do only when §2.4 CrowdSec gating is
   live, since `birb` is bouncer-protected today):
   - `Caddyfile.tmpl` → split: global parts drop (now central), site blocks →
     `caddy/netbird.caddy.tmpl` rendered by existing `20-render`.
   - compose: remove `caddy` service + its build target in `45-build`; join
     proxied services (`netbird-server`, `dashboard`, `netbird-installer`) to
     the external `edge` network.
    - move `caddy_data/acmedns.json` → `~/infra/caddy/acmedns.json`; `/deploy/*`
      assets → `~/infra/edge/netbird/` (served in-container at
      `/srv/edge/netbird/`); the `http://:8082` listener rides along as
      its own consolidated server (same snippet — adapt handles it).
   - new init.d step runs `caddy-route register netbird …`; `80-verify` probes
     unchanged (cert path root is the same `/data/caddy/...` in the central
     container).
   - update bootstrap `53-fail2ban` legacy path once the log moves.
3. **`ee/infra` artifacts** (optional): snippet `:5001 { root * /srv/edge/artifacts … }`,
   drop the standalone service; host's `compose.override.yaml` publishes 5001.

## 5. Phase 3 — dev-host wildcard pattern (design sketch, build when needed)

Per-app names on internal hosts need one `_acme-challenge` CNAME per app name
(manual DNS ops). Alternative for fleets of dev stacks on one host: a single
host-owned wildcard server `*.<host>.broadminde.org` (one acme-dns delegation)
with per-app `handle @host` routes — managed as ONE host-level snippet rather
than per-app servers. Decide when the first dev host onboards; per-app names
(§2.5) are the default until then.

## 6. Operational notes

1. **Firewall**: unchanged steps — 52-ufw deliberately stages no 80/443 rules
   (Docker DNAT bypasses ufw's INPUT; access control for 80/443 is Caddy's
   layer). Everything publishes on `0.0.0.0` (§2.6); restricting a published
   port to LAN/mesh/peers is done with rules in the **`DOCKER-USER` chain** —
   the one place host firewall rules actually see DNAT'd container traffic.
   No step interaction.
2. **Boot ordering**: binds `0.0.0.0` and nothing anywhere binds mesh IPs
   (§2.6) → no bind race, no systemd drop-in; `restart: unless-stopped`
   suffices.
3. **compose.override.yaml** is the per-host escape valve (extra publishes,
   extra mounts) — never rendered by the step; lives only in the live dir,
   which is not a git checkout.
4. **Upgrades**: pins live in `stack/Dockerfile`/compose with the netbird
   pin-matrix comment style; Renovate PRs bump them; re-running
   `./user/init.sh 60-caddy` rebuilds and reconciles.

## 7. Deferred (from caddy-shared.md — with trigger conditions)

- **Shared cert storage (postgres/redis plugin)**: only when >1 host serves
  the *same* names (coordination/rate-limits). Upgrade path is one `--with`
  line + global `storage` block; snippets unchanged.
- **Cross-host failover** (`reverse_proxy` `lb_policy first` + health checks to
  mesh IPs): arrives with the first shared global domain; works on top of the
  registration model as a normal snippet.
- **`caddy-dns/cloudflare`**: only if a zone can't CNAME-delegate to acme-dns.
- **Remote Admin API on the mesh** (register routes from other hosts):
  requires real access control (mTLS or a signer proxy); unix-socket-only
  until a concrete need exists.

## 8. Review findings on `caddy-shared.md` (fixed by this plan)

1. Two **contradictory drafts concatenated** (files+PostgreSQL vs API+Redis) —
   resolved: API-driven, local storage, files as the standalone fallback only.
2. `Dockerfile` `--with ://github.com` lines are **broken** (plugin paths
   stripped) — replaced by the proven netbird pin matrix.
3. Draft A compose: incoherent `dev-mesh`/`host-bridge-network`, missing
   `:80`, unclear backend addressing (`localhost:` from inside a container) —
   replaced by §2.4/§2.6.
4. Draft B admin JSON: `0.0.0.0:2019` with empty `public_keys` access-control
   is misleading/insecure as written — replaced with loopback-only admin.
5. Truncated final `curl -X DELETE "http://10.0.0"` — the doc is literally cut
   off; superseded.
6. `storage postgres … sslmode=disable` — SPOF + plaintext even on the mesh;
   deferred (§7).
7. Draft B's object-ID instinct was right about needing granular add/remove,
   but the mechanism changed after live testing: server-keyed PUTs are
   **rejected by Caddy** for same-listener servers, and `@id` route surgery
   reimplements adapter logic. The combined-adapt + `/load` model (§2.1)
   delivers the same granularity through file add/remove with simpler,
   fully-supported semantics.

## 9. Verification log (2026-08-01, caddy:2-alpine on this workstation)

Live-tested the load-bearing mechanics before committing them to the plan:

| Claim | Result |
|---|---|
| Multi-site snippet adapts to `srv0`, `srv1` (distinct listeners) | ✅ |
| `caddy run --resume`: prefers `autosave.json` over `--config`, no error when absent | ✅ (also restart-persistence test passed) |
| Server-per-app: `PUT …/servers/app2` with app1 already on `:443` | ❌ rejected — `listener address repeated: tcp/:443` → model replaced (§2.1) |
| `admin 127.0.0.1:2019` in-container + published port | ❌ refused (DNAT arrives on eth0, not container loopback) |
| Host bind-mounted admin socket | ❌ socket recreated `0600 root` on every config apply |
| `admin unix//run/caddy-admin.sock` + `docker exec caddy curl --unix-socket` (image ships curl 8.x) | ✅ no TCP admin surface; docker-group gated |
| Combined adapt → `jq -s '.[0] * .[1]'` merge → `POST /load` | ✅ 200; apps routable by SNI; extra listener server works |
| Deregister = rm file + re-`/load`; route gone, other app untouched | ✅ |
| `docker restart` → `--resume` restores registered apps from autosave | ✅ |
| Gotcha worth remembering: `GET /config/apps/http/servers` on a config with no servers returns `{"error":"invalid traversal path…"}` — `list` treats it as empty | noted for `caddy-route` |

### Phase 1 live verification (2026-08-01, this workstation, actual step)

Ran `./user/init.sh 60-caddy` end-to-end (temporary `!override` port remap to
127.0.0.1:8085/8443 — netbird's caddy holds 80/443 here; removed after):

| Check | Result |
|---|---|
| Step: seed .env 0600, create `~/infra/edge` + `edge` network, symlink, render, cache-hit build, up, healthy, post-checks | ✅ |
| Empty `ACME_EMAIL` first run | ✅ after render gate fix (bare `email` fails adapt — bug found + fixed) |
| Override discovery via live-dir compose invocation (`-f` suppresses it) | ✅ bug found + fixed |
| Register multi-site snippet (`tls internal` :443 + `http://` :80) → srv0/srv1, SNI + Host routing | ✅ |
| Hash-skip second reconcile | ✅ |
| Validate rejects global block (first-token `{`) | ✅ |
| Rollback on `/load` failure (missing cert files): file removed, prior state restored, verify app untouched | ✅ after `die`→`return` fix (rollback was unreachable — bug found + fixed) |
| `docker restart` → `--resume` restores registered apps | ✅ |
| Operator update (fill email, re-run step): wipe autosave + hash, rebuild, replay routes.d — apps back without autosave | ✅ |
| Idempotent re-run (no changes) | ✅ |
| Deregister LAST app → global-only push → route gone, stays gone after restart | ✅ after zero-snippet reconcile fix (skip-POST draft left it serving + resurrecting — bug found + fixed) |
| shellcheck / bash -n on all shipped + touched scripts | ✅ (only intentional SC2016 for envsubst's literal var list) |

Teardown: container removed; `~/infra/caddy` left installed (routes.d empty,
`.env` filled). On THIS host the stack stays down until Phase 2 frees 80/443
(netbird migration — `_plans/caddy-conversions.md`).

### Review-fix round (2026-08-01, post `/review` — 12 findings fixed and re-verified)

| Fix | Verification |
|---|---|
| Bouncer-key sed delimiter `s/…/…/` → `s|…|…|` (base64 `/` broke ~2/3 of keys; abort + duplicate-name cascade silently dropped CrowdSec) + stale-bouncer self-heal (delete+re-add) | ✅ sed unit-tested with `/`,`+`,`=` in key |
| `acmedns-register` printed full `/register` response incl. `password` | ✅ now `jq 'del(.password, .username)'` |
| Printed CNAME target `${subdomain}.${fulldomain}` duplicated the subdomain | ✅ prints `${fulldomain}` (matches A.5's `<subdomain>.auth.acme-dns.io`) |
| Site-level `crowdsec` directive unadaptable in validate/reconcile ("not an ordered HTTP handler" — verified) → synthetic `{ order crowdsec first }` wrapper (emits no JSON) | ✅ live: crowdsec snippet now passes validate; `/load` rejects on key-less host with the correct app error + clean rollback |
| Reconcile gated on same-run `changed` → post-wipe abort + re-run = false PASS with apps unserved | ✅ reconcile unconditional; idempotent re-run hash-skips |
| 53/54 both-logs-exist preferred central even when stale → shared `init.d/lib/caddy-log.sh`; fresher mtime wins when both exist | ✅ 7-case resolver matrix passes |
| 54 ignored and clobbered `CADDY_LOG_PATH` env override | ✅ resolver honors it; 54 resolves into `RESOLVED_CADDY_LOG` |
| 53 rewrote jail.local without reload; 54 appended acquis without restart and never removed stale sources | ✅ 53: `fail2ban-client reload` on changed jail.local when already running. 54: managed `acquis.d/caddy-central.yaml` drop-in (rewritten, never appended), legacy acquis.yaml block stripped (awk unit-tested), daemon restart on change |
| `docs/central-caddy.md` + conversions runbook used `docker compose -f` (suppresses override discovery) | ✅ all changed to live-dir/`--project-directory` invocation |
| `caddy: false` doesn't undeploy; no teardown docs | ✅ teardown section + README "provisioning, not runtime" note |
| `CADDY_VERSION` pinned in compose AND Dockerfile (compose arg won) | ✅ compose arg dropped; Dockerfile is the single pin (also fixed A.1/A.2) |
| `acmedns-register usage()` unreachable | ✅ wired: `[[ $# -eq 0 ]] || usage` |

### No-auto-start (2026-08-01, user decision — supersedes the refusal-guard draft)

The step originally ran `up -d` unconditionally, then gained a preflight
port guard that refused when 80/443 were held. User decision: **don't
automatically bring it up at all.** Final semantics: the step provisions,
builds, and does autosave hygiene, but never starts a stopped container;
when the container is already running it applies updates in place
(recreate on change) and replays routes.d. The port check survives as a
warning in the not-started branch. Verified live on this workstation
(netbird holds 80/443): step with container down → provisions, warns,
does not start (incumbent untouched); manual `up -d` on remap override →
healthy; re-run while running → no-op no-change path with hash-skip;
manual stop → step re-run → still does not start, prints instructions.

## 10. Implementation order (Phase 1)

1. `user/init.d/60-caddy/stack/` (Dockerfile, compose.yaml, Caddyfile.tmpl,
   .env.example) + `bin/caddy-route` + `bin/acmedns-register`
2. `run.sh` + `.requires`; `example.bootstrap.conf.yml` + live
   `bootstrap.conf.yml`; README updates
3. `53-fail2ban` log-path configurability; `54-crowdsec` crowdsec group +
   log-path derivation; user-tier `dev` gate removal
4. `docs/central-caddy.md`
5. Verify on a real host with the actual step: rendered Caddyfile adapts;
   register/deregister round-trip with a throwaway snippet; restart
   persistence (resume); reconcile-after-autosave-wipe (§9 mechanics already
   proven); `shellcheck`/`bash -n` everything
6. Phase 2 kickoff: `ci` repo registration (proves the primitive with a real
   cert on broadminde1 before netbird migrates)

---

## Appendix A — reference files (everything Phase 1 creates, standalone)

### A.1 `stack/Dockerfile` (verbatim copy of `netbird-docker/caddy/Dockerfile`)

This **is** the xcaddy build from `~/netbird-docker` — same multi-stage
pattern, same pin matrix. The pins live only here (ARG + the `xcaddy build`
line) — compose passes no build args (see A.2).

```dockerfile
# syntax=docker/dockerfile:1
# caddy-custom: stock caddy:2 runtime with plugins compiled in via xcaddy.
# Builds the same caddy:2 image that ships on Docker Hub, then compiles
# caddy from source in the :builder stage with xcaddy and the DNS/bouncer
# plugins. Final stage is a tiny runtime image with just the custom binary.
#
# To pin a Caddy version, set CADDY_VERSION at build time, e.g.:
#   docker build --build-arg CADDY_VERSION=2.8.4 -t caddy-custom:latest .

ARG CADDY_VERSION=2.11.4

# ---------------------------------------------------------------------------
# Stage 1: compile caddy with the plugins
# ---------------------------------------------------------------------------
FROM caddy:${CADDY_VERSION}-builder AS builder

# xcaddy is pre-installed in the :builder image. The 'go install' line
# pulls xcaddy's deps into the Go module cache, then `xcaddy build`
# compiles caddy from source with the named plugins linked in.
#
# Pinned matrix (verified 2026-07-25):
#   caddy:2.11.4-builder   — Go 1.24, base Alpine 3.21
#   caddy v2.11.4          — current stable
#   acmedns v0.7.0         — requires Caddy >= v2.10.0 and Go 1.24
#                           (its go.mod declares these explicitly)
#   caddy-crowdsec-bouncer v0.13.1 — its go.mod targets caddy v2.11.3 and
#                           declares Go 1.25.7; if the builder image's Go is
#                           older, the go toolchain auto-downloads 1.25.7
#                           during build (network is available in docker
#                           build). /http also blank-imports /appsec (inert
#                           unless appsec_url is set). /layer4 is
#                           intentionally omitted (needs mholt/caddy-l4).
#   xcaddy v0.4.5          — latest; matches caddy:2.11.4-builder
RUN go install github.com/caddyserver/xcaddy/cmd/xcaddy@v0.4.5 \
 && xcaddy build v2.11.4 \
    --with github.com/caddy-dns/acmedns@v0.7.0 \
    --with github.com/hslatman/caddy-crowdsec-bouncer/http@v0.13.1

# ---------------------------------------------------------------------------
# Stage 2: slim runtime
# ---------------------------------------------------------------------------
FROM caddy:${CADDY_VERSION}

# Upgrade Alpine packages to pick up patched curl (8.20.0-r0+) and
# c-ares (1.34.8-r0+). Fixes CVE-2026-5773, CVE-2026-6253, CVE-2026-6429,
# CVE-2026-7168, CVE-2026-5545, CVE-2026-6276, CVE-2026-4873,
# CVE-2026-7009, and CVE-2026-33630 (c-ares).
# golang.org/x/crypto GO-2026-5932 is in Caddy's go.mod; no upstream fix
# yet — accept until Caddy ships a patch release.
RUN apk upgrade --no-cache

# Replace the stock caddy binary with the one built in stage 1.
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
```

### A.2 `stack/compose.yaml` (reference — the executor finalizes comments)

```yaml
# Central Caddy — one edge reverse proxy per host.
# Runs from ~/infra/caddy (deploy-user owned; installed by bootstrap user/init.d/60-caddy).
name: caddy                    # pin project name → deterministic volume names
                               # (caddy_caddy_config) for the autosave wipe (§3.1)
services:
  caddy:
    build:
      context: .
      dockerfile: Dockerfile
      # Version pins live ONLY in the Dockerfile (ARG CADDY_VERSION + the
      # xcaddy build line) — do not re-pin here; single source of truth.
    image: caddy-custom:latest
    pull_policy: build
    container_name: caddy          # one per host by design; stable docker exec target
    restart: unless-stopped
    command: ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--resume"]
    ports:
      - "0.0.0.0:80:80"
      - "[::]:80:80"
      - "0.0.0.0:443:443"
      - "[::]:443:443"
      # NOTE: no Admin-API port. Admin is a unix socket reached via
      # `docker exec caddy curl --unix-socket /run/caddy-admin.sock …` (§2.4).
    environment:
      # Consumed by the rendered Caddyfile's {env.*} at runtime.
      CROWDSEC_BOUNCER_KEY: "${CROWDSEC_BOUNCER_KEY:-}"
      TZ: "${TZ:-UTC}"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./acmedns.json:/etc/caddy/acmedns.json:ro   # optional: only when DNS-01 is used
      - ./logs:/data/logs                            # fail2ban/crowdsec read access.log here
      - ../edge:/srv/edge:ro                         # convention: static roots for file_server snippets (~/infra/edge)
      - caddy_data:/data                             # certs, ACME accounts
      - caddy_config:/config                         # autosave.json (--resume source)
    extra_hosts:
      - "host.docker.internal:host-gateway"          # snippets may target host-published ports
    healthcheck:
      test: ["CMD", "curl", "-fsS", "--unix-socket", "/run/caddy-admin.sock", "http://localhost/config/"]
      interval: 10s
      timeout: 3s
      retries: 6
      start_period: 30s
    networks:
      - edge

volumes:
  caddy_data:
  caddy_config:

networks:
  edge:
    external: true                  # created by user/init.d/60-caddy if absent
    name: edge
```

(For a host that never uses DNS-01, the step ships an empty-object `{}`
placeholder as `acmedns.json` so the compose file never varies per host —
the provider only reads the file when a snippet actually uses
`dns acmedns`. Per-host extra publishes/mounts go in `compose.override.yaml`
in the live dir, §6.3.)

### A.3 `stack/Caddyfile.tmpl` (global block only — site blocks live in routes.d)

```caddyfile
# Central Caddy — global options only. App routes arrive via the Admin API
# (routes.d + caddy-route reconcile); this file must never gain site blocks.
{
	admin unix//run/caddy-admin.sock
	email ${ACME_EMAIL}

	# Structured access log for fail2ban (bootstrap 53-fail2ban) and any
	# future CrowdSec acquisition — JSON, self-rotating, bind-mounted to
	# ~/infra/caddy/logs on the host.
	log {
		output file /data/logs/access.log {
			roll_size 100mb
			roll_keep 5
		}
		format json
	}

	# trusted_proxies intentionally unset: no CDN fronts this host. Re-add
	# the CDN's edge ranges if one is ever placed in front.

	$CROWDSEC_SECTION
}
```

Two rendering mechanisms, kept strictly separate (netbird convention):

- **The step renders the template host-side**: first replace the
  `$CROWDSEC_SECTION` marker **line** with the gated block below (or with
  nothing when `CROWDSEC_BOUNCER_KEY` is unset), then run ONE envsubst pass
  with an explicit variable list — `envsubst '${ACME_EMAIL}
  ${CROWDSEC_API_URL}'` — producing the 0644 Caddyfile. Non-secret values
  only. envsubst is **single-pass**: it never re-scans substituted text,
  which is why the section is spliced into the template text BEFORE the
  pass instead of being passed as a variable. Never write `{$VAR}` in a
  template: envsubst mangles it to `{value}`, and Caddy's own `{$VAR}`
  placeholder would resolve empty (compose doesn't pass these).
- **`{env.VAR}` are Caddy runtime placeholders** resolved inside the
  container (compose's `environment:` block passes them): secrets only —
  `{env.CROWDSEC_BOUNCER_KEY}`. envsubst does not touch `{env.*}`.

Gated block spliced in place of the marker line when the key is set:

```caddyfile
	crowdsec {
		api_url ${CROWDSEC_API_URL}
		api_key {env.CROWDSEC_BOUNCER_KEY}
		ticker_interval 60s
	}
	order crowdsec first
```

(`CROWDSEC_API_URL` defaults to the host LAPI via
`http://host.docker.internal:8080` when the `public` capability is on;
`{env.*}` keeps the key out of the 0644 rendered file — same rationale as
netbird's template.)

### A.4 `caddy-route` — verified command pipeline (the heart of the helper)

All of this ran successfully on 2026-08-01 (§9). `$SOCK` calls are
`docker exec caddy curl -s --unix-socket /run/caddy-admin.sock …`.

```bash
# validate (register only): snippet must adapt alone — else reject
docker cp "$snippet" caddy:/tmp/check.caddy
docker exec caddy caddy adapt --config /tmp/check.caddy --adapter caddyfile >/dev/null

# reconcile: combined adapt → merge over global → push (skip when unchanged)
cat ~/infra/caddy/routes.d/*.caddy > "$tmp/combined.caddy"
docker cp "$tmp/combined.caddy" caddy:/tmp/combined.caddy
docker exec caddy caddy adapt --config /etc/caddy/Caddyfile --adapter caddyfile > "$tmp/global.json"
docker exec caddy caddy adapt --config /tmp/combined.caddy   --adapter caddyfile > "$tmp/apps.json"
jq -s '.[0] * .[1]' "$tmp/global.json" "$tmp/apps.json" > "$tmp/merged.json"
# skip POST when merged.json matches the last pushed hash
docker cp "$tmp/merged.json" caddy:/tmp/merged.json
docker exec caddy curl -s --unix-socket /run/caddy-admin.sock \
  -X POST "http://localhost/load" -H 'Content-Type: application/json' \
  -d @/tmp/merged.json -w '%{http_code}'          # expect 200
```

Notes: `GET /config/apps/http/servers` returns
`{"error":"invalid traversal path…"}` when no servers exist — `list` treats
that as empty. `/load` is atomic; on failure the running config is untouched
and caddy logs the reason (surface `docker logs caddy --tail 20`).

Implementation guardrails (these are the traps — do not improvise around them):

- **Skeleton**: `set -euo pipefail`; `STACK_DIR="${STACK_DIR:-$HOME/infra/caddy}"`;
  `tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT`. Runs as the deploy user;
  the helper's only privilege is docker-group membership.
- **Zero-snippet reconcile**: collect snippets with
  `shopt -s nullglob; files=("$STACK_DIR"/routes.d/*.caddy)`. When the array
  is empty, skip the **combined** adapt and merge — the merged config is the
  adapted global config alone — but STILL hash-compare and POST when changed:
  deregistering the last app must remove it from the running config and from
  autosave (verified live 2026-08-01: an early draft that skipped the POST
  left the last app serving forever and resurrected it on restart). Two
  classic bugs live here: `cat` on an unmatched glob reads stdin and hangs;
  `caddy adapt` on an empty file errors. (First install hits this path —
  routes.d starts empty; pushing the global-only config is a no-op swap of
  the config the container just started with.)
- **Validate must reject global blocks explicitly**: a bare `{` as the first
  non-comment token. `caddy adapt` ACCEPTS global blocks, so adapt alone
  does not enforce the snippet contract (§2.2).
- **Synthetic directive order for adapts**: site-level third-party handler
  directives (e.g. `crowdsec`) have no default order — adapting a
  global-block-free snippet containing one errors with "directive
  'crowdsec' is not an ordered HTTP handler" (verified live). `validate`
  and `reconcile` therefore prepend a synthetic `{ order crowdsec first }`
  to their adapt temp files. `order` emits no JSON, so merged configs and
  the no-op hash are unaffected.
- **Register rollback**: validate (solo adapt + global-block grep) happens
  BEFORE the copy, but a snippet that adapts alone can still fail combined
  (e.g. a site address already claimed by another snippet). If reconcile
  fails after the copy: remove the file just added, re-reconcile to restore
  the prior state, exit 1 naming the offending file. routes.d must never
  retain a config the running server rejected (§3.2 contract).
- **No-op skip hash**: store the last pushed merged.json's hash at
  `"$STACK_DIR/.last-pushed.sha256"` (stack ROOT — never inside routes.d,
  which must contain only `*.caddy`). Compare with `sha256sum`; skip the
  POST on match. run.sh deletes this file whenever it wipes autosave.json,
  forcing exactly one replay push.
- **POST result**: anything other than HTTP 200 → print the response body,
  then `docker logs caddy --tail 20`, and RETURN 1 (not `exit 1`) so
  register's rollback path runs. Capture body+code with
  `-w $'\n%{http_code}'` and shell splitting — never curl `-o` to a host
  tmpfile (the path is interpreted INSIDE the container).
- **Render gates**: an empty `ACME_EMAIL` must DROP the `email` line (a bare
  `email` fails adapt: "wrong argument count" — verified); an empty crowdsec
  section must drop the marker LINE, not substitute an empty string (a
  leftover blank line trips `caddy fmt` warnings on every adapt).
- **Compose invocation**: run compose from the live dir (`cd "$STACK_DIR" &&
  docker compose …`) — an explicit `-f` suppresses `compose.override.yaml`
  discovery, silently breaking the §6.3 escape valve (verified). Ports merge
  additively across files; replacing a published port needs `!override`/
  `!reset` in the override file.

### A.5 `acmedns-register` — essentials (from `netbird-docker/init.d/46-acmedns`)

One acme-dns account serves **unlimited** delegated names (each name just
gets a CNAME to the account's fulldomain), so registration is one-time per
host:

```bash
# 1. Register (idempotent — only when ~/infra/caddy/acmedns.json is absent):
curl -fsS -X POST https://auth.acme-dns.io/register \
  -H 'Content-Type: application/json' --data '{"register": {}}'
# → {"username","password","fulldomain","subdomain","allowfrom"}

# 2. MUST inject server_url (libdns/acmedns v0.5+ — else caddy fails with
#    "ServerURL cannot be empty"), then write 0600:
#    {…registration…, "server_url": "https://auth.acme-dns.io"}
#    (use jq — python3 is not guaranteed on bootstrap hosts; netbird's
#    46-acmedns uses python3, this helper must not):
#    jq -c '. + {server_url: "https://auth.acme-dns.io"}'

# 3. Per name, print + poll for the delegation CNAME:
#    _acme-challenge.<name>  CNAME  <subdomain>.auth.acme-dns.io
#    (dig +short CNAME _acme-challenge.<name> | grep auth\.acme-dns\.io)

# 4. Verify issuance by probing the cert file inside the container:
#    /data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/<name>/<name>.crt
```

Caveats from production: `caddy reload`/Admin-API changes do **not** re-read
`acmedns.json` (provider reads it at init) — restart the container after
replacing the file. Plugin errors land in `/data/logs/access.log`, not stdout.

### A.6 `stack/.env.example` (full text) and `run.sh` implementation guardrails

```bash
# Central Caddy environment — copied to ~/infra/caddy/.env (0600) by
# user/init.d/60-caddy on first run. Fill ACME_EMAIL before `up`.
ACME_EMAIL=

# Optional — CrowdSec bouncer. user/init.d/60-caddy generates and fills this
# via `cscli bouncers add` when the `public` capability is enabled (requires
# crowdsec group membership from root-tier 54-crowdsec). Leave empty
# to run without CrowdSec (the Caddyfile crowdsec section is gated on it).
CROWDSEC_BOUNCER_KEY=
CROWDSEC_API_URL=http://host.docker.internal:8080

TZ=UTC

# DNS-01 (wildcard / non-public names): run bin/acmedns-register once to
# create acmedns.json, add the printed _acme-challenge CNAMEs to DNS, then
# snippets may use `tls { dns acmedns /etc/caddy/acmedns.json }`.
```

`run.sh` mechanics (§3.1 behavior, these exact techniques — user-tier,
runs as the deploy user):

- **No privilege dance**: no `SUDO_USER`, no `getent`, no `runuser`, no
  chown — the step runs as the deploy user, so `$HOME` is correct and
  every file it writes is deploy-user-owned by construction. Preflight
  `docker info` for daemon access; error names the docker group and
  re-login when unreachable.
- **Sync (compare-before-write)**: per stack file, `cmp -s src dst` → skip;
  else `install -m <mode>` and set `changed=1`. `.env` is NOT synced — it is
  seeded once from `.env.example` (step 2) and never overwritten.
- **Bouncer key**: only when `cap_enabled public` and `.env` has an empty
  `CROWDSEC_BOUNCER_KEY`: `key="$(cscli bouncers add caddy-edge -o raw)"`,
  then `sed -i "s|^CROWDSEC_BOUNCER_KEY=.*|CROWDSEC_BOUNCER_KEY=$key|"` on
  `.env` (stays 0600). The delimiter must NOT be `/` — cscli keys are
  base64 (`A-Za-z0-9+/=`), so a `/`-delimited s/// breaks on most keys;
  with `set -e` that aborts mid-step and every re-run then fails on the
  bouncer's unique-name constraint → silently provisions without CrowdSec
  (found in review). If the add fails on a duplicate name, delete the
  stale bouncer and regenerate (self-healing). `cscli` works without sudo
  via the `crowdsec` group (root-tier 54-crowdsec). `cscli` missing or
  group not yet active → warn, leave empty (fail-open, same as the
  template gate; re-running the step fills it later).
- **Render**: splice the CrowdSec block into the template text, then
  `envsubst '${ACME_EMAIL} ${CROWDSEC_API_URL}'` (explicit list, single
  pass — see A.3 for why).
- **Autosave wipe** (only when image/config changed, before `up`):
  `docker compose run --rm --no-deps --entrypoint rm caddy -f /config/autosave.json`
  (reuses the just-built image; no extra pull). Also delete
  `~/infra/caddy/.last-pushed.sha256` so the reconcile below pushes once
  (A.4). Volume name is deterministic via compose `name: caddy` (A.2).
- **Wait healthy**: poll `docker inspect -f '{{.State.Health.Status}}' caddy`
  up to 60s; on timeout `docker logs caddy --tail 30` and exit 1.
- **Post-checks**: `docker exec caddy caddy adapt --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null`,
  `caddy-route reconcile`, `caddy-route list` output matches routes.d files.
