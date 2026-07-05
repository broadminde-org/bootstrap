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
`systemctl` and `docker`, Docker CE is installed, and `lazydocker` is
dropped into the deploy user's `~/.local/bin/`.

After the root tier finishes, log in as the deploy user and run the
**user tier** (`./user-bootstrap/init.sh`). It installs per-user
tooling into `$HOME/.local/bin/` — `uv`, a uv-managed Python, the
`kilo` CLI, and wrappers for the `kilo-session-report.py` and
`llmdocs` frameworks that ship in this repo.

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

## Layout

```
bootstrap/
├── init.sh                          # ROOT-tier runner — picks up init.d/<NN>-* as root
├── init.d/
│   ├── lib/
│   │   ├── env.sh                   # sets EE_ROOT=bootstrap, toolchain version pins
│   │   └── common.sh                # root check + DEBIAN_FRONTEND / NEEDRESTART_MODE exports
│   ├── 01-apt-update-upgrade/       # apt-get update + upgrade -y
│   ├── 05-packages/                 # git, curl, wget, vim, htop, unzip, ca-certificates, sudo,
│   │   └── packages.txt             #   gnupg, gettext-base, jq, openssl
│   ├── 10-create-deploy-user/       # useradd + chpasswd + sudo group (idempotent)
│   ├── 20-groups/                   # SUDO_USER → groups from groups.txt
│   │   └── groups.txt               # adm, docker, sudo, systemd-journal
│   ├── 30-passwordless-sudo/        # writes /etc/sudoers.d/99-<user>-passwordless
│   │   └── commands.txt             # /usr/bin/systemctl *, /usr/bin/docker, /usr/bin/docker compose
│   ├── 50-docker/                   # installs Docker CE + Compose plugin, writes daemon.json
│   └── 55-lazydocker/               # drops lazydocker into $SUDO_USER/.local/bin/
├── user-bootstrap/                  # USER-tier — runs as the deploy user, not as root
│   ├── init.sh                      # user-tier runner — refuses root
│   ├── init.d/
│   │   ├── lib/
│   │   │   ├── env.sh               # sets EE_ROOT=user-bootstrap, uv/python/kilo pins
│   │   │   └── common.sh            # non-root check + sources env.sh
│   │   ├── 10-llmdocs/              # installs `llmdocs` wrapper at $HOME/.local/bin/
│   │   ├── 20-tooling/              # installs uv, uv-managed Python, kilo CLI
│   │   └── 30-kilo-session-report/  # installs `kilo-session-report` wrapper
│   ├── llmdocs/                     # stdlib-only Python docs framework (moved here)
│   ├── kilo-session-report.py       # Kilo session analyzer (moved here)
│   ├── netbird/opencode/            # opencode agent config (placeholder — no init.d step yet)
│   └── vscode/                      # workspace VS Code recommendations + settings
├── LICENSE
└── README.md
```

### Tier-privilege model

- **Root tier** (`./init.sh`) — refuses to run as non-root. Steps
  `20-groups`, `30-passwordless-sudo`, and `55-lazydocker` require
  `SUDO_USER` to be set (i.e., invoked via `sudo`); the rest work as
  plain root.
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
- `50-docker` — `apt-get install -y` is idempotent; `daemon.json` is rewritten each run.
- `55-lazydocker` — version is detected; reinstall only on mismatch.
- `10-llmdocs` / `30-kilo-session-report` — rewrites the wrapper each run; no state to track.
- `20-tooling` — `uv --version`, `uv python list --only-installed`, and `kilo --version` are each checked; sub-tools that match are skipped.

---

## Origin / split history

`bootstrap.sh` was a single 90-line script doing apt update, baseline
package install, and deploy-user creation. The host-provisioning
steps it grew into (groups, packages, passwordless sudo, docker,
lazydocker) were lifted out of the application repos that had been
handing them and merged into `init.d/` here, leaving `bootstrap` as
the canonical home for everything that needs root.

Per-user tooling (`llmdocs/`, `kilo-session-report.py`, the kilo
CLI, `netbird/opencode/`, `vscode/`) was originally placed directly
under `bootstrap/` and a `60-kilo-tooling/` step installed it from
there. That mixed root-tier and user-tier concerns in one repo:
host state and developer workspace state lived in the same tree.
The split into `user-bootstrap/` puts per-user installs in a
runner that is required NOT to run as root, returning the root
tier to a pure host-provisioning role.
