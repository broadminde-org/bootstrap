# Bootstrap incident follow-up: firewall, Caddy, and NetBird

Captured 2026-10-22 UTC. This is an evidence inventory and investigation plan,
not a declaration that provisioning or security is healthy. The original outage
handoff is `/home/stack/netbird-caddy-outage.md`. Commands below are diagnostic;
do not rerun provisioning or reload the edge merely to gather evidence.

## Executive assessment

The root bootstrap **reported failure but continued executing later steps**.
Its saved summary lists `52-ufw` and `53-fail2ban` as failed. UFW is not installed
on this host, yet `54-crowdsec` installed CrowdSec and configured its local API
(LAPI) on `0.0.0.0:8080`. CrowdSec and its firewall bouncer were active; fail2ban
was failed. The absence of UFW does not prove public reachability of port 8080:
kernel/provider firewall rules were not verified. Treat ingress to 8080 as an
urgent unknown, not as an established safe condition.

Separately, the shared Caddy instance accepted an empty `/load` at 03:20:57,
which removed its HTTP servers. A zero-byte staged JSON file and empty-file
hash written at the same instant strongly implicate the route reconciliation
path, but the exact input or jq execution that emitted zero bytes has not been
recovered. A later duplicate apex route blocked replay. The edge was restored
from its saved config and reconciled after the route conflict was corrected.

The NetBird relay endpoint still reported 503 after Caddy recovery, but that
particular health result is consistent with a NetBird 0.81.3 combined-server
health-check mismatch. Public relay WebSocket upgrade returned 101. This does
**not** prove an authenticated peer session succeeds.

## Evidence and timeline

| UTC | Evidence | Interpretation |
| --- | --- | --- |
| Oct 21 ~23:20 | `/home/stack/bootstrap/fails.txt` lists `52-ufw` and `53-fail2ban`; `/var/log/apt/history.log` records Docker and fail2ban but no UFW installation. | Root provisioning did not finish successfully. The saved fragment contains no original step stderr, so the exact `52-ufw` failure is unknown. |
| Oct 21 ~23:21 | APT history records CrowdSec and firewall-bouncer installation; journal records CrowdSec starting at 23:21:20 and restarting at 23:21:36. | A security-dependent step ran after firewall provisioning failed. |
| Oct 22 00:08 | Fail2ban journal: `Have not found any log file for caddy-auth jail`; service failed after reboot. | The configured Caddy log prerequisite was absent. |
| Oct 22 03:20:57 | Caddy log: `POST /load`, `Content-Length: 0`, then `servers shutting down` and `load complete`. `/home/stack/infra/caddy/.last-pushed.sha256` was written ~2 ms later with SHA-256 of the empty file. | Caddy accepted a zero-byte configuration. The hash timing strongly points to `caddy-route`, but admin logs do not identify a caller. |
| Oct 22 03:25 | Deployed `netbird.caddy` was modified; it and the wildcard snippet both claimed `birb.gsit.ca`. Combined adaptation rejected `ambiguous site definition`. | A recovery blocker added after the empty load, not demonstrated as the original outage trigger. |
| Oct 22 ~04:31-04:38 | Caddy restored from its preexisting autosave and reconciled with corrected snippets. Caddy healthy; dashboard and `/api/instance` HTTP 200; public `/relay` WebSocket HTTP 101. | Basic public routing recovered; these checks are narrower than full NetBird peer functionality. |

The available saved bootstrap output is a failure *summary*, not a complete
transcript. APT and systemd times help reconstruct sequence but cannot supply
the lost stderr or tell us which operator command triggered Caddy reconcile.

## 1. Firewall prerequisite was not enforced

`bootstrap/init.sh:169-212,223-230` catches each failed step, records it, then
continues the loop; it exits nonzero only at the end. With `public: true` in
`bootstrap/bootstrap.conf.yml:1-7`, `54-crowdsec` remained eligible after
`52-ufw` failed. Capabilities gate whether a step is selected; they do not
express a successful-step dependency.

At incident time, `bootstrap/init.d/52-ufw/run.sh` required `MGMT_SSH_CIDR`
before reaching `apt-get install -y ufw`. A missing value is a plausible early
exit, **not the proven historical cause**. The complete error was not retained.
On this host `ufw` and `/etc/ufw/ufw.conf` were absent when inspected. A later
uncommitted change removed the CIDR requirement, stages an unrestricted TCP 22
SSH allow, and enables ufw after installation. The bootstrap README's initial
`.env` example had omitted the previously required value; the value is no
longer required.

