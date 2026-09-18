#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 01-apt-update-upgrade — Refresh apt indexes and apply pending upgrades.
#
# Always the first init step so subsequent apt-get install calls hit
# a current package index.
#
# Run as root (sudo ./init.sh 01-apt-update-upgrade).

echo "==> apt-get update"
apt-get update

echo "==> apt-get upgrade -y"
# confdef/confold: never stop on a conffile prompt (consistent with
# 05-packages, 06-playwright-deps, and 50-docker).
apt-get upgrade -y \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold"
