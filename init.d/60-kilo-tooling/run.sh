#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 60-kilo-tooling — host-level tools for the agent-tuner workflow.
#
# Installs three user-level binaries into $SUDO_USER/.local/bin/:
#
#   1. uv          Astral's Python package / project runner. The
#                  standalone installer from https://docs.astral.sh/uv/
#                  is used in preference to the apt package — the apt
#                  build lags badly and cannot be independently
#                  updated without root. uv then provisions the
#                  matching Python interpreter itself
#                  (`uv python install`), so this step does NOT need
#                  a separate apt-get install python3.X step.
#
#   2. Python      Managed by uv. The interpreter lives under
#                  ~/.local/share/uv/python/cpython-<ver>-.../bin/ —
#                  not on PATH directly. Callers should use
#                  `uv run …` (or rely on uv's automatic environment
#                  discovery) rather than bare `python3`. Apps that
#                  need a bare `python3` on PATH should add the
#                  uv-managed interpreter to PATH (or symlink it)
#                  themselves.
#
#   3. kilo        Native CLI binary for the agent-tuner / Kilo
#                  workflow. Downloaded from the Kilo-Org/kilocode
#                  GitHub release as a per-platform tarball
#                  (kilo-linux-x64.tar.gz, etc.). This is the
#                  upstream-canonical install path
#                  (https://kilo.ai/cli) — does NOT require Node.
#                  The older `@kilocode/cli` npm package is being
#                  superseded by this binary.
#
# All three installs run as $SUDO_USER so the files land in the
# deploy user's home and can be updated by that user later without
# root. The bootstrap root check + DEBIAN_FRONTEND setup is done
# by lib/common.sh; do NOT add `set -euo pipefail` or an id check
# here — common.sh owns those.
#
# Idempotent: each sub-tool is independently detected; the script
# exits 0 with an "already installed" message when everything is
# at its pinned version. Per-tool installs run only when the
# detected version does not match the pin, so a partial run (e.g.
# uv already at pin, kilo missing) installs only what is missing.
#
# Run as root (sudo ./init.sh 60-kilo-tooling).

: "${EE_UV_VERSION:=0.8.13}"
: "${EE_PYTHON_VERSION:=3.14}"
: "${KILO_VERSION:=v7.4.1}"

# Resolve the non-root user who invoked sudo.
TARGET_USER="${SUDO_USER:?must run under sudo (e.g., sudo ./init.sh)}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
LOCAL_BIN="$TARGET_HOME/.local/bin"

# Track which sub-installs actually ran so we can exit with a
# truthful summary even on a no-op idempotent re-run. Initialised
# to 0 so the final `(( … ))` test is safe under `set -u` from
# lib/common.sh.
uv_installed=0
python_installed=0
kilo_installed=0

# Ensure curl is available; install via apt if missing. uv and the
# kilo release tarball are both fetched via curl.
if ! command -v curl >/dev/null 2>&1; then
  echo "Installing curl..."
  apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" curl
fi

# ---------------------------------------------------------------------------
# 1. uv
# ---------------------------------------------------------------------------

UV_BIN="$LOCAL_BIN/uv"

# Ensure $LOCAL_BIN exists before uv runs (the installer drops
# files there but does not create the directory itself on every
# platform / version).
sudo -u "$TARGET_USER" mkdir -p "$LOCAL_BIN"

# Idempotency: skip if uv is on PATH (or at the pinned path) and
# reports the pinned version. `uv --version` prints "uv <ver>".
if command -v uv >/dev/null 2>&1; then
  current_uv="$(uv --version 2>/dev/null | awk '{print $2}')"
elif [[ -x "$UV_BIN" ]]; then
  current_uv="$("$UV_BIN" --version 2>/dev/null | awk '{print $2}')"
else
  current_uv=""
fi

if [[ -n "$current_uv" && "$current_uv" == "$EE_UV_VERSION" ]]; then
  echo "uv ${EE_UV_VERSION} already installed; skipping."
else
  echo "Installing uv ${EE_UV_VERSION} (current: ${current_uv:-none})..."

  # Work in a deploy-user-owned tempdir so curl can write without
  # needing sudo. mktemp under the user's home + trap for cleanup.
  sudo -u "$TARGET_USER" mkdir -p "${TARGET_HOME}/.cache"
  uv_tmp="$(mktemp -d "${TARGET_HOME}/.cache/uv-install.XXXXXX")"
  # shellcheck disable=SC2064  # we want the $uv_tmp resolved now.
  trap 'rm -rf "$uv_tmp"' EXIT
  install_env_out="$(sudo -u "$TARGET_USER" -H bash -c '
    set -e
    export XDG_CACHE_HOME="$HOME/.cache"
    curl -fsSL --retry 3 \
      "https://github.com/astral-sh/uv/releases/download/'"$EE_UV_VERSION"'/uv-installer.sh" \
      -o "'"$uv_tmp"'/uv-installer.sh"
    sh "'"$uv_tmp"'/uv-installer.sh" --no-modify-path
  ' 2>&1)" || {
    echo "$install_env_out" >&2
    echo "uv installer failed for version ${EE_UV_VERSION}." >&2
    echo "Verify the version exists at https://github.com/astral-sh/uv/releases/tag/${EE_UV_VERSION}" >&2
    exit 1
  }

  uv_installed=1
  echo "uv ${EE_UV_VERSION} installed."
