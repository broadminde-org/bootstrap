#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 20-python — Install per-user Python tooling (uv + uv-managed CPython).
#
# Two user-level installs:
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
#                  uv also installs versioned executable links in its
#                  user bin directory. No --default or --force is used;
#                  existing user links and older interpreters are kept.
#
# All installs land in the running user's $HOME — files outside
# the home directory are not touched, so this step can be re-run
# without root. The non-root check and toolchain version pins are set up
# by lib/common.sh; do NOT add `set -euo pipefail` or an id check here.
#
# Idempotent: each sub-tool is independently detected; the script
# exits 0 with an "already installed" message when everything is
# at its pinned version. Per-tool installs run only when the
# detected version does not match the pin, so a partial run (e.g.
# uv already at pin, Python missing) installs only what is missing.
#
# Run as the deploy user (./user/init.sh 20-python).

# ---------------------------------------------------------------------------
# Resolve "latest" pins
# ---------------------------------------------------------------------------

# Environment-variable overrides take precedence over bootstrap.conf.yml,
# then common.sh re-exports them. If a version is still "latest",
# resolve it to the actual latest stable release.
resolve_latest_uv() {
  local tag
  tag="$(curl -fsSL --retry 3 "https://api.github.com/repos/astral-sh/uv/releases/latest" 2>/dev/null \
    | jq -r '.tag_name // empty')"
  if [[ -z "$tag" ]]; then
    echo "ERROR: could not resolve the latest uv release from the GitHub API." >&2
    echo "       Pin an explicit version (versions: uv: in bootstrap.conf.yml)" >&2
    echo "       or check connectivity to api.github.com." >&2
    exit 1
  fi
  echo "${tag#v}"
}

resolve_latest_python() {
  local version
  # Preserve the existing latest-series policy, excluding prereleases and
  # variant builds. The final uv executable supplies the fresh-host catalog.
  version="$("$UV_CMD" python list --only-downloads --all-versions --no-config \
    | awk -F- '$1 == "cpython" && $2 ~ /^[0-9]+\.[0-9]+\.[0-9]+$/ {
        split($2, parts, "."); print parts[1] "." parts[2]
      }' | sort -t. -k1,1n -k2,2n | tail -1)" || return 1
  if [[ -z "$version" ]]; then
    echo "ERROR: uv's catalog contains no stable CPython candidate for this host." >&2
    return 1
  fi
  echo "$version"
}

if [[ "$EE_UV_VERSION" == "latest" ]]; then
  EE_UV_VERSION="$(resolve_latest_uv)"
  echo "Resolved uv latest -> ${EE_UV_VERSION}"
fi

LOCAL_BIN="$HOME/.local/bin"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# Track which sub-installs actually ran so we can exit with a
# truthful summary even on a no-op idempotent re-run. Initialised
# to 0 so the final `(( … ))` test is safe under `set -u`.
uv_installed=0
python_installed=0

# Ensure $LOCAL_BIN exists before uv runs (the installer drops
# files there but does not create the directory itself on every
# platform / version).
mkdir -p "$LOCAL_BIN"

# ---------------------------------------------------------------------------
# 1. uv
# ---------------------------------------------------------------------------

UV_BIN="$LOCAL_BIN/uv"

# Idempotency: prefer the user-local uv, then PATH, consistently with
# the Python substep. Skip if that executable
# reports the pinned version. `uv --version` prints "uv <ver>".
if [[ -x "$UV_BIN" ]]; then
  current_uv="$("$UV_BIN" --version 2>/dev/null | awk '{print $2}')"
elif command -v uv >/dev/null 2>&1; then
  current_uv="$(uv --version 2>/dev/null | awk '{print $2}')"
else
  current_uv=""
fi

if [[ -n "$current_uv" && "$current_uv" == "${EE_UV_VERSION#v}" ]]; then
  echo "uv ${EE_UV_VERSION} already installed; skipping."
