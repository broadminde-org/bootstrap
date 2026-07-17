#!/usr/bin/env bash
# lib/env.sh — derive EE_ROOT and toolchain versions for user-side bootstrap.
#
# Lives at user-bootstrap/init.d/lib/env.sh. Sets EE_ROOT to the
# user-bootstrap folder (one level up from init.d/) so the user-side
# steps can locate llmdocs/, scripts/, vscode/, and opencode/ by
# relative path.
#
# Idempotent — uses _EE_USER_BOOTSTRAP_ENV_LOADED so it does not collide
# with bootstrap/init.d/lib/env.sh if both are sourced into the same
# shell (they will not be in normal flows, but defensive is cheap).
[ -n "${_EE_USER_BOOTSTRAP_ENV_LOADED:-}" ] && return 0
export _EE_USER_BOOTSTRAP_ENV_LOADED=1

_ENV_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# EE_ROOT points to the user-bootstrap folder. The root
# bootstrap/init.d/lib/env.sh sets EE_ROOT to the bootstrap repo root;
# this file is meant to be sourced AFTER the root bootstrap has handed
# off to a non-root user, so we override EE_ROOT here.
EE_ROOT="$(cd "$_ENV_SH_DIR/../.." && pwd)"

INIT_ROOT="$EE_ROOT/init.d"
SCRIPT_ROOT="$INIT_ROOT"

export EE_ROOT INIT_ROOT SCRIPT_ROOT

# ---------------------------------------------------------------------------
# Toolchain version pins
#
# Versions may be overridden via env var. These are the versions the
# user-bootstrap step installs in $HOME/.local/bin.
# ---------------------------------------------------------------------------
export EE_UV_VERSION="${EE_UV_VERSION:-0.8.13}"
export EE_PYTHON_VERSION="${EE_PYTHON_VERSION:-3.14}"
export KILO_VERSION="${KILO_VERSION:-v7.4.1}"
export EE_GO_VERSION="${EE_GO_VERSION:-1.26.4}"
export EE_NODE_VERSION="${EE_NODE_VERSION:-24.5.0}"

export CGO_ENABLED="${CGO_ENABLED:-0}"
