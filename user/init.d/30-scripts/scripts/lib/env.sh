# env.sh — derive SCRIPT_ROOT for maintain scripts
#
# Lives at $HOME/scripts/lib/env.sh. Sets SCRIPT_ROOT
# so maintain.d steps can source lib/maintain-common.sh.
#
# Idempotent — uses _MAINTAIN_ENV_LOADED sentinel.
[ -n "${_MAINTAIN_ENV_LOADED:-}" ] && return 0
export _MAINTAIN_ENV_LOADED=1

_ENV_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "$_ENV_SH_DIR/.." && pwd)"

export SCRIPT_ROOT
