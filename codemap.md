# Bootstrap — Codemap

## System Overview

Bootstrap is a two-tier provisioning system for fresh cloud VPSes (Debian/Ubuntu). The root tier (`bootstrap/init.sh`) transforms a stock machine into a deploy-ready host: apt is updated, baseline packages are installed, a non-root deploy user is created with sudo membership, Docker CE with IPv6 is configured, SSH is hardened (server + client), ufw/fail2ban/crowdsec are installed, and `lazydocker` is dropped into the user's `~/.local/bin/`. The user tier (`user/init.sh`) runs as the deploy user and installs per-user tooling: `direnv` bashrc hook, `uv` with a uv-managed Python interpreter, the `kilo` CLI, Go toolchain with dev tools, Node.js via nvm with global npm packages, and wrapper scripts for `llmdocs` and `kilo-session-report`. After both tiers complete, app repositories (e.g. `netbird-docker`, `ansible`) run their own `init.sh` scripts as the deploy user and assume all bootstrap outputs — the deploy user, Docker, groups, PATH entries, and installed tooling — are already in place.

## Tier Model

```mermaid
flowchart TD
    A["Fresh VPS (root only)"] --> B["Root Tier: bootstrap/init.sh"]
    B --> C["01-apt-update-upgrade"]
    B --> D["05-packages"]
    B --> E["10-create-deploy-user"]
    B --> F["20-groups"]
    B --> G["30-passwordless-sudo"]
    B --> H["40-profile"]
    B --> I["50-docker"]
    B --> J["51-ssh-hardening"]
    B --> K["52-ufw"]
    B --> L["53-fail2ban"]
    B --> M["54-crowdsec"]
    B --> N["55-lazydocker"]
    B --> N2["56-ssh-client"]

    N2 --> O["Log in as deploy user"]
    O --> P["User Tier: user/init.sh"]
    P --> Q["10-llmdocs"]
    P --> Q2["15-direnv"]
    P --> R["20-python"]
    P --> R1b["22-kilo"]
    P --> R2["25-go"]
    P --> S["30-scripts"]
    P --> S2["35-node"]

    S2 --> T["Hand off to app repos"]
    T --> U["netbird-docker/init.sh"]
    T --> V["ansible / other app init.sh"]

    style B fill:#e8f5e9
    style P fill:#e3f2fd
    style U fill:#fff3e0
    style V fill:#fff3e0
```

### Tier Privilege Model

| Aspect | Root Tier | User Tier |
|---|---|---|
| Runner | `bootstrap/init.sh` | `user/init.sh` |
| Runs as | root (via `sudo`) | deploy user (non-root) |
| Refuses | non-root (`EUID != 0`) | root (`EUID == 0`) |
| Steps requiring `SUDO_USER` | `20-groups`, `30-passwordless-sudo`, `40-profile`, `55-lazydocker`, `56-ssh-client` | none |
| Install target | `/etc`, `/usr`, system services | `$HOME/.local/bin/`, `$HOME/.local/share/`, `$HOME/.local/go/`, `$HOME/.nvm/` |
| lib/ | `init.d/lib/conf.sh` (unified config reader), `init.d/lib/env.sh` (EE_ROOT), `init.d/lib/common.sh` (root check, apt env vars) | `init.d/lib/common.sh` (non-root check, sources conf.sh, exports version pins) |

### Pipeline Flow

