# bootstrap

Host provisioning for fresh cloud VPSes.

This repo is split into **two tiers** that run in sequence:

| Tier   | Runs as | Runner               | Location                       |
|--------|---------|----------------------|--------------------------------|
| root   | root    | `./init.sh`          | top-level `bootstrap/`         |
| user   | user    | `./user-bootstrap/init.sh` | top-level `user-bootstrap/` |

The **root tier** turns a stock Debian/Ubuntu box into a deploy-ready
host: apt is updated, a baseline sysadmin toolset is installed, a
non-root deploy user is created with `sudo` membership, common dev/
ops packages are added, passwordless sudo is configured for
`systemctl` and `docker`, SSH is hardened, ufw is staged, fail2ban is
installed, and — depending on the capability flags set in
`bootstrap.conf.yml` — Docker CE, KVM, and CrowdSec are installed.

After the root tier finishes, log in as the deploy user and run the
**user tier** (`./user-bootstrap/init.sh`). It installs per-user
tooling into `$HOME/.local/bin/` — `uv`, a uv-managed Python, the
`kilo` CLI, Go toolchain, Node.js, direnv, and wrappers for the
`llmdocs` and user scripts that ship in this repo. The entire
user tier is gated behind the `dev` capability flag.

After both tiers finish, individual apps (e.g. `apps/<app>/` in
their own repository) take over and run their own `init.sh` as the
deploy user.

---

## Quick start

```bash
# ---- root tier (as root on a freshly provisioned VPS) ----
apt-get install -y git
git clone https://github.com/<your-org>/bootstrap.git
cd bootstrap

# Configure capabilities for this host.
cp example.bootstrap.conf.yml bootstrap.conf.yml
# Edit bootstrap.conf.yml — set docker, kvm, dev, public to true/false.
$EDITOR bootstrap.conf.yml

sudo BOOTSTRAP_USER=luke BOOTSTRAP_PASSWORD='…' ./init.sh

# ---- log out, log back in as the deploy user ----
cd bootstrap/user-bootstrap
./init.sh

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

## Capability flags

`bootstrap.conf.yml` controls which provisioning steps run. Each step
in `init.d/` may declare required capabilities via a `.requires` file;
steps without one always run. A step is skipped when **any** of its
required capabilities is disabled.

| Capability | Steps gated | Default |
|---|---|---|
| `docker` | 50-docker, 55-lazydocker | `true` |
| `kvm` | 57-kvm | `false` |
| `dev` | 40-profile + all 6 user-tier steps | `false` |
| `public` | 54-crowdsec | `false` |

Always-run steps (no `.requires`): 01-apt, 05-packages, 10-user,
20-groups, 30-sudo, 51-ssh-hardening, 52-ufw, 53-fail2ban, 56-ssh-client.

If `bootstrap.conf.yml` is missing, every capability is treated as
enabled — backward-compatible with hosts that predate the capability
system.

### Example configurations

**Public app server** (Docker + CrowdSec, no dev tooling, no VMs):
```yaml
capabilities:
  docker: true
  kvm: false
  dev: false
  public: true
```

**Internal build server** (Docker + KVM + full dev toolchain):
```yaml
capabilities:
  docker: true
  kvm: true
  dev: true
  public: false
```

**Minimal private host** (bare baseline, no Docker, no extras):
```yaml
capabilities:
  docker: false
  kvm: false
  dev: false
  public: false