fi

# Re-resolve uv for the Python substep — after a fresh install it
# may not be in the current shell's PATH yet (we ran as the user in
# a sub-shell). Prefer the known $LOCAL_BIN/uv path.
if [[ -x "$LOCAL_BIN/uv" ]]; then
  UV_CMD="$LOCAL_BIN/uv"
else
  UV_CMD="$(command -v uv || true)"
fi

# ---------------------------------------------------------------------------
# 2. Python (uv-managed)
# ---------------------------------------------------------------------------

# `uv python list --only-installed` prints installed interpreters
# e.g. "cpython-3.14.0-<platform>-<libc>-x86_64-gnu". We accept any
# installed CPython whose major.minor prefix matches EE_PYTHON_VERSION.
python_already=0
if [[ -n "$UV_CMD" ]]; then
  if "$UV_CMD" python list --only-installed 2>/dev/null \
        | awk '{print $1}' \
        | grep -E "^cpython-${EE_PYTHON_VERSION}(\.|$)" >/dev/null; then
    python_already=1
  fi
fi

if (( python_already )); then
  echo "Python ${EE_PYTHON_VERSION} (uv-managed) already installed; skipping."
else
  if [[ -z "$UV_CMD" ]]; then
    echo "ERROR: uv is required to install Python ${EE_PYTHON_VERSION} but was not found on PATH." >&2
    echo "       Re-run after the uv install above succeeds, or install uv manually." >&2
    exit 1
  fi
  echo "Installing Python ${EE_PYTHON_VERSION} via uv..."
  # uv python install runs inside the user's home so the interpreter
  # lands under $HOME/.local/share/uv/python/...
  sudo -u "$TARGET_USER" -H bash -c "
    set -e
    export XDG_CACHE_HOME=\"\$HOME/.cache\"
    '$UV_CMD' python install '$EE_PYTHON_VERSION'
  " || {
    echo "uv python install failed for ${EE_PYTHON_VERSION}." >&2
    echo "If this is a brand-new uv version, check https://docs.astral.sh/uv/concepts/python-versions/" >&2
    echo "for the latest CPython build available." >&2
    exit 1
  }
  python_installed=1
  echo "Python ${EE_PYTHON_VERSION} installed via uv."
fi

# ---------------------------------------------------------------------------
# 3. kilo CLI (native binary from Kilo-Org/kilocode GitHub release)
# ---------------------------------------------------------------------------

KILO_BIN="$LOCAL_BIN/kilo"

# Map current host arch to the kilo asset name suffix. The release
# ships linux-x64, linux-arm64 (glibc + musl variants) and the
# matching windows/darwin builds. We default to glibc — Debian /
# Ubuntu hosts are glibc. (musl detection is best-effort.)
host_arch="$(uname -m)"
case "$host_arch" in
  x86_64|amd64)  kilo_arch="x64" ;;
  aarch64|arm64) kilo_arch="arm64" ;;
  *)
    echo "ERROR: unsupported architecture for kilo install: $host_arch" >&2
    echo "       Supported: x86_64, aarch64." >&2
    exit 1
    ;;
esac

# AVX2 detection — match the upstream kilo installer. x64 hosts
# without AVX2 need the -baseline variant.
needs_baseline=0
if [[ "$kilo_arch" == "x64" ]]; then
  if ! grep -qwi avx2 /proc/cpuinfo 2>/dev/null; then
    needs_baseline=1
  fi
fi

# musl detection — match the upstream installer.
is_musl=0
if [[ -f /etc/alpine-release ]]; then
  is_musl=1
elif command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; then
  is_musl=1
fi

kilo_target="linux-${kilo_arch}"
if (( needs_baseline )); then
  kilo_target="${kilo_target}-baseline"
fi
if (( is_musl )); then
  kilo_target="${kilo_target}-musl"
fi

kilo_tarball="kilo-${kilo_target}.tar.gz"

# Strip leading 'v' for tag math.
kilo_version_short="${KILO_VERSION#v}"

# Idempotency flag — initialised to 0 so the later `(( … ))` test
# is safe under `set -u` even when no mismatch was detected.
kilo_need_install=0

