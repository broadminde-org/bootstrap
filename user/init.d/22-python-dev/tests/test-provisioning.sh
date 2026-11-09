#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
export TEST_FIXTURES="$REPO_ROOT/user/init.d/22-python-dev/tests/fixtures"
[[ "$EUID" != 0 ]] || { echo 'Run these tests as a non-root user.' >&2; exit 1; }
[[ -d "$HOME/.tmpdir" ]] || { echo "${HOME}/.tmpdir must exist." >&2; exit 1; }
scratch="$(mktemp -d "$HOME/.tmpdir/python-provisioning.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

# Only these real steps and libraries are copied: --from never provisions the host.
repo="$scratch/repo"
mkdir -p "$repo/user/init.d/lib" "$repo/init.d/lib" "$scratch/bin"
cp "$REPO_ROOT/user/init.sh" "$repo/user/init.sh"
cp "$REPO_ROOT/user/init.d/lib/common.sh" "$repo/user/init.d/lib/"
cp "$REPO_ROOT/init.d/lib/conf.sh" "$repo/init.d/lib/"
cp "$REPO_ROOT/example.bootstrap.conf.yml" "$repo/"
cp -R "$REPO_ROOT/user/init.d/20-python" "$REPO_ROOT/user/init.d/22-python-dev" "$repo/user/init.d/"
cp "$TEST_FIXTURES/curl" "$scratch/bin/curl"
chmod +x "$scratch/bin/curl"
export PATH="$scratch/bin:/usr/bin:/bin"
export EE_UV_VERSION=0.13.5 EE_PYTHON_VERSION=3.13
export TEST_LOG="$scratch/commands" TEST_STATE="$scratch/state"
export HOME="$scratch/home" XDG_CACHE_HOME="$scratch/cache"
export BOOTSTRAP_CONFIG_FILE="$repo/bootstrap.conf.yml"
mkdir -p "$TEST_STATE" "$HOME/.local/bin" "$XDG_CACHE_HOME"
cp "$TEST_FIXTURES/python" "$TEST_STATE/python"
chmod +x "$TEST_STATE/python"
output="$scratch/output"
checks=0

fail() { echo "FAIL: $*" >&2; cat "$output" >&2; exit 1; }
contains() { grep -Fq -- "$2" "$1" || fail "missing '$2' in $1"; }
absent() { if grep -Fq -- "$2" "$1"; then fail "unexpected '$2' in $1"; fi; }
run_ok() { "$@" > "$output" 2>&1 || fail "command failed: $*"; checks=$((checks + 1)); }
run_fail() { if "$@" > "$output" 2>&1; then fail "command succeeded: $*"; fi; checks=$((checks + 1)); }
config() {
  printf 'capabilities:\n' > "$BOOTSTRAP_CONFIG_FILE"
  [[ "$1" == omitted ]] || printf '  dev: %s\n' "$1" >> "$BOOTSTRAP_CONFIG_FILE"
  printf 'versions:\n  uv: "0.13.5"\n  python: "3.13"\n' >> "$BOOTSTRAP_CONFIG_FILE"
}
reset() {
  rm -f "$HOME/.local/bin/uv" "$HOME/.local/bin/ruff" "$scratch/bin/uv" "$TEST_STATE/receipt"
  : > "$TEST_STATE/managed"
  : > "$TEST_STATE/installs"
  : > "$TEST_LOG"
  unset TEST_CATALOG TEST_CATALOG_FAIL TEST_TOOL_FAIL TEST_PYTHON_INSTALL_FAIL TEST_NO_MANAGED_AFTER_INSTALL TEST_CURL_FAIL TEST_UV_VERSION
  export EE_PYTHON_VERSION=3.13 EE_UV_VERSION=0.13.5
  config true
}
local_uv() { cp "$TEST_FIXTURES/uv" "$HOME/.local/bin/uv"; chmod +x "$HOME/.local/bin/uv"; }
python_step() { bash "$repo/user/init.d/20-python/run.sh"; }
ruff_step() { bash "$repo/user/init.d/22-python-dev/run.sh"; }
runner() { bash "$repo/user/init.sh" "$@"; }

# Missing prerequisites are tested directly, independently of runner gating.
reset
run_fail ruff_step
contains "$output" './user/init.sh 20-python'
local_uv
run_fail ruff_step
absent "$TEST_LOG" 'tool install'

# A system-only Python cannot satisfy step 20; managed partial matches do.
run_ok python_step
contains "$TEST_LOG" 'python install --no-config cpython@3.13'
contains "$output" 'Managed interpreter: Python 3.13.5'
: > "$TEST_LOG"
run_ok python_step
absent "$TEST_LOG" 'python install'
for request in 3 3.13 3.13.5; do
  export EE_PYTHON_VERSION="$request"
  : > "$TEST_LOG"
  run_ok python_step
  absent "$TEST_LOG" 'python install'
