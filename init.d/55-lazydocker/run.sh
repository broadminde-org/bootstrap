#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 55-lazydocker — Install lazydocker into the actual user's
# ~/.local/bin/.
#
# Downloads the upstream tarball + checksums, verifies SHA256, and
# drops the binary in $SUDO_USER/.local/bin. Idempotent: skips if the
# pinned version is already present at the expected path.
#
# Lazydocker does not need root at runtime — placing the binary in the
# user's home keeps it out of the system package set and lets the
# deploy user update it under their own user later.
#
# Run as root (sudo ./init.sh 55-lazydocker).

: "${LAZYDOCKER_VERSION:=v0.25.2}"

# Resolve the non-root user who invoked sudo.
TARGET_USER="${SUDO_USER:?must run under sudo (e.g., sudo ./init.sh)}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
INSTALL_DIR="$TARGET_HOME/.local/bin"
INSTALL_BIN="$INSTALL_DIR/lazydocker"

# Ensure curl is available; install via apt if missing.
if ! command -v curl >/dev/null 2>&1; then
  echo "Installing curl..."
  apt-get install -y curl
fi

# Skip if already at the pinned version.
if [[ -x "$INSTALL_BIN" ]]; then
  current_version="$("$INSTALL_BIN" --version 2>/dev/null | awk '{print $3}' || true)"
  if [[ "${current_version#v}" == "${LAZYDOCKER_VERSION#v}" ]]; then
    echo "lazydocker ${LAZYDOCKER_VERSION} already installed at ${INSTALL_BIN}; skipping."
    exit 0
  fi
  echo "lazydocker present but version mismatch (have ${current_version:-unknown}, want ${LAZYDOCKER_VERSION}); reinstalling."
fi

tmpdir="$(mktemp -d)"
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
(
  cd "$tmpdir"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c --ignore-missing checksums.txt
  else
    expected="$(awk -v t="${TARBALL}" '$2 == t {print $1}' checksums.txt)"
    actual="$(sha256sum "$TARBALL" | awk '{print $1}')"
    [[ "$expected" == "$actual" ]] || { echo "SHA256 mismatch: expected=$expected actual=$actual" >&2; exit 1; }
  fi
)

echo "Installing lazydocker to ${INSTALL_BIN} (as ${TARGET_USER})..."
sudo -u "$TARGET_USER" mkdir -p "$INSTALL_DIR"
tar -C "$tmpdir" -xzf "${tmpdir}/${TARBALL}" lazydocker
sudo -u "$TARGET_USER" install -m 0755 "${tmpdir}/lazydocker" "$INSTALL_BIN"

echo "lazydocker ${LAZYDOCKER_VERSION} installed at ${INSTALL_BIN}"
"$INSTALL_BIN" --version || true
