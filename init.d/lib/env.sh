#!/usr/bin/env bash
# lib/env.sh — derive EE_ROOT and toolchain versions for the bootstrap repo.
#
# Lives at bootstrap/init.d/lib/env.sh. Sets EE_ROOT to the bootstrap
# repo root (so host init steps can locate packages.txt, groups.txt,
# etc., relative to their own repo).
#
# Idempotent — uses _EE_BOOTSTRAP_ENV_LOADED so it does not collide
# with other repos' lib/env.sh if they are sourced into the same shell
# (e.g., when an app's init.sh later sources scripts/lib/env.sh).
[ -n "${_EE_BOOTSTRAP_ENV_LOADED:-}" ] && return 0
export _EE_BOOTSTRAP_ENV_LOADED=1

_ENV_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# EE_ROOT points to the bootstrap repo root. App-level init scripts
# (e.g., apps/<app>/init.sh inside their own repo) override EE_ROOT
# to point at themselves after this file has been sourced.
EE_ROOT="$(cd "$_ENV_SH_DIR/../.." && pwd)"

# Project-relative roots — kept for parity with the monorepo env.sh.
INIT_ROOT="$EE_ROOT/init.d"
SCRIPT_ROOT="$INIT_ROOT"

export EE_ROOT INIT_ROOT SCRIPT_ROOT

# ---------------------------------------------------------------------------
# Toolchain version pins
#
# Versions may be overridden via env var. These are the versions the
# bootstrap host is expected to end up at — apps can rely on them.
# ---------------------------------------------------------------------------
export EE_GO_VERSION="${EE_GO_VERSION:-1.26.4}"
export EE_NODE_VERSION="${EE_NODE_VERSION:-24.5.0}"
export EE_PYTHON_VERSION="${EE_PYTHON_VERSION:-3.14}"
export EE_UV_VERSION="${EE_UV_VERSION:-0.8.13}"
export LAZYDOCKER_VERSION="${LAZYDOCKER_VERSION:-v0.25.2}"
export KILO_VERSION="${KILO_VERSION:-v7.4.1}"

# CGO off by default — host-level Go toolchain uses static binaries.
export CGO_ENABLED="${CGO_ENABLED:-0}"
