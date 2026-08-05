# Plan: CrowdSec ↔ central-Caddy link fixes (LAPI reachability + health assertion)

Status: **implemented 2026-08-04**. Two blocking gaps found 2026-08-04 while
reviewing central-caddy readiness for the netbird migration
(`~/netbird-docker/_plans/caddy-conversions.md` §4, "CrowdSec gating live"
prerequisite). Both fixes land in this repo; neither touches netbird-docker.

## Background

The netbird edge (`birb.broadminde.org`) is bouncer-protected today by an
in-stack CrowdSec container whose LAPI the caddy bouncer reaches at
`http://crowdsec:8080` (docker-network DNS — works by construction). The
central design moves the LAPI to the host (root-tier `54-crowdsec`) and points
the central caddy container at it via `CROWDSEC_API_URL=http://host.docker.internal:8080`
(user-tier `60-caddy`, gated on the `public` capability).

Two gaps break that link as currently provisioned, and the bouncer plugin is
deliberately **fail-open** (`enable_hard_fails` off — a CrowdSec outage must
never take the edge down), so the failure mode is *silent*: central caddy
comes up healthy, serves traffic, and enforces **zero** CrowdSec decisions.
Nothing in the current steps would tell the operator.

### Gap 1 — host LAPI is unreachable from the central container

- The Debian crowdsec package defaults `api.server.listen_uri` to
  `127.0.0.1:8080` in `/etc/crowdsec/config.yaml`. `54-crowdsec` never changes
  it (`listen_uri` appears nowhere in this repo).
- `host.docker.internal` maps to the docker **host-gateway** address (a bridge
  gateway IP, e.g. `172.18.0.1`) — not loopback. Container packets arrive at
  `172.x.0.1:8080`; a loopback-bound LAPI refuses them.
- Even with `listen_uri` fixed, ufw blocks the path: `52-ufw` stages
  `default deny incoming` with only SSH-from-management and LLMNR-deny rules.
  Container→host packets on bridge interfaces traverse the INPUT chain, where
  that policy applies. (Docker's DNAT bypass of ufw — the reason 52-ufw
  forbids rules for published ports — applies to FORWARDed traffic *to*
  containers, not to host-bound traffic *from* containers.)

### Gap 2 — nothing asserts the bouncer link end-to-end

The netbird stack's `init.d/48-crowdsec` catches exactly Gap 1's failure mode:
it polls `caddy crowdsec health` from inside the caddy container for 60s. The
bootstrap chain has no equivalent — `54-crowdsec` asserts `cscli version` +
`systemctl is-active`; `60-caddy`'s post-checks are `caddy adapt` +
`caddy-route list`. None prove decisions stream LAPI → caddy.

## Fix 1 — `init.d/54-crowdsec/run.sh`: LAPI reachability

Two new sub-steps between Step 2 (package install) and Step 3 (collections),
plus a one-line change to the Step 5 restart condition and one new
post-condition assertion. Style notes: match the step's existing conventions
(echo headers, idempotent compare-before-write, restart only on change to a
running daemon).

### 1a. New Step 2b — manage `listen_uri`

```bash
# ---------------------------------------------------------------------------
# Step 2b: Make the LAPI reachable from docker containers.
#
# The central Caddy container's bouncer streams decisions from the host LAPI
# at http://host.docker.internal:8080 (user/init.d/60-caddy). host-gateway
# resolves to a bridge gateway address (e.g. 172.x.0.1), NOT loopback — and
# the Debian default `listen_uri: 127.0.0.1:8080` refuses those connections.
# Bind 0.0.0.0 and let ufw (step 2c) scope exposure to the docker bridges.
# The host's firewall bouncer keeps using loopback — unaffected.
# ---------------------------------------------------------------------------

CONFIG_YAML=/etc/crowdsec/config.yaml
lapi_changed=0

if grep -qE '^[[:space:]]*listen_uri:[[:space:]]*0\.0\.0\.0:8080' "$CONFIG_YAML"; then
  echo "LAPI listen_uri already 0.0.0.0:8080 — skipping"
elif grep -qE '^[[:space:]]*listen_uri:[[:space:]]*127\.0\.0\.1:8080' "$CONFIG_YAML"; then
  sed -i.crowdsec-bak \
    's|^([[:space:]]*)listen_uri:[[:space:]]*127\.0\.0\.1:8080|\1listen_uri: 0.0.0.0:8080  # managed by bootstrap/init.d/54-crowdsec — docker-bridge reachable, exposure scoped by ufw|' \
    "$CONFIG_YAML"
  echo "listen_uri: 127.0.0.1:8080 → 0.0.0.0:8080 (backup: ${CONFIG_YAML}.crowdsec-bak)"
  lapi_changed=1
else
  echo "WARNING: listen_uri is neither 127.0.0.1:8080 nor 0.0.0.0:8080 — leaving untouched:" >&2
  grep -E '^[[:space:]]*listen_uri:' "$CONFIG_YAML" >&2
fi
```

