# Plan: macOS compatibility for bootstrap

Date: 2026-09-26
Status: approved design, not yet implemented

## Goal

Make the bootstrap repo usable on an Apple Silicon MacBook (macOS, bash 5.3
present, default shell zsh) without disturbing the working Debian/Ubuntu VPS
path.

## Key decisions (from review + user direction)

- **No zsh scripts anywhere.** Host has bash 5.3, so both `init.sh` runners
  stay bash. zsh only matters as an *rc-file target* (`.zshrc`/`.zprofile`).
- **Wholesale rewrites become `run.macos.sh`** siblings inside existing
  directory steps. Runner dispatches on `uname -s`. No per-step forking of
  steps that only need tweaks.
- **Portable in-step fixes, not coreutils gnubin.** Brew coreutils installs
  `g`-prefixed binaries (`gsha256sum`, `gstat`, `gtimeout`) and does not
  cover `sed`/`find`/`getent` at all, so each affected user-tier step is
  made portable in place rather than relying on PATH shims.
- **Root tier on macOS is tiny**: brew packages + gh-cli. Everything else
  (01, 06, 10, 20, 30, 40, 45, 50, 51, 52, 53, 54, 55, 56, 57, 58) never
  runs — sshd hardening / fail2ban / crowdsec / ufw / kvm / mdns are
  server-only concerns; user creation and sudoers don't apply to a laptop.
- **Docker needs nothing**: the MacBook uses a brew-installed docker wrapper,
  outside this repo's scope. 50-docker stays Linux-only.
- **`60-caddy` stays disabled on macOS** via its existing `docker,caddy`
  `.requires` — no changes.

## Work items

### 1. Runner dispatch (root `init.sh` only)

- Detect `uname -s == Darwin`.
- **Relax the prerequisite check on Darwin**: the root runner hard-requires
  `apt-get` in its prerequisite loop (`init.sh`). On Darwin, skip `apt-get`
  and require only `curl find xargs` (or skip the check entirely) — otherwise
  `sudo ./init.sh` fails before any dispatch.
- Directory steps may carry `run.macos.sh`; on Darwin prefer it over `run.sh`.
- **Root tier on Darwin**: only steps that have a `run.macos.sh` run at all
  (this is the skip mechanism for the 16 Linux-only steps).
- **User tier**: `user/init.sh` needs no change — normal capability gating is
  unchanged and steps are dual-pathed in-step (no `run.macos.sh` files there).

### 2. Root tier macOS variants

- `init.d/05-packages/run.macos.sh` + `packages.macos.txt`:
  - `brew install` / `brew install --cask` list.
  - Must include the prereqs the user tier silently assumes (apt-provided on
    Debian): `jq`, `direnv`, `gh`, `shellcheck`, `ripgrep`, plus sensible
    basics (git, curl, wget, vim, htop, unzip, tmux, rsync, gnupg).
  - **Do not rely on brew coreutils to paper over GNU-isms.** Brew coreutils
    installs `g`-prefixed binaries (`gsha256sum`, `gstat`, `gtimeout`), and
    `sed -i` / `find -printf` / `getent` come from `gnu-sed` / `findutils` /
    glibc — not coreutils at all. Each affected step is made portable in
    place instead (see §3). `coreutils` may still be installed for
    convenience, but nothing depends on its gnubin being on PATH.
  - Xcode CLT note (`xcode-select --install`) as build-essential equivalent.
  - Consider folding gh-cli in here and skipping a `59-gh-cli/run.macos.sh`.
- `init.d/59-gh-cli/run.macos.sh` (optional, only if not folded into 05):
  `brew install gh`.

### 3. User tier in-step tweaks (no forks)

- `25-go/run.sh`: add an `OS` variable (`uname -s` → lowercase
  `darwin`/`linux`) and an `arm64) GOARCH="arm64"` case — today only
  `x86_64`/`aarch64` are handled, so Apple Silicon currently errors.
  Tarball `go${V}.${OS}-${ARCH}.tar.gz`. Checksum via `shasum -a 256`
  fallback when `sha256sum` is absent. Replace the bare `sed -i` calls
  (lines 167, 168, 256) with a portable form (`sed -i ''` on Darwin,
  `sed -i` on Linux) — BSD sed rejects the GNU spelling. Also write the env
  block to `.zprofile` on Darwin.
