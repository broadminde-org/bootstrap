#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 59-gh-cli - install GitHub CLI from the official signed Debian repository.
#
# Authentication is intentionally not configured here. `gh auth login` is
# user-specific and must be performed separately by the operator.

# shellcheck disable=SC1091
DISTRO="$({ . /etc/os-release; printf '%s' "${ID:-}"; })"
case "$DISTRO" in
  debian|ubuntu) ;;
  *)
    echo "ERROR: 59-gh-cli supports Debian and Ubuntu only (detected: ${DISTRO:-unknown})." >&2
    exit 1
    ;;
esac

KEYRING_DIR="/etc/apt/keyrings"
KEYRING="$KEYRING_DIR/githubcli-archive-keyring.gpg"
SOURCE_LIST="/etc/apt/sources.list.d/github-cli.list"
KEY_URL="https://cli.github.com/packages/githubcli-archive-keyring.gpg"

install -d -m 0755 "$KEYRING_DIR" /etc/apt/sources.list.d

tmp_key="$(mktemp)"
trap 'rm -f "$tmp_key"' EXIT
curl --fail --silent --show-error --proto '=https' --tlsv1.2 \
  "$KEY_URL" -o "$tmp_key"

if [[ ! -f "$KEYRING" ]] || ! cmp -s "$tmp_key" "$KEYRING"; then
  install -m 0644 "$tmp_key" "$KEYRING"
  echo "Installed GitHub CLI APT keyring."
else
  echo "GitHub CLI APT keyring is already current."
fi

source_line="deb [arch=$(dpkg --print-architecture) signed-by=$KEYRING] https://cli.github.com/packages stable main"
if [[ ! -f "$SOURCE_LIST" ]] || [[ "$(cat "$SOURCE_LIST")" != "$source_line" ]]; then
  printf '%s\n' "$source_line" > "$SOURCE_LIST"
  chmod 0644 "$SOURCE_LIST"
  echo "Configured GitHub CLI APT repository."
else
  echo "GitHub CLI APT repository is already configured."
fi

apt-get update
apt-get install -y gh

gh --version | sed -n '1p'
echo "GitHub CLI installed. Authenticate separately with: gh auth login"
