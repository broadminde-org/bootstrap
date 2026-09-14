#!/usr/bin/env bash
# Install the Woodpecker CLI matching the server release.

set -euo pipefail

version="${WOODPECKER_CLI_VERSION:-v3.17.0}"
bin_dir="$HOME/.local/bin"
mkdir -p "$bin_dir"

if [[ -x "$bin_dir/woodpecker-cli" ]] && "$bin_dir/woodpecker-cli" --version 2>/dev/null | grep -q "${version#v}"; then
  echo "woodpecker-cli ${version} already installed."
  exit 0
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/woodpecker-cli.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
archive="$tmp_dir/woodpecker-cli.tar.gz"
curl -fsSL "https://github.com/woodpecker-ci/woodpecker/releases/download/${version}/woodpecker-cli_linux_amd64.tar.gz" \
  -o "$archive"
tar -xzf "$archive" -C "$tmp_dir"
install -m 0755 "$tmp_dir/woodpecker-cli" "$bin_dir/woodpecker-cli"
echo "Installed woodpecker-cli ${version}."
