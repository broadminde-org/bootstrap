# Bootstrap audit: remaining defects and recovery priorities

Audited 2026-10-22 against `main` at `34e9499` plus the uncommitted working
tree. Scope: root and user runners, security provisioning, central Caddy,
operator instructions, and read-only host state. **No provisioning step or
route mutation was run for this audit.** This is a current-state review, not
proof that an older committed revision behaved identically. The incident
timeline and uncertainty around the 03:20 Caddy load are recorded separately
in [docs/2026-10-22-bootstrap-incident-follow-up.md](docs/2026-10-22-bootstrap-incident-follow-up.md).

## Decision summary

1. **P0: determine whether CrowdSec LAPI on TCP 8080 is reachable from an
   unintended network and close that path.** Local observation establishes a
   wildcard listener and no active UFW, not external reachability.
2. **P1: make security prerequisites fatal to dependent steps.** The root
   runner continued after UFW failed and installed CrowdSec anyway. The user
   runner has the same continue-on-failure pattern.
3. **P1: make fail2ban start on a fresh host and verify its ban backend.** Its
   Caddy-log jails currently prevent startup; fail2ban remains failed.
4. **P1: make route mutations transactional and require actual live readiness.**
   Replacement registration now rolls back; deregistration does not.
5. **P1: test on a disposable host before treating source edits as host
   recovery.** UFW is still not installed here. The current `52-ufw` source
   no longer needs `MGMT_SSH_CIDR`, but it has not been run on this host.

## Live snapshot and evidence limits

At inspection, `dpkg-query` reported UFW not installed; `systemctl is-active`
reported `ufw` inactive, `fail2ban` failed, and both CrowdSec and its firewall
bouncer active. `ss` showed `*:8080` listening. Caddy was running healthy and
its CrowdSec health check passed. These observations are **not** a test of
provider firewall rules, kernel packet filtering, real external access, or a
NetBird peer session. This session does not have passwordless sudo, so it did
not install UFW, inspect privileged firewall rules, or restart security
services. An authorized operator should verify the actual public ingress
policy before assuming LAPI is protected.

The checkout was already dirty. Relevant uncommitted edits include
`init.d/52-ufw/run.sh`, `init.d/54-crowdsec/run.sh`, and
`user/init.d/60-caddy/{run.sh,stack/bin/caddy-route,stack/wildcard.caddy.tmpl}`.
The previous incident document and `fails.txt` are untracked. This report
does not stage, discard, or alter those changes.

## Confirmed findings

### P0: the existing host does not have the intended LAPI ingress control

`init.d/54-crowdsec/run.sh:155-162` binds CrowdSec LAPI to
`0.0.0.0:8080`. Its new guard at `:147-150` requires active UFW on a **future
run** but cannot change the existing listener or install UFW retroactively.
The allow rule at `:180-189` grants any source in `172.16.0.0/12`, not traffic
specifically arriving from a Docker bridge. Another routed network in that
range could match. The live listener and missing UFW establish exposure on
the host interfaces; reachability from the internet remains **unverified**.

Next: use authorized root access to inspect effective nftables/iptables and
the provider firewall; test TCP 8080 from outside and from the Caddy bridge.
Constrain LAPI to the actual necessary path without breaking Caddy's bouncer.
Do not mistake an active CrowdSec firewall bouncer for an inbound LAPI rule.

### P1: root provisioning continues across failed security prerequisites

`init.sh:191-212` records a failed step and continues; it exits nonzero only
at `:223-230`. The saved `fails.txt:4-6` lists `52-ufw` and `53-fail2ban`,
while APT history confirms CrowdSec was installed afterward. The root
`public` capability selects step 54 independently of step 52's success.
`user/init.sh:197-229` likewise continues after failed user-tier steps.
This behavior is deliberate in the runners, but security-dependent steps
must not proceed on an assumed postcondition that never occurred.

Next: decide fail-fast versus explicit per-step dependencies; at minimum gate
CrowdSec's wildcard bind and fail2ban's `ufw` ban action on a verified active
firewall. Test failure propagation in both runners. The uncommitted guard in
step 54 is useful but not a replacement for runner-level dependency handling.

### P1: fail2ban is installed but fails to start on this host

`init.d/53-fail2ban/run.sh:87-102` enables `caddy-auth` and
`netbird-installer` jails against a Caddy access-log path during root
provisioning. Its comment at `:21-32` says a missing log does not hard-fail,
but the service journal reported `Have not found any log file for caddy-auth
jail` after reboot. `:73-85` selects `banaction = ufw`, while `:173-177` only
warns when an installed UFW is inactive and says nothing when UFW is absent.
Fail2ban is currently failed, so none of these jails should be credited as
protection.