done
for version in 3.130.5 3.13.50 3x13.5; do
  printf '%s\n' "$version" > "$TEST_STATE/managed"
  export EE_PYTHON_VERSION=3.13.5
  : > "$TEST_LOG"
  run_ok python_step
  contains "$TEST_LOG" 'python install --no-config cpython@3.13.5'
done

# Fresh-host latest must consult the installed uv, ignore pre/variant/PyPy
# entries, select the highest stable series numerically, and never guess.
reset
export EE_PYTHON_VERSION=latest EE_UV_VERSION=latest
export TEST_CATALOG=$'cpython-3.9.25-linux-x86_64-gnu\ncpython-3.15.1-linux-x86_64-gnu\ncpython-3.16.0a1-linux-x86_64-gnu\ncpython-3.17.0+freethreaded-linux-x86_64-gnu\npypy-3.18.0-linux-x86_64-gnu'
run_ok python_step
contains "$output" 'Resolved python latest -> 3.15'
[[ "$(grep -n '^installer$' "$TEST_LOG" | cut -d: -f1)" -lt "$(grep -n 'uv python list' "$TEST_LOG" | cut -d: -f1)" ]] || fail 'catalog queried before installation'
export TEST_CATALOG='cpython-3.16.0a1-linux-x86_64-gnu'
: > "$TEST_LOG"
run_fail python_step
contains "$output" 'no stable CPython candidate'
absent "$TEST_LOG" 'python install'
export TEST_CATALOG_FAIL=1
run_fail python_step

# PATH-only uv works; user-local uv wins when both exist (even if PATH is bad).
reset
cp "$TEST_FIXTURES/uv" "$scratch/bin/uv"
chmod +x "$scratch/bin/uv"
run_ok python_step
absent "$TEST_LOG" installer
local_uv
cp "$TEST_FIXTURES/installer.sh" "$scratch/bin/uv"
run_ok python_step
run_ok ruff_step

# Unpinned upgrade, explicit managed interpreter, migration from exact pin,
# and current reruns: no force, reinstall, or project environment operations.
reset
local_uv
printf '3.13.5\n' > "$TEST_STATE/managed"
printf 'ruff==0.1.0\n' > "$TEST_STATE/receipt"
run_ok ruff_step
[[ "$(< "$TEST_STATE/receipt")" == ruff ]] || fail 'old pin survived'
before="$(sha256sum "$TEST_STATE/installs")"
run_ok ruff_step
[[ "$(sha256sum "$TEST_STATE/installs")" == "$before" ]] || fail 'current Ruff unnecessarily reinstalled'
contains "$output" 'ruff 0.14.0'
export EE_PYTHON_VERSION=latest
run_ok ruff_step
contains "$TEST_LOG" '--no-config cpython'
export EE_PYTHON_VERSION=3.14
run_fail ruff_step
run_ok python_step
run_ok ruff_step
export TEST_TOOL_FAIL=1
run_fail ruff_step
absent "$output" 'Ruff ready'

# Preserve a non-uv executable on collision; do not use a PATH Ruff to report success.
reset
local_uv
printf '3.13.5\n' > "$TEST_STATE/managed"
cp "$TEST_FIXTURES/python" "$HOME/.local/bin/ruff"
before="$(sha256sum "$HOME/.local/bin/ruff")"
run_fail ruff_step
contains "$output" 'Executable already exists'
[[ "$(sha256sum "$HOME/.local/bin/ruff")" == "$before" ]] || fail 'unmanaged executable changed'

# Real runner selectors, allowlist gating, preservation when skipped, ordering,
# and continued prerequisite failure after step 20 fails.
reset
local_uv
printf '3.13.5\n' > "$TEST_STATE/managed"
run_ok runner 22
run_ok runner 22-python-dev
for dev in false omitted; do
  config "$dev"
  : > "$TEST_LOG"
  before="$(sha256sum "$HOME/.local/bin/ruff")"
  run_ok runner 22
  contains "$output" 'capability not enabled'
  [[ ! -s "$TEST_LOG" ]] || fail 'disabled step called uv'
  [[ "$(sha256sum "$HOME/.local/bin/ruff")" == "$before" ]] || fail 'disabled step removed Ruff'
done
reset
local_uv
run_ok runner --from 20
[[ "$(grep -n '==> Running 20-python' "$output" | cut -d: -f1)" -lt "$(grep -n '==> Running 22-python-dev' "$output" | cut -d: -f1)" ]] || fail 'wrong resume order'
reset
local_uv
export TEST_PYTHON_INSTALL_FAIL=1
run_fail runner --from 20
contains "$output" '2 script(s) failed.'
absent "$TEST_LOG" 'tool install'
reset
local_uv
export TEST_NO_MANAGED_AFTER_INSTALL=1
run_fail python_step
contains "$output" 'no matching managed CPython found after installation'

echo "PASS: $checks isolated Python/Ruff provisioning scenarios"