```mermaid
flowchart LR
    subgraph Root["Root Tier (bootstrap/init.sh)"]
        direction TB
        R1["01 apt update + upgrade"]
        R2["05 baseline packages"]
        R3["10 create deploy user"]
        R4["20 group membership"]
        R5["30 passwordless sudo"]
        R6["40 profile PATH block"]
        R7["50 Docker CE + IPv6"]
        R8["51 SSH hardening"]
        R9["52 ufw staging"]
        R10["53 fail2ban"]
        R11["54 crowdsec"]
        R12["55 lazydocker"]
        R13["56 SSH client defaults"]
        R1 --> R2 --> R3 --> R4 --> R5 --> R6 --> R7 --> R8 --> R9 --> R10 --> R11 --> R12 --> R13
    end

    subgraph User["User Tier (user/init.sh)"]
        direction TB
        U1["10 llmdocs wrapper"]
        U2["15 direnv hook"]
        U3["20 uv + Python"]
        U3b["22 kilo CLI"]
        U4["25 Go toolchain"]
        U5["30 scripts + runners"]
        U6["35 Node.js via nvm"]
        U1 --> U2 --> U3 --> U3b --> U4 --> U5 --> U6
    end

    subgraph Apps["App Repos"]
        direction TB
        A1["netbird-docker/init.sh"]
        A2["ansible / others"]
    end

    Root -->|"log in as deploy user"| User
    User -->|"both tiers done"| Apps
```

## Root-Tier Step Ownership Table

| Step | Type | What It Installs / Configures | Idempotency Behavior |
|---|---|---|---|
| `01-apt-update-upgrade` | dir | `apt-get update` + `apt-get upgrade -y` | No-op when packages are up to date |
| `05-packages` | dir | Installs packages from `packages.txt`: git, curl, wget, vim, htop, unzip, dnsutils, ca-certificates, sudo, gnupg, gettext-base, jq, openssl, direnv, build-essential | `apt-get install -y` is a no-op when satisfied; `--force-confdef`/`--force-confold` preserve local config edits |
| `10-create-deploy-user` | dir | Creates deploy user via `useradd -m -s /bin/bash -G sudo`; sets password via `chpasswd` | `useradd` skipped if user exists; `usermod -aG sudo` is idempotent; `chpasswd` always reapplies |
| `20-groups` | dir | Adds `SUDO_USER` to groups from `groups.txt`: adm, docker, sudo, systemd-journal | `groupadd -f` is no-op when group exists; `usermod -aG` is idempotent |
| `30-passwordless-sudo` | dir | Writes `/etc/sudoers.d/99-<user>-passwordless` granting NOPASSWD for: `/usr/bin/systemctl *`, `/usr/bin/docker`, `/usr/bin/docker compose` | Content compared to existing file; skipped if identical; validated with `visudo -c` before write |
| `40-profile` | dir | Writes bootstrap-managed PATH block to `$SUDO_USER/.profile` adding `$HOME/.local/bin` and `$HOME/.kilo/bin` to PATH | Wrapped in BEGIN/END markers; existing block compared and skipped if matching; lone markers cause error; non-marker content preserved |
| `50-docker` | dir | Installs Docker CE, docker-ce-cli, containerd.io, docker-buildx-plugin, docker-compose-plugin from Docker upstream apt repo; writes `/etc/docker/daemon.json` (iptables, ip6tables, userland-proxy off, IPv6 with fixed-cidr-v6); writes `/etc/sysctl.d/99-docker-ipv6.conf`; enables/starts docker | `apt-get install -y` is idempotent; `daemon.json` rewritten each run; does NOT restart running docker (manual restart required after config change) |
| `51-ssh-hardening` | dir | Patches `/etc/ssh/sshd_config` (PermitRootLogin no, X11Forwarding no); installs `/etc/ssh/sshd_config.d/60-hardening.conf` (PermitRootLogin no, X11Forwarding no, AllowUsers stack, MaxAuthTries 3, LoginGraceTime 20); reloads sshd | `sed -i` only replaces when insecure defaults present; drop-in overwritten each run; post-condition assertions via `sshd -T` |
| `52-ufw` | dir | Disables LLMNR via `/etc/systemd/resolved.conf.d/no-llmnr.conf`; installs ufw; stages rules: default deny incoming, allow outgoing, SSH from 170.203.0.0/16, deny 5355 TCP/UDP; does NOT enable ufw | `ufw rule` commands are idempotent (skip existing); drop-in overwritten each run |
| `53-fail2ban` | dir | Installs fail2ban; writes `/etc/fail2ban/jail.local` (sshd, caddy-auth, netbird-installer jails); writes `/etc/fail2ban/filter.d/caddy-auth.conf` and `netbird-installer.conf`; enables/starts fail2ban | Config files overwritten each run; jails tolerate missing log paths at startup |
| `54-crowdsec` | dir | Registers CrowdSec apt repo via `install.crowdsec.net`; installs crowdsec + crowdsec-firewall-bouncer-iptables; installs crowdsecurity/sshd and crowdsecurity/caddy collections; appends Caddy log path to `/etc/crowdsec/acquis.yaml`; enables/starts both services | Apt repo script overwrites existing sources; `cscli collections install` skips already-installed; acquis.yaml append skipped if path already present |
| `55-lazydocker` | dir | Downloads lazydocker tarball from GitHub, verifies SHA256, installs binary to `$SUDO_USER/.local/bin/lazydocker` | Version detected via `lazydocker --version`; reinstall only on mismatch; pinned at `v0.25.2` |
| `56-ssh-client` | dir | Writes SSH client defaults (`Host *` block) to `$SUDO_USER/.ssh/config` (ServerAliveInterval, ControlMaster, ControlPersist, UpdateHostKeys, HashKnownHosts) with `Include ~/.ssh/hosts.d/*`; adds stale ControlMaster cleanup snippet to `$SUDO_USER/.bashrc` | Marker-guarded in both files; four case handling for .ssh/config (new, patched, user-managed Host*, append); skips when markers present |

