# bootstrap

Host provisioning for fresh cloud VPSes.

This repo is split into **two tiers** that run in sequence:

| Tier   | Runs as | Runner               | Location                       |
|--------|---------|----------------------|--------------------------------|
| root   | root    | `./init.sh`          | top-level `bootstrap/`         |
| user   | user    | `./user/init.sh` | top-level `user/` |

The **root tier** turns a stock Debian/Ubuntu box into a deploy-ready
host: apt is updated, a baseline sysadmin toolset is installed, a
non-root deploy user is created with `sudo` membership, common dev/
ops packages are added, passwordless sudo is configured for
`systemctl` and `docker`, SSH is hardened, ufw is staged, fail2ban is
installed, and — depending on the capability flags set in
`bootstrap.conf.yml` — Docker CE, KVM, and CrowdSec are installed.

After the root tier finishes, log in as the deploy user and run the
**user tier** (`./user/init.sh`). It installs per-user
tooling into `$HOME/.local/bin/` — `uv`, a uv-managed Python, the
`kilo` CLI, Go toolchain, Node.js, direnv, and wrappers for the
`llmdocs` and user scripts that ship in this repo — and, when the
`caddy` capability is enabled, provisions the host's central Caddy
reverse proxy at `~/infra/caddy/`. The user tier is **not**
capability-gated as a whole; individual steps declare their own
`.requires`.

After both tiers finish, individual apps (e.g. `apps/<app>/` in
their own repository) take over and run their own `init.sh` as the
deploy user.

### Central Caddy (60-caddy)

When both `docker` and `caddy` capabilities are enabled, the user tier
installs **one Caddy reverse proxy per host** at `~/infra/caddy/`
(everything deploy-user owned — the step runs as the deploy user and
needs only docker group membership). It listens on 80/443 and serves
TLS for every app on the host. App stacks register Caddyfile snippets
via `caddy-route`:

```bash
caddy-route register myapp ./myapp.caddy   # add a site
caddy-route deregister myapp               # remove it
caddy-route list                           # see what's running
```

Snippets are plain Caddyfile site blocks (no global options — ACME email,
logging, CrowdSec, and Admin API are owned centrally). The provisioning step
starts the stack itself (refusing only when ports 80/443 are held by another
service) and verifies wildcard cert readiness. Caddy resumes its autosaved
configuration across restarts, while `routes.d/` remains the source of truth
and `caddy-route reconcile` replays it when needed.

Full documentation: [docs/central-caddy.md](docs/central-caddy.md)

