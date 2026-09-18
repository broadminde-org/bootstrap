#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/user.sh"

# 55-lazydocker — Install lazydocker into the deploy user's
# ~/.local/bin/.
#
# Downloads the upstream tarball + checksums, verifies SHA256, and
# drops the binary in the deploy user's ~/.local/bin. Idempotent: skips
# if the pinned version is already present at the expected path.
#
# Lazydocker does not need root at runtime — placing the binary in the
# user's home keeps it out of the system package set and lets the
# deploy user update it under their own user later.
#
# Run as root (sudo ./init.sh 55-lazydocker).

: "${LAZYDOCKER_VERSION:=v0.25.2}"

require_deploy_user
TARGET_USER="$DEPLOY_USER"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
INSTALL_DIR="$TARGET_HOME/.local/bin"
INSTALL_BIN="$INSTALL_DIR/lazydocker"

# Ensure curl is available; install via apt if missing.
if ! command -v curl >/dev/null 2>&1; then
  echo "Installing curl..."
  apt-get install -y curl
fi

# Skip if already at the pinned version. Probe as the target user —
# root may lack execute permission on the user's home in hardened
# setups, which would masquerade as a broken binary.
if [[ -x "$INSTALL_BIN" ]]; then
  current_version="$(sudo -u "$TARGET_USER" "$INSTALL_BIN" --version 2>/dev/null | awk '{print $3}' || true)"
  if [[ "${current_version#v}" == "${LAZYDOCKER_VERSION#v}" ]]; then
    echo "lazydocker ${LAZYDOCKER_VERSION} already installed at ${INSTALL_BIN}; skipping."
    exit 0
  fi
  echo "lazydocker present but version mismatch (have ${current_version:-unknown}, want ${LAZYDOCKER_VERSION}); reinstalling."
fi

sudo -u "$TARGET_USER" mkdir -p "${TARGET_HOME}/.cache"
tmpdir="$(mktemp -d "${TARGET_HOME}/.cache/lazydocker-install.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

TARBALL="lazydocker_${LAZYDOCKER_VERSION#v}_Linux_x86_64.tar.gz"
BASE_URL="https://github.com/jesseduffield/lazydocker/releases/download/${LAZYDOCKER_VERSION}"
TARBALL_URL="${BASE_URL}/${TARBALL}"
CHECKSUMS_URL="${BASE_URL}/checksums.txt"

echo "Downloading ${TARBALL_URL}..."
curl -fsSL --retry 3 -o "${tmpdir}/${TARBALL}" "$TARBALL_URL"

echo "Downloading ${CHECKSUMS_URL}..."
curl -fsSL --retry 3 -o "${tmpdir}/checksums.txt" "$CHECKSUMS_URL"

echo "Verifying SHA256..."
# `--ignore-missing` passes vacuously when the release renamed its
# assets, so require the exact tarball name to appear in checksums.txt
# first, then verify just that line.
if ! grep -F " ${TARBALL}" "${tmpdir}/checksums.txt" > "${tmpdir}/checksum.txt"; then
  echo "ERROR: ${TARBALL} not found in upstream checksums.txt — asset renamed?" >&2
  exit 1
fi
(
  cd "$tmpdir" || exit 1
  sha256sum -c checksum.txt
)

echo "Installing lazydocker to ${INSTALL_BIN} (as ${TARGET_USER})..."
sudo -u "$TARGET_USER" mkdir -p "$INSTALL_DIR"
tar -C "$tmpdir" -xzf "${tmpdir}/${TARBALL}" lazydocker
install -m 0755 "${tmpdir}/lazydocker" "$INSTALL_BIN"
chown "$TARGET_USER":"$(id -gn "$TARGET_USER")" "$INSTALL_BIN"

echo "lazydocker ${LAZYDOCKER_VERSION} installed at ${INSTALL_BIN}"
sudo -u "$TARGET_USER" "$INSTALL_BIN" --version || true