Rationale for `sed` over `yq`: preserves the file's comments and ordering;
`yq` is not installed by 05-packages. The inline `# managed by` comment is
valid YAML and marks the line as owned. Correction (2026-08-04): the `sed` uses
`-E` (extended regex) — the bare-paren `(...)` form in this spec block is GNU
sed BRE which rejects `\1` backreferences and would abort under `set -e`.
Implementation uses `sed -E`. A non-default, non-target value is
warned about and left alone (never clobber operator intent).

### 1b. New Step 2c — ufw allow rule for docker bridges

```bash
# ---------------------------------------------------------------------------
# Step 2c: Allow docker bridge traffic to the LAPI (ufw).
#
# Container → host LAPI packets traverse the INPUT chain, where ufw's
# default-deny applies. Allow only the RFC1918 docker bridge range; external
# exposure stays denied by policy. `ufw allow` stages the rule whether or not
# ufw is active yet (52-ufw enables it manually in Phase 1c), so ordering
# against ufw activation does not matter. IPv6: the `edge` network is
# v4-only today — add a matching fd00::/8 rule if that ever changes.
# ---------------------------------------------------------------------------

if command -v ufw >/dev/null 2>&1; then
  if ! ufw show added 2>/dev/null | grep -q 'CrowdSec LAPI'; then
    ufw allow from 172.16.0.0/12 to any port 8080 proto tcp comment 'CrowdSec LAPI from docker bridges'
    echo "ufw: allowed 172.16.0.0/12 → 8080/tcp (docker bridges)"
  else
    echo "ufw: LAPI rule already present — skipping"
  fi
fi
```

Placement rationale: the rule belongs to the service that needs it, not to
52-ufw — 52-ufw is base hardening that runs before crowdsec exists, and its
"no rules for ports 80/443/3478" doctrine is about Docker-*published* ports
(DNAT bypass), a different category from this host-bound rule.
`ufw show added` reads `/etc/ufw/user.rules` regardless of active state, so
the idempotency check works pre- and post-activation.

### 1c. Step 5 restart condition — include `lapi_changed`

CrowdSec does not reload `config.yaml` on its own; a `listen_uri` change on a
running daemon is inert until restart. Change the existing restart gate:

```bash
if [[ "$((acquis_changed + lapi_changed))" -gt 0 && "$cs_was_active" -eq 1 ]]; then
  echo "CrowdSec config changed — restarting crowdsec"
  systemctl restart crowdsec
fi
```

(Declare `lapi_changed=0` alongside the existing `acquis_changed=0` /
`cs_was_active` sampling near the top of Step 4 so the arithmetic is always
defined.)

### 1d. New post-condition assertion (Step 7)

```bash
# LAPI listens on all interfaces (docker-bridge reachable).
if ss -tlnH 'sport = :8080' | grep -q '0\.0\.0\.0:8080'; then
  echo "  PASS: LAPI listening on 0.0.0.0:8080"
else
  echo "  FAIL: LAPI not listening on 0.0.0.0:8080 — central caddy cannot reach it" >&2
  exit 1
fi
```

## Fix 2 — `user/init.d/60-caddy/run.sh`: bouncer-link health assertion

Add to the Step 9 post-condition block (inside the existing
`was_running -eq 1` section, after the `caddy adapt` PASS check).
`CROWDSEC_BOUNCER_KEY` is already in scope (read from `.env` in Step 7).
`--address` is mandatory here: the central container's admin API is the unix
socket `/run/caddy-admin.sock`, not the default TCP 2019 — this is why
netbird's bare `caddy crowdsec health` cannot be copied verbatim. Verified
against the shipped image: `caddy crowdsec health` accepts the global
`--address` flag (`caddy crowdsec ping` and `caddy crowdsec check <ip>` too).

```bash
  # CrowdSec bouncer link — when a key is configured, prove decisions
  # actually stream from the host LAPI into caddy. The bouncer plugin is
  # fail-open (enable_hard_fails off), so a broken link is SILENT: caddy
  # keeps serving with zero protection. This assertion is the only thing
  # that catches it. The stream bouncer connects on its own retry loop —
  # allow a few ticker intervals (ticker_interval 60s) before failing.
  if [[ -n "$CROWDSEC_BOUNCER_KEY" ]]; then
    cs_healthy=0
    for _i in $(seq 1 12); do
      if docker exec caddy caddy crowdsec health --address unix//run/caddy-admin.sock >/dev/null 2>&1; then
        cs_healthy=1
        break
      fi
      sleep 5
    done
    if [[ "$cs_healthy" -eq 1 ]]; then
      echo "  PASS: CrowdSec bouncer link healthy (decisions streaming from host LAPI)"
    else
      echo "  FAIL: 'caddy crowdsec health' did not pass within 60s" >&2
      echo "        The edge is running UNPROTECTED — the bouncer fails open." >&2
      echo "        Diagnose:" >&2
      echo "          docker exec caddy caddy crowdsec ping --address unix//run/caddy-admin.sock" >&2
      echo "          cscli bouncers list                 (is caddy-edge registered?)" >&2
      echo "          grep listen_uri /etc/crowdsec/config.yaml   (0.0.0.0:8080? — root-tier 54-crowdsec)" >&2
      echo "          ufw status | grep 8080            (docker bridges allowed? — 54-crowdsec)" >&2
      exit 1
    fi
  fi
```