Wildcard zones are configured via the `caddy:` section of `bootstrap.conf.yml`
(`base_domain` + `wildcards` labels). They render only after acme-dns
registration; see [Wildcard zones](docs/central-caddy.md#wildcard-zones).

---

## Quick start

Fresh hosts provision in two phases. Step 10 — which creates the deploy
user — runs as **root** on the fresh VPS; everything after it runs as
the **deploy user** via `sudo` (the remaining root-tier steps resolve
the deploy user from `SUDO_USER`).

```bash
# ---- Phase 1: as root on the freshly provisioned VPS ----
apt-get install -y git
git clone https://github.com/<your-org>/bootstrap.git
cd bootstrap

# Configure capabilities for this host.
cp example.bootstrap.conf.yml bootstrap.conf.yml
# Edit bootstrap.conf.yml — set docker, caddy, kvm, dev, public to true/false.
$EDITOR bootstrap.conf.yml

# Provide the deploy-user parameters via .env (gitignored). Keeping the
# password in .env — instead of on the command line — keeps it out of
# root's shell history.
cat > .env <<'EOF'
BOOTSTRAP_USER=luke
BOOTSTRAP_PASSWORD='…'
# Optional but recommended: enroll an SSH key so the deploy user can
# log in even after password auth is disabled in a later round.
# BOOTSTRAP_SSH_PUBKEY=ssh-ed25519 AAAA… you@your-workstation
EOF
chmod 600 .env

./init.sh 10          # creates the deploy user (as root)

# ---- Phase 2: log out, log back in as the deploy user ----
cd bootstrap
sudo ./init.sh        # all remaining root-tier steps
cd user
./init.sh             # user tier

# ---- hand off to an app repo ----
cd ../<app>            # or wherever the app repo lives
./init.sh
```

Run a single step (e.g. just Docker):

```bash
sudo ./init.sh 50-docker
```

Run everything from a chosen point onward:

```bash
sudo ./init.sh --from 30
```

`./init.sh --help` lists the `--from <NN>` and `<NN>` selectors.
Both runners accept the same selectors.

---

## Post-bootstrap credential setup

The root tier installs `gh`, but authentication and host credentials remain
per-user and interactive. After both bootstrap tiers complete, run:

```bash
~/scripts/bootstrap-access
```

It takes no arguments: it reads the active `bootstrap.conf.yml` (or
`<hostname>.conf.yml`), works out which capabilities are enabled, and walks
each one that needs interactive credentials:

- **gh login** — whenever any enabled stage needs `gh` (today: `dev`).
- **dev** — read-only `go-shared`/`frontend-shared` deploy keys registered via
  the GitHub API, the GitHub Packages classic PAT (validated and stored in
  `~/.config/gh/broadminde-packages.token`, then written to `~/.npmrc` by
  `98-npm-shared`), and the
  optional source RW PAT (`repo`, `workflow`). Credential breadth comes from
  the conf's `github:` section: `packages_write: true` collects
  `write:packages` on publish hosts, `source_rw: true` collects the source RW
  PAT — the walk reads the conf instead of asking per run.
- **caddy** — verifies the ACME account email in `~/infra/caddy/.env` (set
  non-interactively from `caddy.acme_email` in the conf by 60-caddy; the walk
  is the fallback when the conf leaves it empty), plus acme-dns account
  registration when `caddy.wildcards` declares zone labels (prints the
  `_acme-challenge` CNAMEs to add to DNS).

`docker`, `kvm`, and `public` need no interactive credentials (the CrowdSec
bouncer key is generated non-interactively by `60-caddy`), so on a host with
only those enabled the script reports that and exits. Every stage verifies
current state before prompting, so re-running is safe and idempotent.

The stages are also runnable individually — see below.

## GitHub private access

The GitHub stages of `bootstrap-access` delegate to the `github-access`
helper, which is also the standalone entry point when you want to redo one
piece:

```bash
~/scripts/github-access setup
```

The normal setup authenticates `gh`, asks `99-go-shared` to create/register
read-only `go-shared` and `frontend-shared` deploy keys through the GitHub API,
and configures a package-registry PAT through `98-npm-shared`.

Credentials are intentionally split by blast radius:

| Credential | Where it lives | Minimum permissions | Purpose |
|---|---|---|---|
| Operator `gh` auth | gh credential store | gh defaults | Human issue/PR/API workflows |
| Per-repo deploy keys | `~/.ssh/` | read-only | Source fetches for shared repos |
| `BROADMINDE_PACKAGES_TOKEN` | `~/.config/gh/broadminde-packages.token` → `~/.npmrc` and, on Docker hosts, `~/.docker/config.json` | `read:packages` | npm package access and private GHCR image pulls |
| `BROADMINDE_PACKAGES_TOKEN` on publish hosts | Same token file and client configs | `read:packages`, `write:packages` | Publish npm packages and GHCR images |
| `BROADMINDE_SOURCE_RW_TOKEN` | `~/.config/gh/broadminde-source-rw.token` | `repo`, `workflow` | CI/source updates, pushes, issues, and PRs |

The classic PATs live in dedicated mode-0600 files under `~/.config/gh/`,
never in the bootstrap checkout — see `docs/adr/0001-github-pat-storage.md`.
Legacy `bootstrap/.env` entries are migrated on the next `github-access` run.

GitHub Packages' npm registry requires a classic PAT. `gh` cannot mint a
separate PAT, and its broader OAuth token is not copied into `~/.npmrc`. If the
organization enforces SSO, authorize each new PAT for `broadminde-org` after
creating it.

For a RW update/test host such as a CI control host, run:

```bash
~/scripts/github-access setup --ci
```

That requests a package token with `write:packages` and a separate source RW
token with `repo` and `workflow`.

Useful follow-ups:

```bash
~/scripts/github-access status
~/scripts/github-access deploy-keys
~/scripts/github-access packages          # read:packages
~/scripts/github-access packages --write  # read:packages + write:packages
~/scripts/github-access source-rw         # repo + workflow
~/scripts/github-access clear source-rw   # remove a stored token
~/scripts/github-access clear --all       # remove both stored tokens
```

---

## Configuration (`bootstrap.conf.yml`)

`bootstrap.conf.yml` is a single file with sections: `capabilities:` (which
provisioning steps run), `versions:` (which toolchain versions to install),
`skills:` (which agent targets receive npx-installed skills), `caddy:`
(wildcard zone `base_domain` and `wildcards` labels), `github:` (host
credential role for the access walk), and `portal:` (the central-Caddy Portal
mode, `dev` or `image`). The Caddy discovery file publishes the effective
`base_domain` and `portal_mode` so app repositories consume one runtime
contract instead of parsing bootstrap configuration.

### Capability flags

Each step in `init.d/` may declare required capabilities via a `.requires` file;
steps without one always run. A step is skipped when its selecting capability
is disabled. For multiple entries, list prerequisites first and the selecting
feature last (e.g. `docker`, then `caddy`): enabling the feature without its
prerequisites fails before any step runs.

| Capability | Steps gated | Default |
|---|---|---|
| `caddy` | user-tier 60-caddy | `true` |
| `docker` | 50-docker, 55-lazydocker | `true` |
| `kvm` | 57-kvm | `false` |
| `dev` | 06-playwright-deps, user-tier 25-go, 97-gh-auth-instructions, 98-npm-shared + 99-go-shared | `false` |
| `public` | 54-crowdsec | `false` |
| `woodpecker` | RETIRED — 45-woodpecker-local.disabled (local agent runs as deploy user via ci repo) | `false` |

Always-run root-tier steps (no `.requires`): 01-apt, 05-packages, 10-user,
20-groups, 30-sudo, 40-profile, 51-ssh-hardening, 52-ufw,
53-fail2ban, 56-ssh-client, 58-mdns, 59-gh-cli. The user tier always runs;
per-step gating applies (e.g. 60-caddy requires `docker` + `caddy`).

Capabilities are an allowlist: a capability is enabled only when it is listed
and set to `true`. Unlisted capabilities are disabled; host confs can omit
disabled features. `example.bootstrap.conf.yml` defines the valid names. Both
runners reject missing configs or `capabilities:` blocks, unknown/duplicate
names, malformed entries, and unknown active `.requires` names before running
any steps. Other sections (`versions`, `skills`, `caddy`, `github`, `portal`)
remain optional and retain their existing defaults.

A hostname-specific override (`<hostname>.conf.yml` in the repo root) takes
precedence over `bootstrap.conf.yml` when present. Both tiers resolve it the
same way: each runner selects the file and exports it as
`BOOTSTRAP_CONFIG_FILE`, and step subshells that re-source `conf.sh` honor
that export — so root-tier gating and user-tier steps (e.g. 60-caddy's
`public` check) never evaluate different capability sets.

### Shared project script configuration

Shared `dev` and `build` source project-root `.env` files as trusted Bash, so
custom command values can use shell syntax. Docker Compose uses dotenv
interpolation semantics, not Bash. Values shared with Compose should use the
portable dotenv subset; do not assume Bash expansion or command substitution
works in Compose. The `stack` wrapper should not add a third incompatible
parser. Never log secrets or place secret values in reports or other result
artifacts.

All shared-script variables added or standardized by the script consolidation
are listed here. Unset values preserve the prior behavior. Examples show
project-local `.env` values, not repository defaults:

| Variable | Default and behavior | Example |
|---|---|---|
| `FRONTEND_DEV_HOST` | `::`; dual-stack Vite bind default (pre-existing behavior) | `127.0.0.1` |
| `FRONTEND_PORT` | Unset; auto-parse and export Vite's selected port. A configured value is passed as a strict port. | `5173` |
| `FRONTEND_HMR_HOST` | Unset; leaves project HMR behavior unchanged | `portal.dev.example.net` |
| `FRONTEND_HMR_PROTOCOL` | Unset; leaves project HMR behavior unchanged | `wss` |
| `FRONTEND_HMR_CLIENT_PORT` | Unset; leaves project HMR behavior unchanged | `443` |
| `DEV_CADDY_HOST_PREFIX` | Unset; does not inspect central Caddy config; when set derives an HMR host if none is explicit | `portal.dev` |
| `CI_TEST_GO_DIR` | `.`; root-level Go detection | `backend` |
| `CI_TEST_NODE_DIR` | `.`; root-level Node detection | `frontend` |
| `CI_TEST_PYTHON_DIR` | `.`; root-level Python detection | `python` |
| `CI_TEST_NODE_CHECK_SCRIPT` | `check`; required when Node directory/script configuration is enabled, otherwise prior detection applies | `lint` |
| `CI_TEST_NODE_BUILD_SCRIPT` | `build`; required when Node directory/script configuration is enabled, otherwise prior optional-build behavior applies | `build:ci` |
| `CI_TEST_NODE_E2E_SCRIPT` | `test:e2e`; configured E2E script is required with `--e2e`, while unconfigured projects retain the root-level optional step | `test:browser` |
| `BUILD_SWAG_VERSION` | Unset; use the pre-existing Swagger executable resolution | `v1.16.4` |
| `BUILD_SWAG_DIR` | `backend`; Swagger working directory | `api` |
| `BUILD_SWAG_MAIN` | `main.go`; Swagger entry point | `cmd/server.go` |
| `BUILD_SWAG_OUTPUT` | `docs/swagger`; generated output directory | `api/openapi` |
| `BUILD_SWAG_PARSE_DEPENDENCY` | `true`; preserves existing dependency parsing | `false` |
| `BUILD_SWAG_PARSE_INTERNAL` | `true`; preserves existing internal parsing | `false` |
| `BUILD_SWAG_REQUIRED_PATHS` | Empty; no required path validation. Multiple exact paths are comma-separated. | `/api/health,/api/config` |
| `BUILD_GENERATE_STRICT` | `false`; preserves compatibility behavior for generation failures | `true` |
| `IMAGE_ALIAS_TAGS` | Empty; no alias tags. Multiple Docker tags are comma-separated. | `main,stable` |

`stack config` displays the effective Compose configuration using the wrapper's
resolved files and profiles, and forwards Compose config flags. Its output can
contain interpolated secrets; keep it out of logs and result artifacts.

Capabilities gate **provisioning, not runtime state**: disabling one stops its
steps from running but never undeploys anything already installed (e.g.
`caddy: false` leaves a running central Caddy holding 80/443 — see
[docs/central-caddy.md](docs/central-caddy.md) for teardown).

### Version pins

The `versions:` section sets the toolchain and central Caddy version.
Set a tool to `"latest"` to auto-resolve the newest stable release at install
time, or pin an exact version string. Caddy defaults to `"latest"` when omitted;
its resolved version is saved in `~/infra/caddy/.env` for subsequent Compose runs.

| Tool | Env var | Description |
|---|---|---|
| `uv` | `EE_UV_VERSION` | Astral uv Python package manager |
| `python` | `EE_PYTHON_VERSION` | CPython version installed via uv |
| `kilo` | `KILO_VERSION` | Kilo CLI binary |
| `go` | `EE_GO_VERSION` | Go toolchain |
| `node` | `EE_NODE_VERSION` | Node.js (via nvm) |
| `caddy` | `CADDY_VERSION` | Central Caddy builder, binary, and runtime (exact version or `"latest"`) |

### GitHub credential role

The `github:` section is read by `bootstrap-access`. Development hosts
configure package access automatically; Docker-only hosts can opt in to private
GHCR pull access. It declares host credential breadth — no init.d step is gated on
it, and flipping a key never mints a token by itself; the walk validates (or
re-collects) the stored classic PATs to match.

```yaml
github:
  packages_read: false  # true on Docker hosts that pull private GHCR images
  packages_write: false  # true on publish hosts → PAT gains write:packages
  source_rw: false       # true on push/PR hosts → collects repo,workflow PAT
```

`packages_read` and `packages_write` default to `false` when unlisted. A dev
host gets package access automatically; a Docker-only host must set
`packages_read: true` to configure private GHCR pulls. Set `packages_write: true`
on publish hosts to require `write:packages`; Docker hosts also configure GHCR
auth and dev hosts configure npm auth. To widen an existing host, change the
role and re-run `~/scripts/bootstrap-access`. Docker credentials are stored in
`~/.docker/config.json` with mode 0600 (unless Docker uses an external credential
helper).

### Example configurations

**Full public app server** (Docker + Central Caddy + CrowdSec + Playwright browser deps):
```yaml
capabilities:
  docker: true
  caddy: true
  kvm: false
  dev: true
  public: true
```

**Public app server** (Docker + CrowdSec, no VMs, no browser-test deps):
```yaml
capabilities:
  docker: true
  caddy: true
  kvm: false
  dev: false
  public: true
```

**Internal build server** (Docker + KVM + Playwright deps, pinned versions, no edge proxy):
```yaml
capabilities:
  docker: true
  caddy: false
  kvm: true
  dev: true
  public: false

versions:
  uv: "latest"
  python: "3.13"
  kilo: "latest"
  go: "1.26.4"
  node: "24.5.0"
```

**Minimal private host** (bare baseline, no Docker, no extras):
```yaml
capabilities:
  docker: false
  caddy: false
  kvm: false
  dev: false
  public: false
```

---

## Layout

```
bootstrap/
├── bootstrap.conf.yml                # capability flags + toolchain version pins (copy from example)
├── example.bootstrap.conf.yml        # template — unconfigured
├── init.sh                           # ROOT-tier runner — picks up init.d/<NN>-* as root
├── init.d/
│   ├── lib/
│   │   ├── env.sh                    # sets EE_ROOT=bootstrap, toolchain version pins
│   │   ├── common.sh                 # root check + DEBIAN_FRONTEND / NEEDRESTART_MODE exports
│   │   └── conf.sh                   # unified config reader: load_conf, cap_enabled, step_requires_caps, get_pinned_version
│   ├── 01-apt-update-upgrade/        # apt-get update + upgrade -y
│   ├── 05-packages/                  # git, curl, wget, vim, htop, unzip, ca-certificates, sudo,
│   │   └── packages.txt              #   gnupg, gettext-base, jq, openssl, direnv, build-essential
│   ├── 06-playwright-deps/           # browser shared libs (Chromium/Firefox/WebKit; dev-gated)
│   ├── 10-create-deploy-user/        # useradd + chpasswd + sudo group + SSH key enrollment (idempotent)
│   ├── 20-groups/                    # DEPLOY_USER → groups from groups.txt
│   │   └── groups.txt                # adm, docker, sudo, systemd-journal, kvm, libvirt
│   ├── 30-passwordless-sudo/         # writes /etc/sudoers.d/99-<user>-passwordless (visudo-checked first)
│   │   ├── commands.txt              # verb-scoped systemctl, exact cscli bouncer cmds, maintenance wrappers
│   │   └── wrappers/                 # root-owned /usr/local/sbin helpers (drop-caches, prune-text-logs)
│   ├── 40-profile/                   # writes bootstrap-managed PATH block to the deploy user's .profile
│   │   └── profile.snippet           # idempotent ~/.local/bin + ~/.kilo/bin PATH block
│   ├── 45-woodpecker-local.disabled/ # RETIRED: local agent runs as deploy user via ci/init.d/20-agent-local
│   ├── 50-docker/                    # installs Docker CE + Compose plugin, merges daemon.json
│   ├── 51-ssh-hardening/             # PermitRootLogin no via 00-bootstrap-*.conf drop-ins; sshd -t + effective-value assertions
│   ├── 52-ufw/                       # ufw install + default-deny, public SSH allow, auto-enable
│   ├── 53-fail2ban/                  # fail2ban with sshd + Caddy jails
│   ├── 54-crowdsec/                  # CrowdSec LAPI + iptables bouncer (vendored apt repo setup)
│   ├── 55-lazydocker/                # drops lazydocker into the deploy user's ~/.local/bin/
│   ├── 56-ssh-client/                # SSH client defaults + ControlMaster cleanup
│   ├── 57-kvm/                       # qemu-kvm, libvirt, virtinst, bridge-utils
│   ├── 58-mdns/                      # mDNS via nsswitch + private-interface Avahi config
│   └── 59-gh-cli/                    # GitHub CLI from the official signed APT repository
├── user/                   # USER-tier — runs as the deploy user, not as root
│   ├── init.sh                       # user-tier runner — refuses root
│   ├── init.d/
│   │   ├── lib/
│   │   │   └── common.sh             # non-root check + sources conf.sh, exports version pins
│   │   ├── 10-llmdocs/               # installs `llmdocs` wrapper at $HOME/.local/bin/
│   │   ├── 12-bashrc/                # ~/.local/bin + ~/.kilo/bin PATH block in ~/.bashrc
│   │   ├── 15-direnv/                # direnv bashrc hook + profile-level direnvrc scaffold
│   │   ├── 20-python/                # installs uv + uv-managed Python
│   │   ├── 25-go/                    # installs Go toolchain + dev tools (dev-gated)
│   │   ├── 30-scripts/               # scripts/→$HOME/scripts/, runners→$HOME/.local/bin/, air skill + .air.toml template
│   │   ├── 35-node/                  # installs Node.js via nvm + global npm packages
│   │   ├── 36-kilo/                  # installs Kilo CLI via npm (after Node)
│   │   ├── 37-kilo-settings/         # deploys Kilo context, permissions, and global LLM safety rules
│   │   ├── 38-woodpecker-cli/        # installs pinned Woodpecker CLI into ~/.local/bin/
│   │   ├── 40-npx-skills/            # installs agent skills via npx skills CLI
│   │   ├── 60-caddy/                 # central Caddy reverse proxy (one per host)
│   │   ├── 97-gh-auth-instructions/  # points operators to the interactive ~/scripts/github-access helper (dev-gated)
│   │   ├── 98-npm-shared/            # configures GitHub Packages npm auth
│   │   │   ├── .requires             # dev
│   │   │   └── kilo/skills/          # frontend-shared-access agent skill
│   │   └── 99-go-shared/             # configures Go shared-module access
│   │       ├── .requires             # dev
│   │       ├── run.sh                # SSH deploy keys (gh-assisted) and Go module routing
│   │       └── kilo/skills/          # go-shared-access agent skill → ~/.kilo/skills/
│   ├── llmdocs/                      # stdlib-only Python docs framework (moved here)
│   ├── scripts/                      # user scripts (bootstrap-access, github-access, kilo-session-report.py)
│   ├── script-runners/               # thin wrappers deployed to $HOME/.local/bin/
│   └── vscode/                       # workspace VS Code recommendations + settings
├── LICENSE
└── README.md
```

### Tier-privilege model

- **Root tier** (`./init.sh`) — refuses to run as non-root. Steps
  `20-groups`, `30-passwordless-sudo`, `40-profile`, `51-ssh-hardening`,
  `55-lazydocker`, `56-ssh-client`, and `57-kvm` resolve the deploy user
  via `init.d/lib/user.sh` (`require_deploy_user`): `BOOTSTRAP_USER`
  first, then `SUDO_USER`; empty, `root`, an invalid account name, or a
  nonexistent user is a hard error. The remaining steps work as plain
  root.
- **User tier** (`./user/init.sh`) — refuses to run as
  root. All steps operate on `$HOME` and need no privilege
  escalation.

The provisioning privilege model does not grant privilege escalation to chat
LLM sessions. Chat LLM sessions never execute privilege escalation, even for
an approved change. Root-tier commands are run manually by the operator; an
agent must instead provide the exact commands, execution context, expected
result, and non-privileged verification steps where possible. Step
`37-kilo-settings` deploys this as an always-on global Kilo rule, with direct
command denials as defense in depth.

### Idempotency

Every step in both tiers is designed to be safe to re-run:

- `01-apt-update-upgrade` — `apt-get upgrade -y` is a no-op when up to date.
- `05-packages` — `apt-get install -y` is a no-op when satisfied.
- `10-create-deploy-user` — `useradd` is skipped if the user exists; `usermod -aG sudo` is idempotent; `chpasswd` always reapplies the supplied password.
- `20-groups` — `usermod -aG` is idempotent.
- `30-passwordless-sudo` — content is compared to the existing file; `visudo -c` validates before write.
- `40-profile` — the PATH block is wrapped in stable BEGIN/END markers; if both markers are present, the content between them is compared to the canonical snippet and the file is left alone when they match.
- `50-docker` — `apt-get install -y` is idempotent; `daemon.json` is rewritten each run.
- `55-lazydocker` — version is detected; reinstall only on mismatch.
- `59-gh-cli` — the official APT keyring and repository are compared before write; package installation is idempotent. Authentication remains a separate per-user operation.
- `60-caddy` — syncs stack files with compare-before-write; idempotent seeding of `.env`; rendered Caddyfile compared before write; reconcile hash-skip avoids redundant `/load` pushes. Runs as the deploy user (docker group); `cscli` bouncer-key generation is idempotent and fail-open. **Never starts a stopped container** — bringing up the edge is an explicit operator action; updates apply in place only when it is already running.
- `10-llmdocs` / `30-scripts` — rewrites wrappers each run; no state to track.
- `20-python` — `uv --version`, `uv python list --only-installed` are each checked; sub-tools that match are skipped.
- `36-kilo` — resolves `@kilocode/cli@latest` through npm, removes legacy native and nvm-local Kilo installs, and verifies the installed package version.
- `37-kilo-settings` — updates managed agents, commands, rules, and skills with `sync_dir_preserve`; destination-only additions survive. The global privilege rule therefore reaches existing hosts. `kilo.json` and `kilo.jsonc` are copied only when absent; customized files receive a diff and must be merged manually so accumulated permissions are preserved.

---

## Origin / split history

`bootstrap.sh` was a single 90-line script doing apt update, baseline
package install, and deploy-user creation. The host-provisioning
steps it grew into (groups, packages, passwordless sudo, docker,
lazydocker) were lifted out of the application repos that had been
handing them and merged into `init.d/` here, leaving `bootstrap` as
the canonical home for everything that needs root.

Per-user tooling (`llmdocs/`, `scripts/`, the kilo CLI, `vscode/`)
was originally placed directly under
`bootstrap/` and a `60-kilo-tooling/` step installed it from
there. That mixed root-tier and user-tier concerns in one repo:
host state and developer workspace state lived in the same tree.
The split into `user/` puts per-user installs in a
runner that is required NOT to run as root, returning the root
tier to a pure host-provisioning role.
