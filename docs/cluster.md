# Broadminde cluster host preparation

The separate `cluster` repository owns `bmcluster`, discovery, admission,
membership, and SSH key reconciliation. Bootstrap only prepares an opt-in host.
It does **not** run `init`, `join`, `leave`, `orphan-reset`, or roll out a live
cluster. The executable now has a bounded Unix operator socket and a restricted
SSH forced-command dispatcher, both locally tested but not verified on two
hosts. Do not activate the service or SSH peers until the task-6 two-host
verification and privilege review in the cluster foundation plan are complete
and approved by an operator.

## Installation boundary

`init.d/65-bmcluster` is a root-tier step gated solely by `cluster: true`.
It does not require `docker`, `dev`, a Go toolchain, or a deploy-user home.
The tracked example leaves `cluster: false`. A host opts in by editing its
gitignored `bootstrap.conf.yml` or `<hostname>.conf.yml`; never edit that file
from an agent session. Set an exact `versions.bmcluster` tag and the `cluster:`
fields in the example. No published signed release or verified publisher key
was available when this step was written, so these placeholders deliberately
fail closed. The operator must establish the Ed25519 release public key out of
band and provision a root-owned, non-group/world-writable PEM file; downloading
the key from the release URL would defeat signature verification.

The installer accepts only HTTPS release directories and one named binary for
the local architecture, `bmcluster_<version>_linux_amd64` or `_arm64`.
It verifies the detached Ed25519 signature of `SHA256SUMS`, requires one exact
checksum entry for that binary, and verifies its SHA-256 **before** changing
any host files. The URL, key path, version and private listener binding are
all explicit host configuration. A missing asset, key, signature, pinned tag,
interface or private IP aborts the step. There is no `latest` fallback.

After verification, the step creates the system account `bmcluster` with a
locked password, `/usr/sbin/nologin` shell, and only its private primary group;
an existing account with unexpected identity or extra groups is rejected.
It installs a root-owned executable at `/usr/local/bin/bmcluster`, owner-only
state **parent** at `/var/lib/bmcluster`, a root-owned
`/etc/bmcluster/daemon.env`, and systemd service/socket units. Neither unit is
enabled or started; both require `/etc/bmcluster/activated`. The socket unit
creates `/run/bmcluster.sock` with mode 0660 for a dedicated
`bmcluster-operators` group containing the deploy operator (not the locked
service account). The service receives that descriptor from systemd and checks
kernel peer credentials against the configured operator UID before accepting
bounded, whitelisted administrative requests. There is no TCP operator API.
The service runs only `serve-enrollment` if later activated.
The configured state directory `/var/lib/bmcluster/state` is deliberately
absent until an explicit `init` or `join` creates it. Its `sshcontrol/`
subdirectory is created only after an admitted host has a signed recovery
backup attestation and starts `serve-enrollment` again; the rerunnable
installer never initializes membership or creates SSH keys.
The operator group grants no access to private state and no new sudo or Docker
privilege. Direct `init`, offline `recover-admin`, `verify-backup` and destructive
reset remain separately supervised operator procedures, not rerunnable steps.
The step refuses active or enabled `bmcluster.service` and `bmcluster.socket` units so it cannot replace a live activation path.

The sshd configuration is a fail-closed `Match User bmcluster` installed as an
atomic managed block at the beginning of the base file and terminated by
`Match all`: public-key-only authentication, no interactive TTY, no forwarding,
and `ForceCommand /usr/bin/false`. Its leading position prevents an earlier
competing `Match` from weakening the policy, while `Match all` preserves later
global configuration. A complete candidate is validated with `sshd -t -f` and
effective `sshd -T -f` assertions for loopback and a representative cluster-peer
context before installation; rollback remains active through a successful
reload and daemon-health check. There are no cluster authorized keys provisioned
by bootstrap. The dispatcher and managed per-host keys exist in the cluster
executable, but the forced deny remains until task-6 live privilege checks.
No generic shell, sudo or host-execution endpoint is planned.

## SSH activation contract (not yet authorized)

The service account `bmcluster:bmcluster` owns `/var/lib/bmcluster` and the
private 0700 `/var/lib/bmcluster/state/sshcontrol` directory. The cluster
service creates 0600 `id_ed25519` (outbound SSH user identity),
`ssh_host_ed25519_key` (local server identity), `binding.json` (signed public
binding), `authorized_keys` (inbound peers), and `known_hosts` (outbound host
pins). It reconciles the last two files against verified membership on startup,
exchange, revocation and restart; a missing peer binding stays pending.
Neither bootstrap nor an operator should copy these files into the deploy
account's home or modify an operator's own SSH keys. The installer does not
create `sshcontrol/` and must never overwrite its contents on a rerun.