# Idempotency: skip when the installed kilo reports the pinned
# version. `kilo --version` prints "<ver>".
if [[ -x "$KILO_BIN" ]]; then
  current_kilo="$("$KILO_BIN" --version 2>/dev/null || true)"
  if [[ "$current_kilo" == "$kilo_version_short" ]]; then
    echo "kilo ${KILO_VERSION} already installed at ${KILO_BIN}; skipping."
  else
    kilo_need_install=1
    echo "kilo present but version mismatch (have ${current_kilo:-unknown}, want ${kilo_version_short}); reinstalling."
  fi
else
  kilo_need_install=1
fi

if (( kilo_need_install )); then
  echo "Installing kilo ${KILO_VERSION} for ${kilo_target}..."

  # Verify the release actually exists before downloading. The
  # GitHub release JSON also carries per-asset SHA256 digests; we
  # use those as the canonical checksum (no standalone checksums.txt
  # is published alongside kilo releases — see how
  # https://github.com/Kilo-Org/kilocode/releases/latest is laid
  # out).
  release_json="$(curl -fsSL --retry 3 \
    "https://api.github.com/repos/Kilo-Org/kilocode/releases/tags/${KILO_VERSION}")" || {
    echo "ERROR: release ${KILO_VERSION} not found for Kilo-Org/kilocode." >&2
    echo "Check https://github.com/Kilo-Org/kilocode/releases for the current versions." >&2
    exit 1
  }

  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required to parse the kilo release JSON but was not found." >&2
    echo "It is normally installed by 25-packages; re-run that step first." >&2
    exit 1
  fi

  expected_sha="$(jq -r --arg t "$kilo_tarball" \
    '.assets[] | select(.name == $t) | .digest' \
    <<<"$release_json" | sed 's/^sha256://')"
  if [[ -z "$expected_sha" || "$expected_sha" == "null" ]]; then
    echo "ERROR: could not find SHA256 digest for asset ${kilo_tarball} in release ${KILO_VERSION}." >&2
    echo "Re-check the release layout at https://github.com/Kilo-Org/kilocode/releases/tag/${KILO_VERSION}" >&2
    exit 1
  fi

  # Deploy-user-owned tmpdir so curl can write without sudo.
  sudo -u "$TARGET_USER" mkdir -p "${TARGET_HOME}/.cache"
  kilo_tmp="$(mktemp -d "${TARGET_HOME}/.cache/kilo-install.XXXXXX")"
  # shellcheck disable=SC2064  # we want the $kilo_tmp resolved now.
  trap 'rm -rf "$uv_tmp" "$kilo_tmp"' EXIT

  kilo_url="https://github.com/Kilo-Org/kilocode/releases/download/${KILO_VERSION}/${kilo_tarball}"
  echo "Downloading ${kilo_url}..."
  curl -fsSL --retry 3 -o "${kilo_tmp}/${kilo_tarball}" "$kilo_url"

  echo "Verifying SHA256..."
  actual_sha="$(sha256sum "${kilo_tmp}/${kilo_tarball}" | awk '{print $1}')"
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    echo "ERROR: SHA256 mismatch for ${kilo_tarball}." >&2
    echo "  expected: ${expected_sha}" >&2
    echo "  actual:   ${actual_sha}" >&2
    exit 1
  fi

  # The kilo tarball unpacks `kilo` and an optional `tree-sitter/`
  # sibling directory. We only need the binary; ignore the rest.
  echo "Extracting kilo binary..."
  tar -C "$kilo_tmp" -xzf "${kilo_tmp}/${kilo_tarball}" kilo

  echo "Installing kilo to ${KILO_BIN} (as ${TARGET_USER})..."
  sudo -u "$TARGET_USER" mkdir -p "$LOCAL_BIN"
  install -m 0755 "${kilo_tmp}/kilo" "$KILO_BIN"
  chown "$TARGET_USER":"$(id -gn "$TARGET_USER")" "$KILO_BIN"

  kilo_installed=1
  echo "kilo ${KILO_VERSION} installed at ${KILO_BIN}"
  "$KILO_BIN" --version || true
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

if (( uv_installed == 0 && python_installed == 0 && kilo_installed == 0 )); then
  echo ""
  echo "60-kilo-tooling: nothing to do — uv ${EE_UV_VERSION}, Python ${EE_PYTHON_VERSION}, kilo ${KILO_VERSION} all present."
  exit 0
fi

echo ""
echo "60-kilo-tooling: installed"
(( uv_installed ))    && echo "  - uv ${EE_UV_VERSION}"
(( python_installed )) && echo "  - Python ${EE_PYTHON_VERSION} (uv-managed)"
(( kilo_installed ))  && echo "  - kilo ${KILO_VERSION}"
echo ""
echo "PATH note: $LOCAL_BIN is on PATH for login shells (see /etc/skel/.profile)."
echo "Use 'uv run <script>' to run Python scripts against the uv-managed interpreter."