Next: enable log-dependent jails only when their log source exists and is
parseable; require an active ban backend; assert daemon and jail status after
initialization and after reboot. Rerunning this step is not currently safe to
regard as a verified repair.

### P1: deregister can lose an existing Caddy route on failure

`user/init.d/60-caddy/stack/bin/caddy-route:223-235` removes the route file
**before** reconcile, with no rollback. If adaptation, Docker access, or
`/load` fails, disk has already lost the snippet, even if the old route
continues serving temporarily. A later successful replay then removes it
from the edge. By contrast, replacement registration now saves and restores
the old snippet at `:198-214`.

Next: give deregistration the same restore-on-failure semantics and test both
the disk and live config after a rejected load. Avoid using deregistration as
an assumed atomic recovery operation until that is done.

### P1: Caddy provisioning can miss changed credentials and environment

`user/init.d/60-caddy/run.sh:150-187,256-260` marks a newly generated
bouncer key as a Compose change, but later edits to its `.env` or
`acmedns.json` need not set the change flags. The unchanged-stack branch at
`:583-608` reconciles routes without recreating the container. Thus an
apparently successful rerun can leave old container environment or DNS-01
provider credentials loaded. This is a **code-path risk**; no stale live
credential was demonstrated on this host.

Next: fingerprint the relevant inputs, trigger a safe recreate/reload when
they change, and verify the loaded credential path without printing secrets.

### P1: wildcard readiness does not establish HTTPS readiness

`user/init.d/60-caddy/run.sh:679-685,708-723` regards the presence of a
certificate **directory** as issuance success. It does not verify certificate
files, expiry, names, or the certificate actually served by port 443. The
03:20 outage demonstrated why on-disk certificates and an Up container are
insufficient. `run.sh:658-663` only warns if route listing fails, while
`stack/bin/caddy-route:244-271` suppresses admin errors and can print
`(no servers loaded)` with a successful exit. The discovery writer at
`run.sh:445-469,740-747` records `available: true` and a container-running
flag rather than observed HTTPS readiness.

Next: make live admin-server state and representative HTTPS routes hard
postconditions, and distinguish `installed`, `running`, and `ready` in
discovery. Keep certificate storage checks as supporting evidence only.

### P2: fail2ban filter-only edits are not reloaded

`init.d/53-fail2ban/run.sh:113-161` writes both filter files, but
`:179-186` reloads an already-running daemon only when `jail.local` changes.
A corrected filter with an unchanged jail file remains inactive. Compare or
fingerprint all loaded inputs, then check the daemon's effective jails.

### P2: privilege and identity assumptions need an explicit policy

`init.d/30-passwordless-sudo/commands.txt:14-21` allows wildcard
`systemctl start *` and `systemctl enable *`. `systemctl enable` accepts an
absolute path to a unit file, so the claimed verb-scoped restriction does
not by itself prevent arbitrary root service execution. However,
`init.d/50-docker/run.sh:112-119` already grants the deploy user Docker-group
access, which is root-equivalent: this is a misleading boundary, not an
additional independent privilege escalation on the current design.
Docker and CrowdSec group assignment use raw `SUDO_USER` (`50-docker/run.sh:116-119`,
`54-crowdsec/run.sh:285-288`) while other steps resolve `BOOTSTRAP_USER`
via `init.d/lib/user.sh:19-20`. An override can grant the wrong account.

Next: explicitly decide whether the deploy user is trusted as root; if not,
remove Docker-group access and broad sudo grants as one design change. Use
the shared deploy-user resolver consistently.

### P2: bootstrap's fresh-host and recovery instructions contradict code

`README.md:71-100` clones as root without choosing a deploy-user-accessible
directory, then tells the new user to `cd bootstrap`. If cloned under
`/root`, the handoff cannot work. `example.bootstrap.conf.yml:90-99` and
`docs/central-caddy.md:128-131` still claim wildcard `*` renders the apex;
current `user/init.d/60-caddy/run.sh:368-373` reserves only the wildcard.
`README.md:492` says rerunning Caddy never starts a stopped container, but
`run.sh:565-580` starts one. `docs/central-caddy.md:191-193` implies every
rerun wipes autosave/restarts, whereas `run.sh:546-557` only does that when
image inputs change. These are actionable recovery hazards, not just stale
wording.

Next: make the quick start specify an accessible checkout location and
correct the wildcard ownership and container-lifecycle runbooks.

## Open questions and testing boundary

- The exact historical reason `52-ufw` failed is not in the saved output.
  The old SSH-CIDR check could exit before APT, but that invocation's stderr
  was not retained. The current uncommitted step installs UFW first, stages
  unrestricted TCP 22 SSH access, and enables UFW; **it has not been run here**.
- The exact jq input or caller that generated the zero-byte Caddy `/load`
  remains unknown. The current `caddy-route` guard rejects empty/malformed
  merged JSON, but a disposable test of that failure and rollback paths is
  still needed. See the incident follow-up for the timestamped evidence.
