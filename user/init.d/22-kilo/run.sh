#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 22-kilo — Install the kilo CLI native binary.
#
# One user-level install lands in $HOME/.local/bin/:
#
#   kilo         Native CLI binary for the agent-tuner / Kilo
#                workflow. Downloaded from the Kilo-Org/kilocode
#                GitHub release as a per-platform tarball
#                (kilo-linux-x64.tar.gz, etc.). This is the
#                upstream-canonical install path
#                (https://kilo.ai/cli) — does NOT require Node.
#                The older `@kilocode/cli` npm package is being
#                superseded by this binary.
#
# The install lands in the running user's $HOME — files outside
# of /etc and /usr/local are not touched, so this step can be re-run
# without root. The non-root check and version pins are set up
# by lib/common.sh; do NOT add `set -euo pipefail` or an id check here.
#
# Idempotent: checks the installed version; exits 0 with an
# "already installed" message when the pinned version matches.
#
# Run as the deploy user (./user/init.sh 22-kilo).

# ---------------------------------------------------------------------------
# Resolve "latest" pin
# ---------------------------------------------------------------------------

resolve_latest_kilo() {
  local tag
  tag="$(curl -fsSL "https://api.github.com/repos/Kilo-Org/kilocode/releases/latest" 2>/dev/null \
    | grep -o '"tag_name": *"[^"]*"' \
    | head -1 \
    | grep -o 'v[^"]*')"
  echo "${tag:-v7.0.0}"
}

if [[ "$KILO_VERSION" == "latest" ]]; then
  KILO_VERSION="$(resolve_latest_kilo)"
  echo "Resolved kilo latest -> ${KILO_VERSION}"
fi

LOCAL_BIN="$HOME/.local/bin"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

kilo_installed=0

# Ensure $LOCAL_BIN exists.
mkdir -p "$LOCAL_BIN"

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
    echo "It is normally installed by bootstrap's 25-packages step." >&2
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

  mkdir -p "$CACHE_HOME"
  kilo_tmp="$(mktemp -d "$CACHE_HOME/kilo-install.XXXXXX")"
  trap 'rm -rf "$kilo_tmp"' EXIT

  kilo_url="https://github.com/Kilo-Org/kilocode/releases/download/${KILO_VERSION}/${kilo_tarball}"
  echo "Downloading ${kilo_url}..."
  curl -fsSL --retry 3 -o "$kilo_tmp/$kilo_tarball" "$kilo_url"

  echo "Verifying SHA256..."
  actual_sha="$(sha256sum "$kilo_tmp/$kilo_tarball" | awk '{print $1}')"
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    echo "ERROR: SHA256 mismatch for ${kilo_tarball}." >&2
    echo "  expected: ${expected_sha}" >&2
    echo "  actual:   ${actual_sha}" >&2
    exit 1
  fi

  # The kilo tarball unpacks `kilo` and an optional `tree-sitter/`
  # sibling directory. We only need the binary; ignore the rest.
  echo "Extracting kilo binary..."
  tar -C "$kilo_tmp" -xzf "$kilo_tmp/$kilo_tarball" kilo

  echo "Installing kilo to ${KILO_BIN}..."
  mkdir -p "$LOCAL_BIN"
  install -m 0755 "$kilo_tmp/kilo" "$KILO_BIN"

  kilo_installed=1
  echo "kilo ${KILO_VERSION} installed at ${KILO_BIN}"
  "$KILO_BIN" --version || true
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

if (( kilo_installed == 0 )); then
  echo ""
  echo "22-kilo: nothing to do — kilo ${KILO_VERSION} already present."
  exit 0
fi

echo ""
echo "22-kilo: installed kilo ${KILO_VERSION}"
echo ""
echo "PATH note: $LOCAL_BIN must be on PATH for login shells (see /etc/skel/.profile)."
