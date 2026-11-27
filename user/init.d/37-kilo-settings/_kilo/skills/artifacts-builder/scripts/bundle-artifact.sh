#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 1 ]]; then
  printf '%s\n' 'Usage: bash /path/to/artifacts-builder/scripts/bundle-artifact.sh <prepared-project-directory>' >&2
  exit 1
fi
command -v node >/dev/null || { printf '%s\n' 'Node >=22.9 is required; use the configured host toolchain.' >&2; exit 1; }
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# Sanitize before Node startup, which can write caches or execute preload hooks.
unset NODE_OPTIONS NODE_COMPILE_CACHE
export NODE_DISABLE_COMPILE_CACHE=1
exec node "$SCRIPT_DIR/artifact.mjs" bundle "$1"
