# Plan: Herdr Core user-tier bootstrap

Date: 2026-11-08
Status: draft for refinement in a new session; not implemented

## Goal

Install the `hc`/herdr-core CLI for the non-root bootstrap user on macOS and
Debian/Ubuntu, without disrupting an existing installation or running terminals
on an ordinary bootstrap rerun. Installation is the scope; connecting machines,
starting agent terminals, and configuring Kilo to use `hc` are not.

## Evidence and current state

- Upstream: <https://herdr.dev/core/> and
  <https://github.com/herdrdev/herdr-core>. The official installer is
  <https://releases.herdr.dev/core/install.sh>; its release manifest is
  <https://releases.herdr.dev/core/latest.json>.
- The installer supports Linux/macOS on x86_64 and aarch64 (macOS `arm64`). It
  installs to `~/.local/bin/herdr-core`, adding `hc` there only if the name is
  free. On macOS, a bundled app may be installed under
  `~/.local/share/herdr-core` and the bin entries point to that app. The
  installer checks the archive's SHA-256 against its HTTPS-served manifest; on
  the macOS bundled-app path it verifies the app's code signature. The
  manifest is not independently signed.
- The installer can update an existing binary and restart Core. Do not treat
  rerunning it unconditionally as idempotent. `HC_VERSION=X.Y.Z` requests an
  exact release manifest; `hc update --version X.Y.Z` has different semantics
  (at least that version), so do not substitute the latter for an exact pin.
- On this Mac (Darwin/arm64), `~/.local/bin/hc` and `herdr-core` are symlinks
  to the Herdr Core app. Installed version and the release manifest were both
  0.1.19 on 2026-11-08; `hc server status` showed a running Core with one live
  terminal. No installer or update was executed during investigation.
- `user/init.sh` runs steps as a non-root user. `user/init.d/12-bashrc` already
  puts `~/.local/bin` on PATH for Linux Bash and macOS zsh; no new rc-file
  block is needed. `init.d/05-packages` supplies curl on Linux; verify tar in
  the step rather than assuming it is installed everywhere.
- Upstream security model: Core starts when needed, runs commands with its
  user's privileges, and exposes a local Unix socket, not a public port.
  Machine connections use SSH and grant clients access as the remote account.
  See <https://github.com/herdrdev/herdr-core/blob/master/docs/security.md>
  and <https://github.com/herdrdev/herdr-core/blob/master/docs/machines.md>.

## Proposed implementation

1. Add `user/init.d/39-herdr-core/run.sh` (directory step, Bash,
   `set -euo pipefail`). Source `../lib/common.sh` for the non-root guard and
   resolved bootstrap config. No `.requires`: like the other core user CLIs,
   install for every user-tier host, unless that policy changes in review.
   There is no need for a runner change or a separate macOS script.
2. Support `versions.herdr_core: "latest"` or an exact `X.Y.Z` pin via
   `get_pinned_version herdr_core latest`, with an optional
   `HERDR_CORE_VERSION` environment override. Validate the value before
   network/install operations. Do not add partial-version resolution unless
   there is a concrete use case; upstream's `HC_VERSION` accepts an exact
   release. Resolve `latest` from upstream's manifest to a concrete version.
3. Check `curl`, `tar`, and a working SHA-256 utility (the upstream installer
   uses `sha256sum` or `shasum -a 256`). Read the version from the
   bootstrap-owned `~/.local/bin/herdr-core` executable rather than trusting
   any unrelated `hc` on PATH. If it equals the target, exit without downloading
   the archive or restarting Core. If a newer installed version would be
   downgraded by the selected pin or a stale `latest` manifest, fail clearly
   and leave it untouched. Inspect ownership/name collisions before installing:
   do not silently replace a package-managed `hc` or report success if a
   different `hc` shadows the installed binary.
4. For a missing or older version, download the upstream installer into a
   temporary directory, invoke it with `HC_VERSION=<resolved exact version>`
   and the default user-home install location, then clean up temporary files.
   Do not pipe downloaded shell directly into `sh`. Use its built-in archive
   checksum and macOS signing/update behavior rather than reimplementing the
   bundle installer. An actual version change may restart Core while keeping
   running terminals; report that clearly.
5. Verify `~/.local/bin/herdr-core --version` reports the target and that
   `hc` resolves to that installation rather than an unrelated command.
   Do not invoke `hc ls`, `hc server start`, or `hc machine add` as verification:
   those can start a Core or alter runtime state. Do not overwrite Herdr config,
   templates, state, socket directories, or existing terminals.
6. Document the new step and optional pin in `README.md`, `docs/codemap.md`,
   `AGENTS.md`, and `example.bootstrap.conf.yml`. No new capability is planned;
   if the policy changes to opt-in, update every host conf explicitly and the
   capability maps as required by `AGENTS.md`.

## Verification after implementation

- Run `bash -n` and `shellcheck` on the new step; inspect `git diff` for only
  the intended step and documentation changes.
- On this Mac, run `./user/init.sh 39-herdr-core` with a matching pin or
  `latest`; verify it skips and `hc server status` still shows the same running
  Core/terminal. Do not use this live Mac to test a forced downgrade or upgrade.
- On a disposable Linux x86_64 or aarch64 VM, test a fresh install, the
  single-step selector, a second no-op run, and `./user/init.sh --from 39`.
  Test a deliberate version upgrade only in a disposable environment with a
  live terminal, checking that it survives the Core restart.
- Check behavior when `hc` is an unrelated executable, when the manifest or
  installer is unavailable, and for an unsupported OS/architecture. Fail
  without claiming success or touching user state on those paths.

## Decisions to revisit

- Confirm whether Herdr Core should be unconditional on every user-tier host
  (proposed) or gated by a new explicit capability. Do not silently reuse
  `dev`: it currently gates a different set of optional tooling.
- Decide whether bootstrap should enforce a configured older exact pin by
  failing (proposed) or simply preserve the newer installation with a warning.
- Confirm whether later integration with Kilo's agent workflows warrants a
  separate task. This plan only installs the runtime; it does not make Kilo
  sessions run under `hc` or auto-register VPSes on the Mac.