For authorized disposable task-6 tests, and only after a separate operator
decision for live rollout, the enablement order is: verify an independent
offline recovery-key backup; attest it with
`verify-backup` under supervised private-state access; restart the service so
it creates the SSH identity; exchange signed bindings over pinned member TLS;
inspect the managed files and separate SSH receipts; then review and configure
sshd. sshd must use the exact absolute `sshcontrol/authorized_keys` path for
`Match User bmcluster` and pass `CLUSTER_STATE_DIR=/var/lib/bmcluster/state` to
that account's forced command (for example, via a reviewed `SetEnv` in the
same Match block). `PermitUserEnvironment` remains disabled. Managed entries
already contain `command="/usr/local/bin/bmcluster ssh-control --peer=<host-ID>"`
with restrictive key options; the executable may use `CLUSTER_SSH_EXECUTABLE`
only if set to a reviewed absolute path. The dispatcher reads
`SSH_ORIGINAL_COMMAND` and permits only `bmcluster-control/v1 snapshot` and
`bmcluster-control/v1 acknowledge`; it is not an operator shell. The daemon
receives `CLUSTER_STATE_DIR`, interface/address and `CLUSTER_OPERATOR_UID` from
root-owned `/etc/bmcluster/daemon.env`; the deploy operator instead sets
`CLUSTER_OPERATOR_SOCKET=/run/bmcluster.sock` for routine CLI commands and
never needs private-state read permission. Supervised offline commands use
the private state directly, not the operator socket.

sshd must present the signed binding's `ssh_host_ed25519_key` before any
cluster peer can validate its managed `known_hosts` pin. `HostKey` is a global
sshd setting, not a `Match User` directive: installing it on a shared sshd
changes that server's offered host keys for other accounts too. The operator
must choose and verify an isolated listener or a reviewed shared-sshd host-key
configuration; bootstrap installs neither. Only after live tests verify the
server key, effective sshd policy, locked-account login behavior, inbound and
outbound peer restrictions, and revocation may the operator replace
`ForceCommand /usr/bin/false` with the per-key forced-command policy. Test
effective `sshd -T` settings and keep a rollback path before reload. Simply
removing the deny without an `AuthorizedKeysFile`, environment handoff and
host-key plan is not activation. No agent performs these privileged actions.

The UFW change is **deny-only** for the selected private IP/interface and
control port. The installer requires active UFW, removes only its own stale
endpoint denies, inserts the current deny ahead of broader allows, and verifies
its priority and the absence of stale managed rules. This step does not add an
allow for TLS or UDP 5353, enable the service, or create the activation marker.
An operator-reviewed rollout must still check Docker forwarding/iptables
behavior, actual interface binding and host-level ingress restrictions; a local
IP bind alone is not a guarantee that traffic arrived through the trusted
interface.

## Discovery and membership

DNS-SD is native Go (`grandcat/zeroconf`) on an explicitly selected trusted
interface. It is not controlled by Avahi's interface allowlist; this step makes
**no Avahi changes**. `cluster.discovery` must stay `off` before two-host tests.
The current pilot on a private bridge proved local publish/browse only. Its
NetBird `wt0` interface has no `MULTICAST` flag, so automatic overlay browsing
must not be assumed. Manual DNS-name/IP join is a separate, authenticated
admission path. Discovery metadata is untrusted and must never authorize peers.

Cluster creation is always explicit; silence never initializes a new cluster.
The default admission policy is approval; an out-of-band admin fingerprint
pins first contact. Private host keys and mutable membership stay in private
state; the distinct recovery key must be transferred and verified offline.
During partitions, local block/delete decisions cannot be reported as
cluster-wide revocation without peer acknowledgements. Unique per-host SSH
keys may eventually grant only a forced cluster-control operation. No primary
election, scheduler, host-wide Caddy migration, shared storage, or Docker
deployment belongs to this capability. Existing `~/infra/caddy` and other
live stacks remain untouched.

Before any operator activation, complete two-host DNS-SD and manual-admission
tests, restart/partition and SSH privilege-denial tests, verify recovery backup,
and review firewall exposure and the operator socket's live permissions. See the
cluster foundation plan's task 6 for the full verification matrix. No agent
executes privileged host rollout commands.