**Root-tier step count: 13** (01, 05, 10, 20, 30, 40, 50, 51, 52, 53, 54, 55, 56)

## User-Tier Step Ownership Table

| Step | Type | What It Installs / Configures | Idempotency Behavior |
|---|---|---|---|
| `10-llmdocs` | dir | Writes `$HOME/.local/bin/llmdocs` wrapper: `exec uv run --project <llmdocs dir> python -m llmdocs "$@"` | Wrapper rewritten each run (path may change if repo relocated) |
| `15-direnv` | dir | Adds `eval "$(direnv hook bash)"` to `~/.bashrc`; creates profile-level `~/.config/direnv/direnvrc` scaffold | grep check on bashrc; skip direnvrc if already exists |
| `20-python` | dir | Two sub-installs: (1) `uv` via official installer at `$HOME/.local/bin/uv`, (2) Python via `uv python install` under `~/.local/share/uv/python/` | Each sub-tool independently version-checked; `uv --version`, `uv python list --only-installed`; only mismatched tools are installed |
| `22-kilo` | dir | Installs `kilo` CLI binary at `$HOME/.local/bin/kilo` from GitHub release (arch-aware: x64/arm64, baseline/musl variants, SHA256 verified via release JSON) | Version-checked via `kilo --version`; reinstall only on mismatch |
| `25-go` | dir | Installs Go binary to `~/.local/go/` (pinned via `EE_GO_VERSION`); writes Go shell environment block to `~/.profile` (GOROOT, GOPATH, GOPROXY, GOSUMDB, GOPRIVATE, PATH); installs dev tools (golangci-lint, gosec, govulncheck, air) to `~/go/bin/`; persists go env to `~/.config/go/env`; prunes orphan go toolchain binaries | Version check on `go version`; marker-guarded shell env block with stale cleanup; dev tools re-installed at @latest on every run (go install is fast when already at latest) |
| `30-scripts` | dir | Copies `scripts/` to `$HOME/scripts/`; installs script runners to `$HOME/.local/bin/` (including `kilo-session-report` wrapper) | Files overwritten each run |
| `35-node` | dir | Installs nvm; installs Node.js (pinned via `EE_NODE_VERSION`); adds nvm sourcing to `~/.bashrc`; installs global npm packages from `packages.txt` (including `@playwright/test` with browser deps) | Version check on `node --version`; grep check on bashrc nvm block; per-package check via `npm list -g` |

**User-tier step count: 7** (10, 15, 20, 22, 25, 30, 35)

## User-Tier Tools (20-python + 22-kilo)