```

---

## Layout

```
bootstrap/
├── bootstrap.conf.yml                # capability flags (copy from example)
├── example.bootstrap.conf.yml        # template — unconfigured
├── init.sh                           # ROOT-tier runner — picks up init.d/<NN>-* as root
├── init.d/
│   ├── lib/
│   │   ├── env.sh                    # sets EE_ROOT=bootstrap, toolchain version pins
│   │   ├── common.sh                 # root check + DEBIAN_FRONTEND / NEEDRESTART_MODE exports
│   │   └── caps.sh                   # capability-gating: load_caps, step_requires_caps
│   ├── 01-apt-update-upgrade/        # apt-get update + upgrade -y
│   ├── 05-packages/                  # git, curl, wget, vim, htop, unzip, ca-certificates, sudo,
│   │   └── packages.txt              #   gnupg, gettext-base, jq, openssl, direnv, build-essential
│   ├── 10-create-deploy-user/        # useradd + chpasswd + sudo group (idempotent)
│   ├── 20-groups/                    # SUDO_USER → groups from groups.txt
│   │   └── groups.txt                # adm, docker, sudo, systemd-journal, kvm, libvirt
│   ├── 30-passwordless-sudo/         # writes /etc/sudoers.d/99-<user>-passwordless
│   │   └── commands.txt              # /usr/bin/systemctl *, /usr/bin/docker, /usr/bin/docker compose
│   ├── 40-profile/                   # writes bootstrap-managed PATH block to $SUDO_USER/.profile
│   │   └── profile.snippet           # idempotent ~/.local/bin + ~/.kilo/bin PATH block
│   ├── 50-docker/                    # installs Docker CE + Compose plugin, writes daemon.json
│   ├── 51-ssh-hardening/             # PermitRootLogin no, X11Forwarding no, AllowUsers
│   ├── 52-ufw/                       # ufw install + rule staging (does NOT enable)
│   ├── 53-fail2ban/                  # fail2ban with sshd + Caddy jails
│   ├── 54-crowdsec/                  # CrowdSec LAPI + iptables bouncer
│   ├── 55-lazydocker/                # drops lazydocker into $SUDO_USER/.local/bin/
│   ├── 56-ssh-client/                # SSH client defaults + ControlMaster cleanup
│   └── 57-kvm/                       # qemu-kvm, libvirt, virtinst, bridge-utils
├── user-bootstrap/                   # USER-tier — runs as the deploy user, not as root
│   ├── init.sh                       # user-tier runner — refuses root
│   ├── init.d/
│   │   ├── lib/
│   │   │   ├── env.sh                # sets EE_ROOT=user-bootstrap, uv/python/kilo pins
│   │   │   └── common.sh             # non-root check + sources env.sh
│   │   ├── 10-llmdocs/               # installs `llmdocs` wrapper at $HOME/.local/bin/
│   │   ├── 15-direnv/                # direnv bashrc hook + profile-level direnvrc scaffold
│   │   ├── 20-tooling/               # installs uv, uv-managed Python, kilo CLI
│   │   ├── 25-go/                    # installs Go toolchain + dev tools
│   │   ├── 30-scripts/               # copies scripts/→$HOME/scripts/, runners→$HOME/.local/bin/
│   │   └── 35-node/                  # installs Node.js via nvm + global npm packages
│   ├── llmdocs/                      # stdlib-only Python docs framework (moved here)
│   ├── scripts/                      # user scripts (e.g., kilo-session-report.py)
│   ├── script-runners/               # thin wrappers deployed to $HOME/.local/bin/
│   ├── opencode/                     # opencode agent config (placeholder — no init.d step yet)
│   ├── sync-kilo-context.sh          # copies live ~/.config/kilo context into opencode/
│   └── vscode/                       # workspace VS Code recommendations + settings
├── LICENSE
└── README.md
```

### Tier-privilege model

- **Root tier** (`./init.sh`) — refuses to run as non-root. Steps
  `20-groups`, `30-passwordless-sudo`, `40-profile`, and
  `55-lazydocker` require `SUDO_USER` to be set (i.e., invoked via
  `sudo`); the rest work as plain root.
- **User tier** (`./user-bootstrap/init.sh`) — refuses to run as
  root. All steps operate on `$HOME` and need no privilege
  escalation.

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
- `10-llmdocs` / `30-scripts` — rewrites wrappers each run; no state to track.
- `20-tooling` — `uv --version`, `uv python list --only-installed`, and `kilo --version` are each checked; sub-tools that match are skipped.

---

## Origin / split history

`bootstrap.sh` was a single 90-line script doing apt update, baseline
package install, and deploy-user creation. The host-provisioning
steps it grew into (groups, packages, passwordless sudo, docker,
lazydocker) were lifted out of the application repos that had been
handing them and merged into `init.d/` here, leaving `bootstrap` as
the canonical home for everything that needs root.

Per-user tooling (`llmdocs/`, `scripts/`, the kilo CLI,
`opencode/`, `vscode/`) was originally placed directly under
`bootstrap/` and a `60-kilo-tooling/` step installed it from
there. That mixed root-tier and user-tier concerns in one repo:
host state and developer workspace state lived in the same tree.
The split into `user-bootstrap/` puts per-user installs in a
runner that is required NOT to run as root, returning the root
tier to a pure host-provisioning role.