Hard-fail rationale: a populated `CROWDSEC_BOUNCER_KEY` means the operator
opted into protection; failing the step does not stop caddy (it is already
running — the step never starts/stops it), it only refuses to report success
for a silently-unprotected edge. When the key is empty (non-`public` hosts)
the check is skipped entirely, matching the rendered-Caddyfile gate.

## Verification (live, broadminde1)

After `sudo ./init.sh 54-crowdsec` and `./user/init.sh 60-caddy`, with the
central container up (the loopback-remap smoke-test override from
`caddy-conversions.md` §4.4 step 1 is sufficient — 80/443 not required):

```bash
# Host side
grep listen_uri /etc/crowdsec/config.yaml        # 0.0.0.0:8080, managed comment
ss -tln | grep 8080                              # 0.0.0.0:8080
ufw show added | grep 8080                       # 172.16.0.0/12 rule
cscli bouncers list                              # caddy-edge registered
cscli lapi status

# Container side
docker exec caddy caddy crowdsec ping   --address unix//run/caddy-admin.sock
docker exec caddy caddy crowdsec health --address unix//run/caddy-admin.sock

# Decision flow, end-to-end (TEST-NET-3 documentation IP — safe)
cscli decisions add --ip 203.0.113.7 --duration 5m --reason "link test"
docker exec caddy caddy crowdsec check 203.0.113.7 --address unix//run/caddy-admin.sock   # expect: banned
cscli decisions delete --ip 203.0.113.7
```

Idempotency: re-run both steps — expect all "skipping / already" lines, no
restart, no ufw duplication.

## Rollback

- `listen_uri`: `cp /etc/crowdsec/config.yaml.crowdsec-bak /etc/crowdsec/config.yaml && systemctl restart crowdsec`
  (or sed the value back to `127.0.0.1:8080`). The central bouncer loses its
  LAPI and fails open — the edge keeps serving, unprotected.
- ufw: `ufw delete allow from 172.16.0.0/12 to any port 8080 proto tcp`
- 60-caddy assertion: revert the Step 9 edit; the step is re-synced from this
  repo on every run, so no live-state cleanup is needed.

## Operational notes for this host (broadminde1)

- `bootstrap.conf.yml` currently has `public: false` — flip it before running
  54-crowdsec, or the step is capability-skipped and 60-caddy leaves the
  bouncer key empty.
- `init.d/lib/caddy-log.sh` defaults `LEGACY_CADDY_LOG` to
  `/home/stack/netbird-docker/...`, but this host's live stack runs from
  `/home/luke/netbird-docker`. Pre-cutover, the acquis drop-in will therefore
  resolve to the (not yet existing) central log — harmless (CrowdSec warns,
  does not fail; the in-stack crowdsec keeps protecting the edge meanwhile).
  To have the host engine tail the *live* netbird log during the migration
  window, run: `sudo CADDY_LOG_PATH=/home/luke/netbird-docker/logs/caddy/access.log ./init.sh 54-crowdsec`.
  Consider fixing the lib default in a separate change.
- The iptables firewall bouncer hooks INPUT and does **not** see DNAT'd
  traffic to published container ports (80/443 traverse FORWARD) — expected.
  The caddy plugin bouncer remains the edge enforcement layer; the firewall
  bouncer covers host services (sshd et al.). The layers are complementary;
  do not treat one as a substitute for the other.

## After landing — cross-references to update

- `codemap.md` — the `54-crowdsec` row is already stale (says "appends Caddy
  log path to `/etc/crowdsec/acquis.yaml`"; the step has used the managed
  `acquis.d/caddy-central.yaml` drop-in since the 2026-08-01 review round).
  Update for the drop-in *and* the new listen_uri/ufw behavior.
- `docs/central-caddy.md` (operator's guide) — document the LAPI listen
  address + ufw expectation and the `caddy crowdsec health --address …`
  diagnostic in the CrowdSec section.
- `_plans/central-caddy.md` — append to the review-fix log (these two gaps
  are exactly the class of finding that log tracks).
- `~/netbird-docker/_plans/caddy-conversions.md` — §4 prerequisites: the
  "CrowdSec gating live" gate becomes satisfiable; add the health-check
  command as the gate's verification. (Separate repo, separate commit.)
