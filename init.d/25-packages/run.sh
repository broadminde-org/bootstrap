#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 25-packages — Install common dev/ops apt packages on top of the
# sysadmin baseline from 05-baseline-packages.
#
# Reads packages.txt (one package per line, `#` for comments, blank
# lines ignored). Per-package apt flags (-o force-confdef/force-confold)
# keep any locally-edited config files intact across re-runs.
#
# Run after 05-baseline-packages. Run as root (sudo ./init.sh 25-packages).

echo "==> Installing common packages..."
grep -vE '^\s*(#|$)' "$(dirname "$0")/packages.txt" | \
  xargs apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

echo "==> Done."