### Version Pins

Version pins live in the `versions:` section of `bootstrap.conf.yml` (alongside capability flags). Any tool may be set to `"latest"` to auto-resolve the newest stable release at install time, or pinned to an exact version string. The default pins in `example.bootstrap.conf.yml` are:

| Tool | Default Pin | Env Var | Source | Binary Location |
|---|---|---|---|---|
| `uv` | `latest` | `EE_UV_VERSION` | `https://github.com/astral-sh/uv/releases/download/${EE_UV_VERSION}/uv-installer.sh` | `$HOME/.local/bin/uv` |
| Python (CPython) | `3.13` | `EE_PYTHON_VERSION` | `uv python install` | `~/.local/share/uv/python/cpython-3.13-.../bin/` (not on PATH) |
| `kilo` | `latest` | `KILO_VERSION` | `https://github.com/Kilo-Org/kilocode/releases/download/${KILO_VERSION}/kilo-linux-{x64\|arm64}{-baseline}{-musl}.tar.gz` | `$HOME/.local/bin/kilo` |
| Go | `latest` | `EE_GO_VERSION` | `https://go.dev/dl/go${EE_GO_VERSION}.linux-{amd64\|arm64}.tar.gz` | `$HOME/.local/go/bin/go` |
| Node.js | `latest` | `EE_NODE_VERSION` | nvm (`nvm install ${EE_NODE_VERSION}`) | `$HOME/.nvm/versions/node/v${EE_NODE_VERSION}/bin/node` |

Version pins are read by `init.d/lib/conf.sh` via `get_pinned_version <tool>` and exported as env vars by `user/init.d/lib/common.sh`. Individual steps resolve `"latest"` to a concrete version via their own API calls (GitHub releases JSON, go.dev, nodejs.org). Env var overrides take precedence over the config file.

### Install Details

- **uv**: Downloaded via official `uv-installer.sh` with `--no-modify-path` flag. No apt dependency.
- **Python**: Installed via `uv python install`. Lives under `~/.local/share/uv/python/`. Callers use `uv run` rather than bare `python3`.
- **kilo**: Downloaded from GitHub release JSON with SHA256 verification (digest extracted from `.assets[].digest`). Architecture detection: `x86_64` → `linux-x64`, `aarch64` → `linux-arm64`. AVX2 check on x64 (falls back to `-baseline`). musl check via `/etc/alpine-release` or `ldd --version` (adds `-musl` suffix).
- **Go**: Downloaded tarball from `go.dev/dl`, extracted to `~/.local/go/`. Shell env written to `~/.profile` (marker-guarded, self-healing). Dev tools (golangci-lint, gosec, govulncheck, air) installed via `go install` with `GOTOOLCHAIN=${GO_TOOLCHAIN_PIN}+auto`. `go env -w` persists GOPROXY/GOSUMDB/GOPRIVATE/GOTOOLCHAIN to `~/.config/go/env` for non-interactive shells.
- **Node.js**: nvm is downloaded directly (nvm.sh, nvm-exec, bash_completion from `raw.githubusercontent.com`). Node.js installed via `nvm install` with exact pin. nvm sourcing added to `~/.bashrc`. Global npm packages installed from `packages.txt` with per-package idempotency check. `@playwright/test` gets browser install (`npx playwright install --with-deps`).

### Wrapper Tools (not version-pinned binaries)

| Wrapper | Target | Invocation |
|---|---|---|
| `$HOME/.local/bin/llmdocs` | `user/llmdocs/` framework | `uv run --project <llmdocs root> python -m llmdocs` |
| `$HOME/.local/bin/kilo-session-report` | `user/kilo-session-report.py` | `uv run --script <path>/kilo-session-report.py` |

## Relationship to App Repos

Bootstrap is a **prerequisite** — app repos (`netbird-docker`, `ansible`, etc.) run after both tiers complete and assume the following outputs:

### What Bootstrap Provides