The committed form of `bootstrap/init.d/54-crowdsec/run.sh` changed LAPI from
loopback to `0.0.0.0:8080`, then added a Docker-bridge UFW rule only *if* the
`ufw` command existed. It did not fail when UFW was absent. The current
uncommitted guard at `bootstrap/init.d/54-crowdsec/run.sh:147-150` now refuses
a run without active UFW; it does not undo the already-live wildcard bind.
`/etc/crowdsec/config.yaml` retains that binding, and a local socket check
showed `*:8080` listening. The active CrowdSec firewall bouncer is not an
inbound allowlist for LAPI.

**Priority P0:** verify actual ingress policy for TCP 8080 from outside the
host and from Docker bridges. Establish a verified deny for unwanted sources
without breaking the Caddy-to-LAPI path. Host firewall inspection and repair
require authorized root access; an unprivileged `nft list ruleset` was denied,
and provider-side firewall policy was not verified. Do not activate a default
deny firewall remotely until SSH management access and rollback are confirmed.

**Priority P1:** make the security steps dependency-aware or stop before a
dependent step after a prerequisite failure. Capture a complete provisioner
transcript (with secrets redacted), rerun only the needed UFW step after
checking SSH access and a rollback path, and verify its status and effective
rules. The
new CrowdSec guard is only one layer; the runner still continues past failed
steps.

## 2. Fail2ban does not start reliably on a fresh host

`bootstrap/init.d/53-fail2ban/run.sh:21-32` claims missing Caddy log files are
only a warning. But it writes enabled `caddy-auth` and `netbird-installer`
jails pointing at the resolved Caddy access log (`:73-102`), and the journal
records fail2ban refusing startup because the `caddy-auth` log did not exist.
Its configured ban action is `ufw` (`:73-85`), another failed prerequisite.
Fail2ban was failed at inspection time. The service is not providing its
intended jails merely because its package was installed.

**Priority P1:** decide whether these jails should be staged disabled until
the log exists, provision a valid log before enabling them, or reorder the
steps. Require a passing `fail2ban-client status` and expected jail statuses
after initialization and reboot. Do not claim a jail protects anything until
both its log source and ban action work.

## 3. Empty Caddy load: delivery path proven, production cause unknown

The pre-guard `caddy-route` merged adapted global and snippet JSON with jq,
then hashed, copied, and posted the result without testing that jq produced a
JSON document (`bootstrap/user/init.d/60-caddy/stack/bin/caddy-route:117-165`).
`jq` can exit zero without emitting a value, so `set -e` was not a sufficient
guard. The zero-byte `/tmp/merged.json` seen after the outage and the matching
empty-file hash support this route helper as the sender. They do **not** prove
the exact jq inputs, the triggering invocation, or that the user-tier
provisioner rather than another caller invoked it. The original host-side temp
directory was removed on process exit; the container temp file has since been
overwritten by a successful reconcile. Synthetic normal-policy inputs did
not reproduce empty output.

Caddy's old `--resume` autosave predated the outage and held a valid server
config. The empty load removed the Unix admin listener too, making the
configured healthcheck fail and normal socket-based reconciliation impossible
until a valid config was loaded through the fallback localhost admin endpoint.

The current uncommitted source and deployed helper reject missing/invalid
JSON or a missing Unix admin socket before posting, and compare live config
before hash-skipping. This prevents this particular zero-byte catastrophe
even though its initiating cause remains unexplained. The current files are
**not evidence of the script revision executing at 03:20:57**.

**Priority P1:** retain redacted reconcile diagnostics on failed adaptation or
merge: input file sizes and hashes, jq exit status and output size, invocation
source, and error output. Add a regression test for successful zero-output jq,
zero snippets, conflicting hosts, admin-socket preservation, and failed route
replacement. Never log credentials or full merged Caddy config. Investigate
the 03:20 caller using retained process/audit logs if available; do not assert
the exact cause from timestamps alone.

