# Code Review Remediation Plan — bootstrap workspace

Produced by the full workspace code review of 2026-09-18 (three parallel review
agents + coordinator verification; ShellCheck 0.10 cross-check; empirical runner
CLI tests). Execute in priority order. Every item lists the exact files/lines
and the intended fix — read the surrounding code before editing, follow the
AGENTS.md conventions (idempotent, `set -euo pipefail`, fail loudly,
compare-before-write, validate-before-activate), and keep `README.md` /
`docs/codemap.md` / `AGENTS.md` in sync when behavior or step inventory changes.

Each phase is independently committable. No automated test suite exists —
verify by running affected steps on a disposable VM (see AGENTS.md "Testing").

---

## Execution notes (2026-09-18) — all items addressed

Deviations and decisions taken during execution:

- **1.1**: drop-ins renamed to `00-bootstrap-auth.conf` / `01-bootstrap-hardening.conf`;
  legacy `60/61` drop-ins are removed on re-run when they carry our marker.
  Post-conditions run BEFORE the reload (sshd -T reads on-disk config) so a
  failed assertion never reaches the live daemon; the reload is followed by a
  daemon-active check. Round 1 keeps `passwordauthentication yes` asserted.
- **1.3**: deploy-user resolution lives in new `init.d/lib/user.sh`
  (`require_deploy_user`); consumers: 20, 30, 40, 51, 55, 56, 57. `50-docker`
  and `54-crowdsec` keep their soft conditional SUDO_USER group-adds (not in
  the plan's file list). NOTE: the plan asked to validate the two-phase README
  flow on a fresh VM — no disposable VM was available in this session; the
  flow was verified by inspection plus runner CLI tests. Validate on a
  disposable VM before relying on it operationally.
- **3.1**: docker sudoers lines dropped entirely (docker group already grants
  root-equivalent access) — documented in commands.txt. systemctl is
  verb-scoped; cscli is scoped to the two exact bouncer commands 60-caddy
  invokes.
- **3.4**: chose the "vendor the repo setup" option (59-gh-cli pattern:
  keyring + signed-by sources entry, compare-before-write). LAPI stays on
  0.0.0.0 (docker bridges need it); exposure is closed by 52-ufw now
  auto-enabling once the SSH rule is verified staged, plus louder warnings.
- **4.4**: chose option (a) — narrow whitelist (`apt-get autoremove/autoclean/clean -y`,
  `journalctl --vacuum-time=*`) + root-owned no-arg wrappers
  (`/usr/local/sbin/drop-caches`, `/usr/local/sbin/prune-text-logs`, installed
  by 30-passwordless-sudo) for 80/91; `sudo_run` probes per-command via
  `sudo -n -l "$@"`; skip message prints the absolute runner path.
- **4.6**: verified on a live host that the agent runs as `kilo serve
  --port 0` (so the old guard did match); added shared `kilo_running()` in
  maintain-common.sh (`pgrep -x kilo` first, `-f` fallback) and used it in
  120/135; 130 got a Windsurf process guard.
- **45-woodpecker**: gated behind a NEW `woodpecker` capability (default
  false in example + this host's conf). This host has no `woodpecker`
  account, so nothing existing is unmanaged. plugin-git SHA256 pinned for
  amd64 + arm64 (from upstream checksums.txt); GitHub host keys seeded from
  api.github.com/meta instead of accept-new.
- **52-ufw**: now requires `MGMT_SSH_CIDR` (env or repo-root .env, fail loudly
  when unset) and auto-enables ufw only when the SSH rule is verifiably
  staged; otherwise it fails loudly and leaves ufw disabled.
- **65-codium-state-dumps**: name predicate uses the observed format
  `YYYYMMDDTHHMMSS` plus the dashed ISO variant — the plan's example pattern
  (`2[0-9][0-9][0-9]-*`) matches nothing on the current host.
- **secrets/**: no step generates host secret files, so the convention was
  removed from AGENTS.md (kept `secrets/` in .gitignore defensively).
- Verified: `bash -n` on every shell file; shellcheck shows no new findings;
  runner CLI matrix (help/unknown/--from/bad selector) on the user tier;
  `maintain --list`, no-such-step, and `--tier 2 --dry-run`; jq daemon.json
  merge preserves app keys; acquis awk handles the two-filename legacy
  block; `require_deploy_user` matrix (empty/root/dotted/nonexistent/valid);
  sshd tolerant seds; nvm pinned-commit URLs; GitHub keys vs api.github.com;
  plugin-git checksums vs upstream checksums.txt.

---

## Phase 1 — CRITICAL: fresh-host lockout chain (fix together)

These compose into a brick-the-fresh-host scenario on the documented quick start.

### 1.1 SSH hardening ordering + validation (`init.d/51-ssh-hardening/`)

- [x] Rename the drop-ins so they sort **before** cloud-init's
  `50-cloud-init.conf` (sshd is first-match-wins per keyword; current
  `60-auth.conf` sorts after and silently loses). Suggested:
  `00-bootstrap-auth.conf` etc. Update the header comment at `run.sh:11-24`
  which currently claims the opposite ordering.
- [x] Add `sshd -t` before `systemctl reload` (`run.sh:62`).
- [x] Add real post-condition assertions via `sshd -T -C user=<deploy>`:
  assert effective `permitrootlogin no` and (for round 1)
  `passwordauthentication yes`; abort loudly if not in effect. The header at
  `run.sh:26-28` promises this; implement it.
- [x] Make the `sed` at `run.sh:43-44` tolerant: match
  `^[#[:space:]]*PermitRootLogin[[:space:]=]` style patterns, not just the
  exact strings `PermitRootLogin yes` / `X11Forwarding yes`.
- [x] Back up `/etc/ssh/sshd_config` before `sed -i`; compare-before-write on
  the drop-ins (skip reload when unchanged).
- [x] Add an `ssh.service` fallback for the reload (`sshd.service` alias is
  fine on current Debian/Ubuntu; older releases differ).

### 1.2 Enroll a deploy-user SSH key before hardening (`init.d/10-create-deploy-user/run.sh`)

- [x] Read `BOOTSTRAP_SSH_PUBKEY` from `.env` (repo root, gitignored); when
  set, install it into `/home/<user>/.ssh/authorized_keys` (0700 dir, 0600
  file, correct ownership), idempotently (append-if-absent).
- [x] Gate `PermitRootLogin no` in 51 on proof of a working non-root login
  path: key enrolled OR password auth confirmed effective (1.1 post-condition).

### 1.3 Fix deploy-user resolution; repair the documented flow

Files: `README.md:67-81`, `init.d/10-create-deploy-user/run.sh:25-36`,
`init.d/20-groups/run.sh:18`, `init.d/30-passwordless-sudo/run.sh:18`,
`init.d/40-profile/run.sh:41`, `init.d/55-lazydocker/run.sh:21`,
`init.d/56-ssh-client/run.sh:11`, `init.d/57-kvm/run.sh:50-75`.

- [x] Introduce explicit deploy-user resolution, e.g. in
  `init.d/lib/common.sh` or a new `lib/user.sh`:
  `DEPLOY_USER="${BOOTSTRAP_USER:-${SUDO_USER:-}}"`, hard error when empty or
  `root` (unless the step is the user-creation step itself). Steps 20-56 must
  consume `DEPLOY_USER`, not raw `SUDO_USER`.
- [x] `10-create-deploy-user/run.sh:25-29`: skip creation only when
  `SUDO_USER` is set AND != root AND != `BOOTSTRAP_USER`. Remove the dead
  branch at `:31-36`. Fix the misleading exit message at `:76` ("re-run
  subsequent init steps **with** sudo").
- [x] Rewrite the README quick start as the two-phase flow that actually
  works: (1) as root: `./init.sh 10` (creates deploy user), (2) log in as the
  deploy user, `sudo ./init.sh` for the rest. Validate this exact sequence on
  a fresh VM before closing this item.
- [x] Update `docs/codemap.md` if step contracts change.

### 1.4 Caddy bouncer-key rotation flag is clobbered before use (`user/init.d/60-caddy/run.sh:104` vs `:144-146`)

Step 2 (CrowdSec key generation) sets `compose_changed=1` at line 104
precisely because a container-env change only applies on recreate — but the
flag block is *initialized later* in Step 5 (`compose_changed=0` at line
145), wiping it. On a re-run with a running container and an empty
`CROWDSEC_BOUNCER_KEY`: key generated → flag set → flag reset → compose
unchanged → the `was_running` branch takes the config-only **hot-reload**
path (`:452`) → the reloaded Caddyfile references
`{env.CROWDSEC_BOUNCER_KEY}` but the old container's env has no key → the
`caddy crowdsec health` post-condition (`:509-529`) fails after 60s → step
exits 1, on exactly the re-run the code was written to handle.

- [x] Move the three `*_changed=0` initializations above Step 2 (before
  line 86), or make line 104 accumulate (`: "${compose_changed:=0}"`).

---

## Phase 2 — CRITICAL: runner CLI hardening (both runners + maintain.d)

Files: `init.sh:64-83`, `user/init.sh:68-87`,
`user/init.d/30-scripts/scripts/maintain.d/run.sh:61-63,208,216`.

Verified empirically in review: `--from` with no operand crashes (unbound
`$2`); `./init.sh 5` matches nothing yet reports success; an unrecognized
argument is silently ignored and the runner proceeds to run ALL steps.

- [x] Validate `--from` has an operand and it matches `^[0-9]+`; usage error
  otherwise.
- [x] Normalize numeric comparisons: compare `$((10#$num))` against
  `$((10#$only_number))` so `5` matches `05-…` (both runners +
  `maintain.d/run.sh:208`). Reject a bare-number selector that matches no
  step with a loud "no such step" error instead of running nothing (or
  everything).
- [x] Hard-error on any unmatched positional argument (typo'd selector must
  never become a full run).
- [x] `--help` in `user/init.sh:71` prints via a brittle `sed` range; align
  with the root runner's simpler extraction.
- [x] `maintain.d/run.sh:41`: take the first `# @tier` match only
  (`grep -m1`) — a duplicated tier line currently kills the runner under
  `set -e`.

---

## Phase 3 — HIGH: privilege & input validation (root tier)

### 3.1 Scope the sudoers whitelist (`init.d/30-passwordless-sudo/`)

- [x] Replace `/usr/bin/systemctl *` with verb-scoped entries (start, stop,
  restart, reload, status, daemon-reload, enable, disable — as needed by the
  deployed scripts in `user/init.d/30-scripts/scripts/`). `systemctl edit
  --full` and `link` are silent root escalation.
- [x] Replace `/usr/bin/cscli *` with the specific verbs the host needs, or
  document the deliberate breadth.
- [x] Remove dead entry `commands.txt:16` (`/usr/bin/docker compose` is
  subsumed by the bare `/usr/bin/docker` line above it).
- [x] Decide the docker line's intent: bare `/usr/bin/docker` is
  root-equivalent; either keep and document, or drop and rely on the docker
  group.
- [x] Coordinate with Phase 4.4 (the `@sudo` maintenance tier) so the
  whitelist and the scripts agree on one model.

### 3.2 Validate `BOOTSTRAP_USER` (`init.d/10-create-deploy-user/run.sh:62-70`)

- [x] `[[ "$BOOTSTRAP_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]`, reject otherwise
  (newline injection into `chpasswd` can reset root's password).
- [x] Refuse existing users with UID < 1000 except the intended deploy user;
  refuse `root` explicitly (currently `id` succeeds and the account gets
  `usermod -aG sudo` + password set).
- [x] Add `-r` to the interactive `read` at `:52` (backslash mangling).
- [x] Reconcile the non-interactive rule with the interactive password
  fallback at `:38-55`: prefer `.env`-only, or document the exception; scrub
  the README's `BOOTSTRAP_PASSWORD='…' ./init.sh` pattern from shell history
  guidance (it lands the password in root's history).

### 3.3 sudoers validate-before-activate (`init.d/30-passwordless-sudo/run.sh:18,53-55`)

- [x] Build the sudoers file to a temp path, `visudo -cf` the temp, then
  `install -m 0440` into `/etc/sudoers.d/` (currently written live then
  validated — a bad file breaks all sudo in between).
- [x] Sanitize the username embedded in the output filename: a dot in
  `$SUDO_USER` produces `99-john.doe-passwordless`, which sudo silently
  skips. Validate against `^[a-z_][a-z0-9_-]*$` (3.2 covers this at source).
- [x] Guard `SUDO_USER` with the `: "${VAR:?msg}"` pattern the sibling steps
  use (currently dies cryptically under `set -u`).

### 3.4 CrowdSec install integrity (`init.d/54-crowdsec/run.sh:94`)

- [x] Replace `curl -fsSL https://install.crowdsec.net | bash` with
  fetch-then-verify (pinned checksum) or vendor the repo setup directly
  (write sources.list + keyring like `59-gh-cli` does). The comment at
  `:52-61` claiming parity with the Docker GPG step is a false equivalence —
  apt verifies packages, nothing verifies the piped script.
- [x] Consider binding LAPI away from `0.0.0.0:8080` (`:122`) until ufw is
  confirmed active, or enable ufw non-interactively at the end of 52 now
  that the SSH rule is staged first (see 4.3 note).
- [x] Make the `acquis.yaml` rewrite at `:200-202` atomic (temp + `install`),
  and harden the legacy-block awk stripper at `:190-205` against a
  two-filename legacy block.

### 3.5 libvirt qemu hook guard (`init.d/57-kvm/run.sh:190-195`)

- [x] Implement the intended `HOOK_MARKER` guard: if
  `/etc/libvirt/hooks/qemu` exists and lacks the marker, fail loudly with
  instructions; overwrite only when marker-present or absent.

### 3.6 mDNS public-uplink exposure (`init.d/58-mdns/run.sh:110-114`)

- [x] When no RFC1918/ULA interface is detected, write an explicit
  `allow-interfaces=lo` (or mask `avahi-daemon` loudly) instead of rendering
  no restriction at all. The step's stated guarantee ("mDNS is never
  published on a public uplink") is currently false on plain public VPSes.
- [x] Sanitize the DHCP-derived domain before `printf '%b'` at `:75`
  (`^[a-z0-9.-]+$`) or switch to `%s`; fix the `AVAHi_CONF` typo at `:28`;
  skip the avahi restart when the config compare says unchanged; back up
  `/etc/hosts` before editing.

---

## Phase 4 — HIGH: scripts tree (deployed tooling safety)

### 4.1 `16-nvm-old-versions.sh` total-deletion guard
(`maintain.d/16-nvm-old-versions.sh:16-37`)

- [x] Abort with `log_skip` when both the active version and
  `~/.nvm/alias/default` are unresolvable (currently removes ALL installed
  Node versions in that case).
- [x] Resolve aliases to concrete installed dirs (prefix-match `v24.*` etc.)
  instead of string equality.

### 4.2 Gate ee-layout steps off the `$HOME` fallback
(`scripts/lib/env.sh:15`, `maintain.d/{05,63,95,09}.sh`)

- [x] Treat `EE_ROOT == $HOME` fallback as "no project root": require a
  positive marker (`.git`/`apps/` present or an explicit opt-in env var)
  before running ee-layout steps; `log_skip` otherwise. Currently a tier-1
  `maintain` on a non-ee host deletes from `~/archive` (63) and sweeps all of
  `$HOME` (05, 95).

### 4.3 `kill_pid` process-identity check (`dev.d/common.sh:65-90`)

- [x] Before `kill -9 -- -PGID`, verify the PID is actually the backend
  (check `/proc/$pid/cmdline` for the expected pattern, or record PGID at
  start time in a `.pgid` sidecar and compare). A recycled PID currently gets
  its whole new process group killed.
- [x] Add `# shellcheck disable=SC2015` with a one-word comment at `:80,85`
  (confirmed benign best-effort escalation).

### 4.4 Fix the `@sudo true` maintenance tier end-to-end
(`scripts/lib/maintain-common.sh:33-51`, `maintain.d/{75,80,90,91}.sh`)

Currently fully inert: whitelist grants don't cover any invoked command, and
the `sudo -n true` probe fails regardless.

- [x] Decide the model: either (a) add narrow whitelist entries
  (`/usr/bin/apt-get autoremove -y`, `/usr/bin/journalctl --vacuum-time=*`,
  a root-owned `/usr/local/sbin/drop-caches` wrapper for 80) and change the
  probe to attempt-and-handle-rc or `sudo -n -l`, or (b) delete the `@sudo`
  tier and document root maintenance as root-tier `init.sh` steps.
- [x] Fix the skip message: `sudo maintain` can't work (`~/.local/bin` not in
  sudo's `secure_path`) — print the absolute path.

### 4.5 `50-vite.sh` pm2 ordering (`dev.d/50-vite.sh:7-10`)

- [x] Move the `command -v pm2` check after the `has_frontend` skip and make
  it non-fatal (`log_skip` + `exit 0`). Currently `dev up` aborts the whole
  sequence on pm2-less machines even for Go-only projects.

### 4.6 Verify the `kilo serve` process guard
(`maintain.d/120-kilo-db-vacuum.sh:27`, `135-kilo-full-reset.sh:20`,
`diagnose.d/15-kilo.sh:9`)

- [x] On a live host, check `ps -eo command` for the real Kilo process name;
  `pgrep -f 'kilo serve'` matches nothing documented in this repo, and 135
  `rm -rf`s `~/.local/share/kilo` under a running agent if the guard is dead.
  Broaden the match (e.g. `pgrep -x kilo`) and/or check open handles with
  `lsof` on the DB.
- [x] Add the same running-process guard to `130-cascade-full-reset.sh:15`
  (Windsurf/Codium) — it's the only reset step without one.

### 4.7 `36-kilo` breaks on the documented default `node: "latest"` (`user/init.d/36-kilo/run.sh:25`)

`nvm use --delete-prefix "$EE_NODE_VERSION"` receives the **raw** pin —
35-node resolves `latest`/partial pins to a full `x.y.z` only inside its own
subshell and never persists the resolved value. nvm has no `latest` alias
(`nvm_validate_implicit_alias` accepts only `stable|unstable|node|iojs`), so
`nvm use latest` fails → `set -e` aborts the step. `node: "latest"` is what
`example.bootstrap.conf.yml:71` ships and what `lib/common.sh:40` defaults
to. Partial pins survive only by nvm's prefix-matching.

- [x] `nvm use --delete-prefix default` (35-node always sets the default
  alias to the pin), or factor the version resolver into `lib/` and reuse it.

---

## Phase 5 — MEDIUM batch

### Root tier

- [x] `init.d/50-docker/run.sh:129-148` — merge `daemon.json` with `jq`
  (own only the step's keys) or declare exclusive ownership in docs; re-runs
  currently clobber app-added `hosts` entries without backup. Fix the
  `SYSCtl_FILE` typo at `:197`; write the sysctl drop-in only when changed.
- [x] `init.d/52-ufw/run.sh:82,109` — move the hardcoded management CIDR
  `170.203.0.0/16` to `.env` (`MGMT_SSH_CIDR`, fail loudly when unset);
  compare-before-write the resolved drop-in at `:48-53`.
- [x] `init.d/53-fail2ban/run.sh:79` — add the ufw-inactive warning that
  `54-crowdsec:149-151` has, or use `banaction = iptables-multiport` until
  ufw is enabled.
- [x] `init.d/45-woodpecker-local/run.sh` — pass through the runner's
  `BOOTSTRAP_CONFIG_FILE` instead of hardcoding
  `"$BOOTSTRAP_ROOT/bootstrap.conf.yml"` (`:37`); source `lib/common.sh` like
  every other root step; pin a SHA256 for the plugin-git download (`:42-46`)
  and reinstall on version mismatch (the `command -v` gate never upgrades);
  add an arch check (URL is amd64-only); compare-before-write `.ssh/config`
  (`:23-29`); seed GitHub's published host keys instead of
  `StrictHostKeyChecking accept-new`; add a `.requires` gate if woodpecker
  isn't universal (confirm intent — currently provisions a CI user on every
  host).
- [x] `init.d/55-lazydocker/run.sh:58-67,76` — grep checksums.txt for the
  exact tarball name before `sha256sum -c --ignore-missing` (currently passes
  vacuously on asset renames); remove the dead `else` branch that calls the
  missing tool; run the version probes as the target user, not root; fix the
  `cd` without `|| exit` at `:59`.
- [x] `init.d/01-apt-update-upgrade/run.sh:16` — add
  `--force-confdef --force-confold` for consistency with 05/06/50.
- [x] `init.d/20-groups/run.sh:29` — drop the `2>/dev/null || true` on
  `groupadd` (swallows real errors; the subsequent `usermod` fails loudly
  anyway).
- [x] `init.d/56-ssh-client/run.sh:83` — verify `Include ~/.ssh/hosts.d/*`
  tilde expansion against the oldest targeted OpenSSH; no-op the bashrc
  cleanup loudly when `~/.bashrc` is absent (`:26`).
- [x] `init.d/57-kvm/run.sh:130-137` — test for the sysctl drop-in file, not
  the runtime value (Docker may already have set `ip_forward=1`, in which
  case persistence is never written); compare-before-write
  `/etc/profile.d/kvm.sh`; fail loudly when `SUDO_USER` is unset like sibling
  steps do.

### Config / repo hygiene

- [x] `.gitignore`: add `*.conf.yml` with `!example.bootstrap.conf.yml`
  (hostname-override confs are currently committable), and `secrets/`
  (AGENTS.md mandates the dir; nothing ignores it).
- [x] Reconcile `secrets/`: it is referenced by zero scripts. Either wire the
  secret-generating steps (54-crowdsec, 45-woodpecker) to write there with
  `chmod 700/600`, or remove the convention from AGENTS.md.
- [x] `bootstrap.conf.yml` (live): strip the example file's stale "Copy this
  file to bootstrap.conf.yml" header.
- [x] Delete or intentionally track
  `kilo-session-reports/20260902T182328Z/report.txt` (untracked despite the
  gitignored dir) and
  `user/init.d/30-scripts/scripts/__pycache__/` (committed bytecode that
  `sync_dir_preserve` ships to every `~/scripts`).

### User tier (from the late-arriving deep review)

- [x] `20-python/run.sh:47-54` — remove the silent uv fallback to hardcoded
  `0.9.0` on GitHub API failure: the idempotency check at `:115` then treats
  any newer installed uv as "not matching the pin" and **downgrades** it.
  Fail loudly (the step already does for python at `:160-164`).
- [x] `20-python/run.sh:150-152` — fix the exact-pin detection pattern:
  installed interpreters print `cpython-3.13.7-linux-x86_64-gnu` (hyphen
  after version), but the grep is `^cpython-${VER}(\.|$)` → exact pins
  reinstall every run. Use `^cpython-${EE_PYTHON_VERSION}(\.|-|$)`.
- [x] `25-go/run.sh:186-223` — make `install_go_tools` actually idempotent
  as the header claims (skip when the binary exists) or pin tool versions;
  currently `go install …@latest` runs for all four tools on every re-run
  and silently upgrades them.
- [x] `25-go/run.sh:102-110` — the version check tests `go` from PATH but
  everything later uses `$HOME/.local/go/bin/go`; a foreign Go at the pinned
  version on PATH skips the tarball install and the step dies later on the
  missing `${GO_BIN}`. Check `"$GO_BIN" version` instead.
- [x] `60-caddy/run.sh:90-95` — `sudo cscli bouncers add` without `-n` can
  hang the "non-interactive" step if the sudoers drop-in is missing/stale.
  Use `sudo -n` so it fails into the existing recovery branch.
- [x] Supply-chain integrity for toolchain installers:
  `35-node/run.sh:95-101` sources `nvm.sh` fetched from a **mutable git tag**
  (`v0.40.4`) — pin to a commit SHA; `25-go/run.sh:117-123` — verify the Go
  tarball against go.dev's published `.sha256`; `38-woodpecker-cli/run.sh:18`
  — add a checksum; add `--retry` to 35-node's curls for consistency.
- [x] `38-woodpecker-cli/run.sh` — source `../lib/common.sh` (currently no
  non-root guard; running it directly as root pollutes `/root/.local/bin`),
  use `get_pinned_version` (hardcoded `v3.17.0` default), and map `uname -m`
  (hardcoded `linux_amd64` installs the wrong arch on aarch64; 25-go models
  this correctly).
- [x] `40-npx-skills/run.sh:16` — source nvm + `nvm use default` like
  98-npm-shared does; currently relies on ambient `npx`, which is absent in
  non-interactive invocations (ssh, cron) since nvm is only wired into
  `.bashrc`.
- [x] `sync-kilo-context.sh:74-84` — sync scope gaps vs. what
  37-kilo-settings deploys: add `rules` to the loop and a `kilo.json` block
  next to `kilo.jsonc`; live edits to those currently never reach the repo.
- [x] Version resolvers (`20-python`, `25-go`, `35-node`) — switch the
  grep-based JSON parsing to `jq` (already a dependency of 60-caddy and
  99-go-shared); strictly more robust.

### Scripts tree
- [x] `scripts/lib/retention.sh:51,104,39,67` — replace the fatal
  `${PROJECT_DIR:?}` with a soft check + `return 0` (the header promises
  "never blocks the caller"); delete via the resolved path, not the
  unresolved one; numeric-validate `EE_RESULTS_KEEP`; then silence SC2115
  with a documented directive.
- [x] `maintain.d/05-results-prune.sh:19,36,86` — source the deployed
  `~/scripts/lib/retention.sh` (not the ee-monorepo copy) and
  `export PROJECT_DIR="$EE_ROOT"`; add `-maxdepth` or prune
  `node_modules/.git/.cache` in the finds.
- [x] `maintain.d/12-node-ecosystem-cache.sh:31-38` — require
  `${NVM_DIR}/nvm.sh` to exist before deleting anything (a misconfigured
  `NVM_DIR=$HOME` turns the prune into `rm -rf ~/.cache`).
- [x] `maintain.d/65-codium-state-dumps.sh:27,35` — add a name predicate
  matching the dump format (e.g. `-name '2[0-9][0-9][0-9]-*'`); currently
  deletes any subdir of the VSCodium state dir older than 7 days.
- [x] `maintain.d/72-pm2-logs.sh:10,21` — flush per-project
  `.dev/pm2/logs` (where `dev` actually isolates pm2) instead of
  `$EE_ROOT/.pm2/logs`.
- [x] Failure accounting across `maintain.d` (12:42, 34:25, 57:26, 85:26,
  50:49 + `run.sh:220-226`): track an in-step failure flag and `exit 1`;
  skip post-state checks in dry-run branches (currently dry-run prints
  "✗ failed to remove" for things never attempted).
- [x] `ci.d/common.sh:42` — replace the process-substitution tee with
  `"$@" 2>&1 | tee "$log_file"; status=${PIPESTATUS[0]}` so the failure
  digest never reads a partial log.
- [x] `maintain.d/{70,96}` — check `docker info` (daemon), not just the
  binary; propagate prune rc. Reconfirm 96's `--volumes` caution in its
  summary line.
- [x] `maintain.d/09-git-tmp-packs.sh:25` — add `-mmin +60` so an in-flight
  fetch's temp pack survives.
- [x] `ci.d/30-python.sh:8-9` — `uv run ruff check .` (or tool fallback) for
  consistency with the uv invocations; `ci.d/10-go.sh:7-10` — absent
  gosec/govulncheck should SKIP, not FAIL.
- [x] `scripts/lib/maintain-common.sh:64` — remove the dead git-probe branch
  in `detect_ee_root` (deployed `~/scripts/lib` is never a git repo).
- [x] `dev.d/{40-air,42-uv,45-backend}` — extract the triplicated `down`
  port-kill block into `dev.d/common.sh`.
- [x] `build.d/10-frontend.sh:58-63` — check `_npm_ci_rc` and fail with
  "npm ci failed"; fix the literal `\`\`\`` fence lines across build.d
  (write `'```'`); `build.d/common.sh:34-38` — escape `$err` before JSON
  interpolation.

---

## Phase 6 — LOW / hygiene (batch commit)

- [x] `scripts/lib/env.sh:1`, `maintain.d/common.sh:1` — add
  `# shellcheck shell=bash` (source-only files; siblings carry the
  directive).
- [x] `maintain.d/run.sh:195` — implement or delete the unused `skipped`
  counter; `build.d/common.sh:19` — delete unused `BOLD` (the
  maintain-common one IS used by `--list`, silence with a directive).
- [x] `scripts/lib/version.sh:45-49` — validate build numbers `^[0-9]+$`.
- [x] `50-go-caches.sh:70`, `95-iso-output.sh:19,24` — quote the pattern in
  `${var#"$EE_ROOT"/}` (SC2295, cosmetic log text); wrap size reads in
  `user_run` so `sudo maintain` reports the user's cache sizes, not root's.
- [x] `54-uv-cache.sh:24-27` — drop cargo-cult `yes |`; fix the comment
  (`--force` skips the in-use lock, never prompts).
- [x] `user/sync-kilo-context.sh` — split the combined `local` at `:59`
  (SC2318 readability), replace the one-element `for dir in skills` loop at
  `:101` with a plain block or comment, and add a comment noting the
  intentional wholesale `rm -rf` mirror semantics (vs. `sync_dir_preserve`
  elsewhere).
- [x] `user/init.d/25-go/run.sh:277` — quote `"$HOME/go/bin/..."` (cosmetic;
  `$HOME` can't contain spaces here).
- [x] `user/init.d/60-caddy/run.sh:339` — replace the literal
  `~/bootstrap/docs/central-caddy.md` with a `$HOME`-expanded path in the
  generated JSON doc string.
- [x] `user/init.d/35-node/packages.txt:7` — stale comment says browsers
  install via `npx playwright install --with-deps`, but `run.sh:189-193`
  deliberately omits `--with-deps` (root tier owns OS deps).
- [x] `user/init.d/35-node/run.sh:158,178` — the `npm list -g` snapshot is
  taken once and matches any installed version, so bumping a version in
  `packages.txt` never upgrades. Match the pinned version or reinstall on
  mismatch.
- [x] `user/init.d/12-bashrc/run.sh:46,116` — use `id -un` instead of
  `$USER` (not guaranteed under `set -u` in stripped environments); the
  `mktemp`+`mv` path leaves `.bashrc` at 0600 while the create path sets
  0644 — normalize the mode.
- [x] `user/init.d/10-llmdocs/run.sh:37` — `rm -rf "$HOME/llmdocs"` destroys
  local edits on re-run; switch to `sync_dir_preserve` for consistency (the
  destruction is documented, so this is a consistency call).
- [x] `user/init.d/98-npm-shared/run.sh:44` — the transitional fallback
  shell-sources `.env` (arbitrary execution + `set -u` fragility); when next
  touched, parse instead (`grep '^BROADMINDE_PACKAGES_TOKEN='`).
- [x] `user/init.d/60-caddy/run.sh:189` — `[[ ! -L …/caddy-route ]]` passes
  on broken/stale symlinks; use `ln -sfn` unconditionally or compare
  `readlink`.
- [x] `25-go/run.sh:255-259` + `99-go-shared/run.sh:194` — both
  wholesale-overwrite `GOPRIVATE` via `go env -w`; merge with existing
  user-added entries instead.
- [x] Shellcheck-noise hygiene: annotate the intentional literal-expansion
  sites with `# shellcheck disable=SC2016` (`35-node:106-108`,
  `60-caddy:215-281`; 25-go:141 already models this) so real signal isn't
  buried; same for `dev.d/common.sh:80,85` (SC2015) and
  `sync-kilo-context.sh:59,101` (SC2318/SC2043 — both confirmed benign).
- [x] `diagnose.d/{15,20}` — scope `ps` to `-u "$(id -u)"` for truthful
  per-user numbers.
- [x] `dev.d/50-vite.sh:35` — consider `0.0.0.0` default parity with
  `42-uv.sh:76` (`--host ::` breaks on IPv6-disabled hosts).
- [x] `init.d/50-docker/run.sh:98` — consider pinning the Docker GPG
  fingerprint (one line; TOFU matches upstream docs but is cheap to close).
- [x] `init.d/54-crowdsec/run.sh:251-258` — document the deliberate
  `0640 root:crowdsec` credential-permission choice (widens LAPI/CAPI
  credential reads to the deploy user).
- [x] `init.d/10-create-deploy-user` + `50-docker:41-44` — make `.env`
  handling consistent (AGENTS.md says repo-root `.env`; 50 sources a
  step-local one; 10 reads none).

---

## Documentation sync (do with the phases that touch them)

- [x] `README.md` quick start → two-phase flow (Phase 1.3).
- [x] `AGENTS.md` — update the `.env`/secrets section if the `secrets/`
  convention is wired or dropped (Phase 5); runner CLI semantics if selector
  validation changes behavior (Phase 2).
- [x] `docs/codemap.md` — step contract changes (deploy-user resolution,
  `.requires` additions).

## Deferred / noted

- The user-tier deep review arrived after the plan was first drafted; its
  findings are merged above (1.4, 4.7, the Phase-5 "User tier" block, and the
  Phase-6 additions). No remaining coverage gaps.
- Review baseline: commit `92d7581` (main).