| Output | Consumed By | Details |
|---|---|---|
| Deploy user (from `10-create-deploy-user`) | All app repos | Non-root account with sudo membership; app `init.sh` scripts run as this user |
| Docker CE + Compose plugin (from `50-docker`) | `netbird-docker` | Docker daemon running with IPv6, `daemon.json` configured, `docker compose` available |
| Group membership: docker, adm, sudo, systemd-journal (from `20-groups`) | All app repos | Non-root docker access, log reading without sudo |
| Passwordless sudo for systemctl/docker (from `30-passwordless-sudo`) | App init scripts | Apps can manage services and containers without interactive password prompts |
| `$HOME/.local/bin` on PATH (from `40-profile`) | All app repos + user-tier wrappers | Wrappers installed by user-tier are callable by name |
| SSH client defaults (from `56-ssh-client`) | All app repos | ServerAliveInterval/ControlMaster/ControlPersist for reliable connections; `Include ~/.ssh/hosts.d/*` for per-repo SSH aliases; stale ControlMaster cleanup in bashrc |
| Baseline packages: jq, openssl, gettext-base, curl, git, build-essential (from `05-packages`) | All app repos | `jq` for JSON parsing, `openssl` for secrets, `gettext-base` for `envsubst` template rendering, `curl`/`git` for downloads, `build-essential` for native Node.js modules |
| ufw + fail2ban + crowdsec (from `52-ufw`, `53-fail2ban`, `54-crowdsec`) | `netbird-docker` | fail2ban jails reference `/home/stack/netbird-docker/logs/caddy/access.log`; crowdsec acquis.yaml references the same path |
| SSH hardening (from `51-ssh-hardening`) | All app repos | `AllowUsers stack` restricts SSH access |
| direnv hook (from `15-direnv`) | All app repos with `.envrc` | Per-directory environment loading; profile-level `direnvrc` scaffold for shared functions |
| uv + Python 3.13 (from `20-python`) | `llmdocs`, `kilo-session-report`, app Python tooling | `uv run` is the preferred Python execution method |
| kilo CLI (from `22-kilo`) | Agent-tuner workflow, `kilo-session-report` | Native binary for Kilo sessions |
| llmdocs framework (from `10-llmdocs`) | Docs-source repos | Repo-agnostic docs-to-markdown conversion |
| Go toolchain + dev tools (from `25-go`) | Go app repos | Go binary in `~/.local/go/`, toolchain pin in `~/.profile`, dev tools (golangci-lint, gosec, govulncheck, air) in `~/go/bin/` |
| Node.js + global npm packages (from `35-node`) | SvelteKit frontends, Playwright tests | Node.js via nvm (`EE_NODE_VERSION` pin), `@playwright/test` with browsers pre-installed |

### Execution Order

```mermaid
flowchart LR
    A["bootstrap/init.sh\n(root tier)"] --> B["user/init.sh\n(user tier)"]
    B --> C["netbird-docker/init.sh\n(app tier)"]
    C --> D["ansible / other apps\n(app tier)"]

    style A fill:#e8f5e9
    style B fill:#e3f2fd
    style C fill:#fff3e0
    style D fill:#fff3e0
```

### Completeness Verification

| Tier | Expected Steps | Found in Source | Status |
|---|---|---|---|
| Root (init.d/) | 01, 05, 10, 20, 30, 40, 50, 51, 52, 53, 54, 55, 56 = **13 steps** | 01-apt-update-upgrade, 05-packages, 10-create-deploy-user, 20-groups, 30-passwordless-sudo, 40-profile, 50-docker, 51-ssh-hardening, 52-ufw, 53-fail2ban, 54-crowdsec, 55-lazydocker, 56-ssh-client = **13 steps** | All accounted for |
| User (user/init.d/) | 10, 15, 20, 22, 25, 30, 35 = **7 steps** | 10-llmdocs, 15-direnv, 20-python, 22-kilo, 25-go, 30-scripts, 35-node = **7 steps** | All accounted for |
| **Total** | **20 steps** | **20 steps** | Complete |
