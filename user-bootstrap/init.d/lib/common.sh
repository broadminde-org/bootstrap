#!/usr/bin/env bash
set -euo pipefail

# Common environment and privilege setup for user-bootstrap init.d scripts.
#
# Sources ./env.sh (which sets EE_ROOT to the user-bootstrap folder),
# then refuses to run as root. The user-side steps install per-user
# tooling into $HOME (kilo CLI, wrapper for kilo-session-report, llmdocs
# shim, opencode/vscode config) — they MUST run as the deploy user,
# not as root.

if [ "$(id -u)" -eq 0 ]; then
  echo "Error: user-bootstrap scripts must NOT be run as root." >&2
  echo "Log in as the deploy user (e.g., luke) and rerun." >&2
  exit 1
fi

# Source env.sh AFTER the non-root check so root callers fail fast
# without inheriting env.sh's exports.
# shellcheck source=./env.sh
. "$(dirname "${BASH_SOURCE[0]}")/env.sh"