else
  echo "Installing uv ${EE_UV_VERSION} (current: ${current_uv:-none})..."

  mkdir -p "$CACHE_HOME"
  uv_tmp="$(mktemp -d "$CACHE_HOME/uv-install.XXXXXX")"
  trap 'rm -rf "$uv_tmp"' EXIT
  curl -fsSL --retry 3 \
    "https://github.com/astral-sh/uv/releases/download/${EE_UV_VERSION#v}/uv-installer.sh" \
    -o "$uv_tmp/uv-installer.sh"
  sh "$uv_tmp/uv-installer.sh" --no-modify-path

  uv_installed=1
  echo "uv ${EE_UV_VERSION} installed."
fi

# Re-resolve uv for the Python substep — after a fresh install it
# may not be in the current shell's PATH yet (the installer shims
# into a child shell). Prefer the known $LOCAL_BIN/uv path.
if [[ -x "$LOCAL_BIN/uv" ]]; then
  UV_CMD="$LOCAL_BIN/uv"
else
  UV_CMD="$(command -v uv || true)"
fi

if [[ -z "$UV_CMD" || ! -x "$UV_CMD" ]]; then
  echo "ERROR: uv was not found after installation; re-run ./user/init.sh 20-python from the repository root." >&2
  exit 1
fi
actual_uv="$("$UV_CMD" --version | awk '{print $2}')"
if [[ "$actual_uv" != "${EE_UV_VERSION#v}" ]]; then
  echo "ERROR: selected uv reports ${actual_uv}, expected ${EE_UV_VERSION}." >&2
  exit 1
fi
if [[ "$EE_PYTHON_VERSION" == "latest" ]]; then
  EE_PYTHON_VERSION="$(resolve_latest_python)"
  echo "Resolved python latest -> ${EE_PYTHON_VERSION}"
fi

# ---------------------------------------------------------------------------
# 2. Python (uv-managed)
# ---------------------------------------------------------------------------

# uv parses numeric components literally; --system excludes project/virtual
# environments, while --managed-python excludes system-installed Python.
if python_bin="$("$UV_CMD" python find --no-project --system --managed-python \
    --no-python-downloads --no-config "cpython@${EE_PYTHON_VERSION}" 2>/dev/null)"; then
  echo "Python ${EE_PYTHON_VERSION} (uv-managed) already installed; skipping."
else
  echo "Installing Python ${EE_PYTHON_VERSION} via uv..."
  "$UV_CMD" python install --no-config "cpython@${EE_PYTHON_VERSION}" || {
    echo "uv python install failed for ${EE_PYTHON_VERSION}." >&2
    echo "If this is a brand-new uv version, check https://docs.astral.sh/uv/concepts/python-versions/" >&2
    echo "for the latest CPython build available." >&2
    exit 1
  }
  python_bin="$("$UV_CMD" python find --no-project --system --managed-python \
    --no-python-downloads --no-config "cpython@${EE_PYTHON_VERSION}")" || {
    echo "ERROR: no matching managed CPython found after installation." >&2
    exit 1
  }
  python_installed=1
  echo "Python ${EE_PYTHON_VERSION} installed via uv."
fi
actual_python="$("$python_bin" --version)"
echo "Managed interpreter: ${actual_python} (${python_bin})"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

if (( uv_installed == 0 && python_installed == 0 )); then
  echo ""
  echo "20-python: nothing to do — uv ${EE_UV_VERSION}, Python ${EE_PYTHON_VERSION} both present."
  exit 0
fi

echo ""
echo "20-python: installed"
if (( uv_installed )); then echo "  - uv ${EE_UV_VERSION}"; fi
if (( python_installed )); then echo "  - Python ${EE_PYTHON_VERSION} (uv-managed)"; fi
echo ""
echo "PATH note: $LOCAL_BIN must be on PATH for login shells (see /etc/skel/.profile)."
echo "Use 'uv run <script>' to run Python scripts against the uv-managed interpreter."