The bootstrap wildcard originally claimed the apex together with
`*.birb.gsit.ca`; NetBird then claimed the apex in its route template.
Bootstrap now renders only the wildcard placeholder, while NetBird owns the
apex. Validate the *combined* routes on future deployments, not just each
snippet individually. Registration previously removed an existing route on
failed replacement; the current uncommitted helper preserves and restores it.

## 4. NetBird readiness is an unreliable deployment signal

In NetBird 0.81.3 combined-server mode, startup reports `Relay WebSocket
multiplexed on management port (no separate relay listener)`. The upstream
[health-check code](https://github.com/netbirdio/netbird/blob/v0.81.3/relay/healthcheck/healthcheck.go)
marks an empty `ListenerProtocols()` list unhealthy; the upstream
[combined server](https://github.com/netbirdio/netbird/blob/v0.81.3/combined/cmd/root.go)
attaches `/relay` to the management HTTP server instead of opening a separate
relay listener. At inspection, port 9000 `/health` returned 503 with
`listeners:null, certificate_valid:true`, while public `/relay` accepted a
valid HTTP/1.1 WebSocket upgrade (101). Before Caddy recovery, the same check
logged refused connections to the public address and reported
`certificate_valid:false`; that earlier reachability problem was real.

`netbird-docker/init.d/60-bootstrap/run.sh:43-54` calls an HTTP 200 from
`/api/instance` "healthy" without checking relay operation. `80-verify/run.sh:6-16,41-42`
explicitly prints status rather than end-to-end readiness, and Compose does
not define a server healthcheck. A 101 proves the proxy reaches the handler,
not that an authenticated peer can use the relay. A 503 from this particular
health endpoint is also not sufficient evidence of a broken relay.

**Priority P2:** confirm the upstream combined-mode health semantics and
choose an appropriate probe or upstream fix. Test a real authenticated peer
connection and relay use before marking NetBird operational. Separate
dashboard, management API, WebSocket upgrade, and peer-session readiness in
deployment reporting.

## Additional deployment risks

- `bootstrap/user/init.d/60-caddy/run.sh:658-663` only warns if route listing
  fails; its discovery file can continue to advertise availability based on
  a running container (`:740-747`). Certificate files on disk (`:679-685`)
  do not prove a TLS listener is serving them. Require live HTTPS and
  config-health postconditions.
- `netbird-docker` previously defaulted `CF_PROXIED_HOSTS` to its apex even
  when DNS pointed directly at this server. That generated a 403 policy for
  direct clients. The current uncommitted helper defaults to a nonmatching
  sentinel and the deployed direct-origin route was updated. A real CDN
  deployment must explicitly identify its CDN-fronted names.
- The existing `bootstrap/docs/caddy-route-security-review.md:24-71` records
  broad snippet authority: registration can claim other hosts, serve mounted
  files, and has no audit trail. It is a deferred trust-boundary risk, not
  evidence of this outage. That review's historical rollback description
  should be revisited after the current helper change.

## Evidence still needed

1. The complete root bootstrap stdout/stderr for the failed `52-ufw` and
   `53-fail2ban` runs, or a safe isolated reproduction on a disposable host.
2. Effective host and provider firewall policy, plus an external TCP 8080
   reachability test. A listener alone does not answer the ingress question.
3. A retained trace of who called Caddy `/load` at 03:20:57 and the jq inputs
   from that invocation, if audit/process logs exist. Do not infer these from
   the subsequently overwritten temporary file.
4. An authenticated NetBird peer and relay test, plus a confirmed upstream
   disposition for the combined-mode 503 health response.

Read-only starting points for the next investigation:

```sh
systemctl status crowdsec crowdsec-firewall-bouncer fail2ban ufw
journalctl -u fail2ban --since '2026-10-21 23:00:00 UTC' --no-pager
ss -lnt '( sport = :8080 )'
docker logs caddy --since 2026-10-22T03:20:50Z --until 2026-10-22T03:21:05Z
```

An authorized operator must inspect the effective host/provider ingress
policy separately; these local commands cannot establish public reachability.

## Current change boundary

This document does not install or enable UFW, change provider firewall rules,
restart fail2ban, alter CrowdSec's live listener, or claim the relay is fully
healthy. Earlier repairs restored Caddy and changed source/deployed route
files; those edits are uncommitted. Reconcile this written assessment with
live state before using it for operations at a later date.