- `38-woodpecker-cli/run.sh`: same OS/arch case — add `arm64→arm64` plus an
  `OS` variable; asset `woodpecker-cli_${OS}_${ARCH}.tar.gz` (upstream
  publishes `darwin_arm64`/`darwin_amd64` — verified). Checksum via
  `shasum -a 256` fallback.
- `12-bashrc`, `15-direnv`, `35-node`: also write `.zshrc` (direnv uses
  `direnv hook zsh`; nvm/PATH blocks likewise) and `.zprofile` where the
  block is a login-shell concern.
- **Replace 40-profile's PATH block on macOS.** `40-profile` is root-tier and
  Linux-only, so nothing puts `~/.local/bin` + `~/.kilo/bin` on PATH for zsh.
  Assign `12-bashrc` to also write the same PATH block to `~/.zshrc` (and
  `~/.zprofile`) on Darwin — this is the concrete macOS substitute.
- `98-npm-shared`: use `stat -f %Lp` on Darwin (returns exactly `600`,
  matching the existing `== 600` comparison); keep `stat -c %a` on Linux.
- `99-go-shared`: replace `timeout 15` with a portable re-exec (`gtimeout` if
  present, else run without a timeout). Also: root-tier 56-ssh-client doesn't
  run on macOS, so ensure `~/.ssh/config` has the
  `Include ~/.ssh/hosts.d/*` line (handle per-user in this step).
- **30-scripts payload** carries GNU-isms that coreutils does not fix:
  `find -printf` (`scripts/maintain.d/run.sh:153`), `getent`
  (`scripts/lib/maintain-common.sh:129`), `timeout`
  (`scripts/dev.d/50-vite.sh:54`), `readlink -f`
  (`scripts/lib/retention.sh:63`, already degrades via `|| echo ""`). Make
  these portable (BSD `find` alternative, `$HOME`/`dscl` instead of `getent`,
  timeout fallback) rather than assuming brew covers them.
- Optional: small `init.d/lib/os.sh`-style helper sourced by user tier for
  `OS`/`ARCH` detection + `sha256` shim, to avoid repeating the case
  statement.

### 4. Docs

- `AGENTS.md`: document the `run.macos.sh` convention — directory steps may
  carry one; root tier on Darwin runs only steps that have one; user tier
  dual-paths in-step.
- `example.bootstrap.conf.yml`: annotate macOS host expectations — `dev: true`
  (for 98/99) with `docker/caddy/kvm/public/woodpecker: false`. Because the
  conf file is gitignored and unlisted capabilities are disabled, a macOS
  host must create `bootstrap.conf.yml` (or `<mac-hostname>.conf.yml`) with
  this minimal set before the user tier runs, or 98/99 silently skip.
- `docs/codemap.md` if it enumerates runner behavior.

## Explicitly out of scope

- macOS versions of: deploy-user creation, sudoers, sshd, ufw, fail2ban,
  crowdsec, kvm, mdns, docker, lazydocker, playwright-deps, woodpecker-local,
  ssh-client, profile, groups, apt-update.
- 60-caddy (disabled on macOS hosts).
- Any changes to the Linux `run.sh` behavior beyond additive Darwin branches.

## Verification

- Create the macOS host conf first: copy `example.bootstrap.conf.yml` to
  `bootstrap.conf.yml` (or `<mac-hostname>.conf.yml`) with `dev: true` and
  `docker/caddy/kvm/public/woodpecker: false`.
- Run `sudo ./init.sh` (root tier) on the MacBook: only 05-packages (and
  possibly 59-gh-cli) execute.
- Run `./user/init.sh` as the user: 10–40 steps succeed on darwin/arm64;
  98/99 run (with `dev`); 60-caddy stays skipped.
- Re-run a Linux VM smoke test (single-step + `--from`) to confirm no
  regression.
