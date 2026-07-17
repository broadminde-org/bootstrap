#!/usr/bin/env bash
set -euo pipefail

# Common environment and privilege setup for user init.d scripts.
#
# Sources the unified conf.sh (bootstrap/init.d/lib/conf.sh), calls load_conf
# to populate toolchain version pins from the versions: section of
# bootstrap.conf.yml, then refuses to run as root.
#
# The user-side steps install per-user tooling into $HOME — they MUST run as
# the deploy user, not as root. Each step locates its own bundled assets
# relative to its own BASH_SOURCE[0].

if [ "$(id -u)" -eq 0 ]; then
  echo "Error: user scripts must NOT be run as root." >&2
  echo "Log in as the deploy user (e.g., luke) and rerun." >&2
  exit 1
fi

# Source the unified config reader AFTER the non-root check so root callers
# fail fast without inheriting its exports.
# conf.sh auto-locates bootstrap.conf.yml relative to its own path.
# shellcheck source=../../../init.d/lib/conf.sh
. "$(dirname "${BASH_SOURCE[0]}")/../../../init.d/lib/conf.sh"

# Load the config in this shell process. We read _TOOL_VERSION directly below
# (not via $() subshells) so that load_conf runs exactly once and only one
# "Using bootstrap config:" line appears per step invocation.
load_conf

# Environment-variable overrides take precedence over bootstrap.conf.yml.
# Export toolchain version pins for steps that reference them directly.
# Steps that receive "latest" resolve the concrete version themselves via
# their own API calls.
export EE_UV_VERSION="${EE_UV_VERSION:-${_TOOL_VERSION[uv]:-latest}}"
export EE_PYTHON_VERSION="${EE_PYTHON_VERSION:-${_TOOL_VERSION[python]:-latest}}"
export KILO_VERSION="${KILO_VERSION:-${_TOOL_VERSION[kilo]:-latest}}"
export EE_GO_VERSION="${EE_GO_VERSION:-${_TOOL_VERSION[go]:-latest}}"
export EE_NODE_VERSION="${EE_NODE_VERSION:-${_TOOL_VERSION[node]:-latest}}"
export CGO_ENABLED="${CGO_ENABLED:-0}"
