#!/usr/bin/env bash
set -euo pipefail

# Common environment and privilege setup for bootstrap init.d scripts.
#
# Sources ./env.sh (which sets EE_ROOT to the bootstrap repo root and
# exports toolchain version pins), then enforces root and sets the
# non-interactive apt defaults that every host step relies on.

export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical
export NEEDRESTART_MODE=a

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: this script must be run as root (e.g., via sudo)." >&2
  exit 1
fi

# Source env.sh AFTER the root check so non-root callers fail fast
# without inheriting env.sh's PATH mutations and exports.
# shellcheck source=./env.sh
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
