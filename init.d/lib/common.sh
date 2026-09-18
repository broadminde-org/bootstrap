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

# env_file_value KEY — read a KEY=value pair from the repo-root .env
# without sourcing it (sourcing would execute arbitrary shell). Prints
# the value with surrounding double quotes stripped; returns 1 when the
# file or the key is absent. EE_ROOT comes from env.sh (sourced above).
env_file_value() {
  local key="$1"
  local env_file="$EE_ROOT/.env"
  [[ -f "$env_file" ]] || return 1
  grep -E "^${key}=" "$env_file" | head -n 1 | cut -d= -f2- \
    | sed -e 's/^"//' -e 's/"$//'
}
