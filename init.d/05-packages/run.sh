#!/usr/bin/env bash
# shellcheck disable=SC1091
. "$(dirname "$0")/../lib/common.sh"

# 05-packages — Install the host package set.
#
# Reads packages.txt (one package per line, `#` for comments, blank
# lines ignored). Per-package apt flags (-o force-confdef/force-
# confold) keep any locally-edited config files intact across
# re-runs.
#
# Run as root (sudo ./init.sh 05-packages).

echo "==> Installing host packages from packages.txt..."
grep -vE '^\s*(#|$)' "$(dirname "$0")/packages.txt" | \
  xargs apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

echo "==> Done."
