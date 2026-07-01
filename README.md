# bootstrap

Broadminde host provisioning for fresh cloud VPSes.

This repo replaces the original monolithic `bootstrap.sh`. It runs as
**root** (or via `sudo`) and turns a stock Debian/Ubuntu box into a
broadminde-deployable host: apt is updated, a baseline sysadmin toolset
is installed, a non-root deploy user is created with `sudo` membership,
common dev/ops packages are added, passwordless sudo is configured for
`systemctl` and `docker`, Docker CE is installed, and `lazydocker` is
dropped into the deploy user's `~/.local/bin/`.

After `bootstrap` finishes, individual apps (e.g. `apps/netbird`) take
over as the deploy user and run their own `init.d/`.

---

## Quick start

```bash
# As root on a freshly provisioned VPS (Debian 13 / Ubuntu 24.04):
apt-get install -y git
git clone https://github.com/broadminde-org/bootstrap.git
cd bootstrap
sudo BOOTSTRAP_USER=luke BOOTSTRAP_PASSWORD='…' ./init.sh
# … log out and back in as the deploy user, then continue into the app:
cd ../netbird-docker   # or wherever the app repo lives
./init.sh
```

Run a single step (e.g. just Docker) with:

```bash
sudo ./init.sh 50-docker
```

Run everything from a chosen point onward:

```bash
sudo ./init.sh --from 30
```

`./init.sh --help` lists the `--from <NN>` and `<NN>` selectors.

---

## Layout

```
bootstrap/
├── init.sh                          # runner — picks up init.d/<NN>-* in numeric order
├── init.d/
│   ├── lib/
│   │   ├── env.sh                   # sets EE_ROOT=bootstrap, toolchain version pins
│   │   └── common.sh                # root check + DEBIAN_FRONTEND / NEEDRESTART_MODE exports
│   ├── 01-apt-update-upgrade/       # apt-get update + upgrade -y
│   ├── 05-baseline-packages/        # git, curl, wget, vim, htop, unzip, ca-certificates, sudo
│   │   └── packages.txt
│   ├── 10-create-deploy-user/       # useradd + chpasswd + sudo group (idempotent)
│   ├── 20-groups/                   # SUDO_USER → groups from groups.txt
│   │   └── groups.txt               # adm, docker, sudo, systemd-journal
│   ├── 25-packages/                 # common dev/ops apt packages
│   │   └── packages.txt             # gnupg, jq, openssl, gettext-base, openssh-server
│   ├── 30-passwordless-sudo/        # writes /etc/sudoers.d/99-<user>-passwordless
│   │   └── commands.txt             # /usr/bin/systemctl *, /usr/bin/docker, /usr/bin/docker compose
│   ├── 50-docker/                   # installs Docker CE + Compose plugin, writes daemon.json
│   └── 55-lazydocker/               # drops lazydocker into $SUDO_USER/.local/bin/
├── LICENSE
└── README.md
```

### Step privilege model

Every step here runs as **root** (the runner refuses to start
otherwise). Five of the steps (everything after `10-create-deploy-user`)
require `SUDO_USER` to be set — i.e. they must be invoked via `sudo`
so the deploy user gets its groups and sudoers entries applied. Steps
`01`, `05`, and `10` work fine when run as root with no `SUDO_USER`
(they only mutate root-owned state).

### Idempotency

Every step is designed to be safe to re-run:

- `01-apt-update-upgrade` — `apt-get upgrade -y` is a no-op when up to date.
- `05-baseline-packages` / `25-packages` — `apt-get install -y` is a no-op when satisfied.
- `10-create-deploy-user` — `useradd` is skipped if the user exists; `usermod -aG sudo` is idempotent; `chpasswd` always reapplies the supplied password.
- `20-groups` — `usermod -aG` is idempotent.
- `30-passwordless-sudo` — content is compared to the existing file; `visudo -c` validates before write.
- `50-docker` — `apt-get install -y` is idempotent; `daemon.json` is rewritten each run.
- `55-lazydocker` — version is detected; reinstall only on mismatch.

---

## Origin / split history

`bootstrap.sh` was a single 90-line script doing apt update, baseline
package install, and deploy-user creation. The five host-provisioning
steps from `apps/netbird/init.d/` (`01-groups`, `03-packages`,
`05-passwordless-sudo`, `30-docker`, `31-lazydocker`) were lifted out
of that repo and merged into `init.d/` here, leaving `bootstrap` as
the canonical home for everything that needs root.