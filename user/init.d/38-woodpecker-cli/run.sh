#!/usr/bin/env bash
# Install the Woodpecker CLI matching the server release.

set -euo pipefail

# shellcheck source=../lib/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=../lib/os.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/os.sh"

version="${WOODPECKER_CLI_VERSION:-$(get_pinned_version woodpecker v3.17.0)}"
bin_dir="$HOME/.local/bin"
mkdir -p "$bin_dir"

case "$(uname -m)" in
  x86_64)        arch="amd64" ;;
  aarch64|arm64) arch="arm64" ;;
  *) echo "ERROR: unsupported architecture for woodpecker-cli: $(uname -m)" >&2; exit 1 ;;
esac
# Upstream publishes darwin_arm64/darwin_amd64 as well as linux_*.
asset="woodpecker-cli_${BOOTSTRAP_OS}_${arch}.tar.gz"

if [[ -x "$bin_dir/woodpecker-cli" ]] && "$bin_dir/woodpecker-cli" --version 2>/dev/null | grep -q "${version#v}"; then
  echo "woodpecker-cli ${version} already installed."
  exit 0
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/woodpecker-cli.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
archive="$tmp_dir/woodpecker-cli.tar.gz"

base_url="https://github.com/woodpecker-ci/woodpecker/releases/download/${version}"
curl -fsSL --retry 3 "${base_url}/${asset}" -o "$archive"
curl -fsSL --retry 3 "${base_url}/checksums.txt" -o "$tmp_dir/checksums.txt"

# Require the exact asset in checksums.txt, then verify just that line.
# Portable: sha256sum on Linux, shasum -a 256 on macOS.
if ! expected_sha="$(grep -F " ${asset}" "$tmp_dir/checksums.txt" | awk '{print $1}')" \
   || [[ -z "$expected_sha" ]]; then
  echo "ERROR: ${asset} not found in upstream checksums.txt — asset renamed?" >&2
  exit 1
fi
sha256_verify "$archive" "$expected_sha"

tar -xzf "$archive" -C "$tmp_dir"
install -m 0755 "$tmp_dir/woodpecker-cli" "$bin_dir/woodpecker-cli"
echo "Installed woodpecker-cli ${version}."
