#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 05-baseline-packages — Install the sysadmin baseline packages.
#
# Reads packages.txt (one package per line, `#` for comments, blank
# lines ignored). Mirrors scripts/init.d/03-packages/run.sh.
#
# Run as root (sudo ./init.sh 05-baseline-packages).

echo "==> Installing baseline packages from packages.txt..."
grep -vE '^\s*(#|$)' "$(dirname "$0")/packages.txt" | \
  xargs apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

echo "==> Done."