- `user/init.d/60-caddy/stack/bin/caddy-route:50-75` checks adaptation but
  does not enforce hostname ownership or safe file roots. This is a
  full-trust snippet boundary, detailed in
  [docs/caddy-route-security-review.md](docs/caddy-route-security-review.md).
- No dedicated automated root/user provisioning failure-regression suite was
  identified. `AGENTS.md:190-197` calls for disposable-VM verification; the
  existing Bats tests target shared user scripts, not these host transitions.
  Do not run firewall or destructive route tests against the production edge.

### Deferred KVM provisioning risks (2026-10-22 review)

The optional `kvm` capability is disabled in the example config. Defer these
changes until KVM provisioning can be exercised on a disposable VM host:

- `init.d/57-kvm/run.sh:62-65` recursively changes ownership of all existing
  `/opt/kvm` contents on each run. VM disks or service-owned data may become
  inaccessible to QEMU; constrain ownership changes to newly created paths.
- `init.d/57-kvm/run.sh:213-224` generates a synchronous libvirt QEMU hook
  that calls `virsh dumpxml` back into libvirt. VM startup may hang while the
  daemon waits for its hook; use the hook-provided domain XML instead.
- `init.d/57-kvm/run.sh:53-55,226-230` grants the deploy user `kvm` and
  `libvirt` membership, but the hook grants PTY access to `libvirt-qemu`.
  Serial-console access may fail unless that group membership is resolved.

These are code-path risks, not reproduced host incidents. Do not rerun the KVM
step on a host with VM data merely to confirm them.

### Deferred user-tier follow-ups (2026-10-22 review)

- **Caddy acme-dns credential lifecycle:** `user/init.d/60-caddy/run.sh`
  registers credentials when wildcards are configured and `acmedns.json` is a
  placeholder, but does not guarantee recreation of an already-running Caddy
  container. The credential file is bind-mounted individually and registration
  replaces it atomically; config reload or container restart may retain the old
  mount. Manual changes to `acmedns.json` and container `.env` likewise do not
  set the step's change flags (see the P1 credential finding above). Credential
  changes are expected to be rare, and a wider Caddy-management redesign is
  under consideration, so defer automated detection/recreation. For now,
  explicitly **recreate** the container after replacing credentials; do not
  assume a reload or restart suffices. No stale live credential was confirmed.
- **Playwright capability gating:** `user/init.d/35-node/packages.txt` includes
  `@playwright/test`, and the ungated `35-node/run.sh` installs Chromium,
  Firefox, and WebKit even with `dev: false`. The root-tier
  `init.d/06-playwright-deps` OS dependencies are `dev`-gated. Defer splitting
  Playwright into a separate `dev`-gated user step until the user-step layout
  is revisited; non-dev hosts currently install browsers without guaranteed
  system dependencies.
- **CrowdSec monitoring between bootstrap runs:** `user/init.d/60-caddy/run.sh`
  now checks the configured bouncer link on every provisioning run, and failed
  key generation no longer deletes an existing registration. Bootstrap is not
  a continuous monitor: the fail-open bouncer can lose its LAPI connection
  between runs without an alert. Defer a scheduled check/alert to the host
  monitoring design; do not treat successful provisioning as ongoing protection.

### Deferred Docker decisions (2026-10-22 review)

Step 50 now detects a daemon configuration newer than the running process. The
following separate issues are deferred pending an explicit access-policy and
registry decision; disabling `docker` only gates provisioning, not runtime
state (discuss that capability behavior separately):

- `init.d/50-docker/run.sh:45-52,130-158` passes an `http://` URL into
  `insecure-registries`, whereas Docker documents `host:port` entries. Normalize
  the registry address and test the HTTP case before relying on it.
- `init.d/50-docker/run.sh:121-123,157-158` preserves app-added Docker TCP
  listeners, including the documented unauthenticated `:2375` example. A
  reachable Docker API is root-equivalent; decide whether to forbid, constrain,
  or explicitly validate these listeners.
- `init.d/50-docker/run.sh:114-119` grants the deploy user the root-equivalent
  `docker` group. Central Caddy currently depends on it. Revisit together with
  the broad sudo grants rather than removing group access in isolation.

## Recommended order in the bootstrap workspace

1. Verify live LAPI reachability and host/provider firewall policy with
   authorized access; recover UFW and fail2ban with a tested SSH path.
2. Make step dependencies and postconditions explicit; add a disposable-host
   regression for a failed UFW install and a missing Caddy log.
3. Add transactional deregistration and live Caddy readiness assertions;
   test failed `/load` and config drift off-host.
4. Resolve the documented privilege model and correct the fresh-host and
   recovery runbooks before the next deployment.
